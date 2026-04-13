// Package mobile provides a gomobile-compatible bridge to tesla-vehicle-command.
// All exported types use only gomobile-compatible types: primitives, []byte, string, error,
// and exported structs/interfaces.
package mobile

import (
	"context"
	"crypto/ecdh"
	"crypto/elliptic"
	"errors"
	"fmt"
	"sync"
	"time"

	"google.golang.org/protobuf/proto"

	"github.com/teslamotors/vehicle-command/internal/authentication"
	"github.com/teslamotors/vehicle-command/pkg/connector"
	"github.com/teslamotors/vehicle-command/pkg/protocol/protobuf/vcsec"
	"github.com/teslamotors/vehicle-command/pkg/vehicle"
)

// BLETransport is the interface that Swift must implement to provide BLE connectivity.
// gomobile will generate the corresponding Swift/ObjC protocol.
type BLETransport interface {
	// Send transmits raw data to the vehicle over BLE.
	Send(data []byte) error
	// Recv blocks until data is received or the timeout expires.
	// Returns the received data or an error (including timeout).
	Recv(timeoutMs int64) ([]byte, error)
	// Close tears down the BLE connection.
	Close()
}

// bleConnectorAdapter wraps a BLETransport to implement connector.Connector.
type bleConnectorAdapter struct {
	transport BLETransport
	vin       string
	recvChan  chan []byte
	done      chan struct{}
	once      sync.Once
}

func newBLEConnectorAdapter(vin string, transport BLETransport) *bleConnectorAdapter {
	a := &bleConnectorAdapter{
		transport: transport,
		vin:       vin,
		recvChan:  make(chan []byte, connector.BufferSize),
		done:      make(chan struct{}),
	}
	go a.recvLoop()
	return a
}

// recvLoop continuously calls transport.Recv and pushes data into recvChan.
func (a *bleConnectorAdapter) recvLoop() {
	for {
		select {
		case <-a.done:
			return
		default:
		}
		// Use a 5-second polling timeout so we can check for shutdown periodically.
		data, err := a.transport.Recv(5000)
		if err != nil {
			// On timeout or transient error, keep looping unless closed.
			select {
			case <-a.done:
				return
			default:
				continue
			}
		}
		if len(data) > 0 {
			select {
			case a.recvChan <- data:
			case <-a.done:
				return
			}
		}
	}
}

func (a *bleConnectorAdapter) Receive() <-chan []byte {
	return a.recvChan
}

func (a *bleConnectorAdapter) Send(ctx context.Context, buffer []byte) error {
	return a.transport.Send(buffer)
}

func (a *bleConnectorAdapter) VIN() string {
	return a.vin
}

func (a *bleConnectorAdapter) Close() {
	a.once.Do(func() {
		close(a.done)
		a.transport.Close()
	})
}

func (a *bleConnectorAdapter) PreferredAuthMethod() connector.AuthMethod {
	return connector.AuthMethodGCM
}

func (a *bleConnectorAdapter) RetryInterval() time.Duration {
	return 3 * time.Second
}

func (a *bleConnectorAdapter) AllowedLatency() time.Duration {
	return 5 * time.Second
}

// Session wraps a tesla vehicle-command Vehicle for use from gomobile.
type Session struct {
	vehicle   *vehicle.Vehicle
	connector *bleConnectorAdapter
}

// NewSession creates a new Session.
//
// Parameters:
//   - vin: the vehicle identification number
//   - privateKeyBytes: the 32-byte ECDH P-256 private scalar
//   - transport: a BLETransport implementation (provided from Swift)
func NewSession(vin string, privateKeyBytes []byte, transport BLETransport) (*Session, error) {
	if transport == nil {
		return nil, errors.New("transport must not be nil")
	}
	if len(privateKeyBytes) != 32 {
		return nil, fmt.Errorf("privateKeyBytes must be 32 bytes (got %d)", len(privateKeyBytes))
	}

	privKey := authentication.UnmarshalECDHPrivateKey(privateKeyBytes)
	if privKey == nil {
		return nil, errors.New("invalid private key scalar")
	}

	conn := newBLEConnectorAdapter(vin, transport)
	v, err := vehicle.NewVehicle(conn, privKey, nil)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("failed to create vehicle: %w", err)
	}

	return &Session{
		vehicle:   v,
		connector: conn,
	}, nil
}

// Connect starts the dispatcher (BLE message routing layer) without establishing sessions.
// This is needed before SendAddKeyRequest can work.
// timeoutMs is the maximum time in milliseconds to wait for the dispatcher to start.
func (s *Session) Connect(timeoutMs int64) error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutMs)*time.Millisecond)
	defer cancel()

	if err := s.vehicle.Connect(ctx); err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	return nil
}

// Start connects to the vehicle and establishes VCSEC and Infotainment sessions.
// timeoutMs is the maximum time in milliseconds to wait for the handshake.
func (s *Session) Start(timeoutMs int64) error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutMs)*time.Millisecond)
	defer cancel()

	if err := s.vehicle.Connect(ctx); err != nil {
		return fmt.Errorf("connect: %w", err)
	}

	if err := s.vehicle.StartSession(ctx, nil); err != nil {
		return fmt.Errorf("start session: %w", err)
	}

	return nil
}

// GetVehicleState fetches all vehicle state categories and returns
// the combined results as serialized protobuf bytes.
// Each category result is a serialized carserver.VehicleData message.
// The returned bytes are a serialized carserver.VehicleData containing all fields.
func (s *Session) GetVehicleState(timeoutMs int64) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutMs)*time.Millisecond)
	defer cancel()

	categories := []vehicle.StateCategory{
		vehicle.StateCategoryCharge,
		vehicle.StateCategoryClimate,
		vehicle.StateCategoryDrive,
		vehicle.StateCategoryLocation,
		vehicle.StateCategoryClosures,
		vehicle.StateCategoryChargeSchedule,
		vehicle.StateCategoryPreconditioningSchedule,
		vehicle.StateCategoryTirePressure,
		vehicle.StateCategoryMedia,
		vehicle.StateCategoryMediaDetail,
		vehicle.StateCategorySoftwareUpdate,
		vehicle.StateCategoryParentalControls,
	}

	// Fetch each category and merge the protobuf bytes.
	// We use proto.Merge to combine VehicleData messages.
	var merged []byte

	for _, cat := range categories {
		data, err := s.vehicle.GetState(ctx, cat)
		if err != nil {
			// Skip categories that fail (e.g., infotainment asleep).
			continue
		}
		if data == nil {
			continue
		}

		serialized, err := proto.Marshal(data)
		if err != nil {
			continue
		}

		if merged == nil {
			merged = serialized
		} else {
			// Proto wire format allows concatenation for merging.
			merged = append(merged, serialized...)
		}
	}

	if merged == nil {
		return nil, errors.New("failed to retrieve any vehicle state")
	}

	return merged, nil
}

// GetDriveState fetches only the drive state (gear, speed, power, odometer, navigation).
// This is much faster than GetVehicleState since it makes a single BLE round-trip.
func (s *Session) GetDriveState(timeoutMs int64) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutMs)*time.Millisecond)
	defer cancel()

	data, err := s.vehicle.GetState(ctx, vehicle.StateCategoryDrive)
	if err != nil {
		return nil, fmt.Errorf("get drive state: %w", err)
	}
	if data == nil {
		return nil, errors.New("no drive state returned")
	}
	return proto.Marshal(data)
}

// SendAddKeyRequest sends a key-pairing request over BLE.
// The user must then tap their NFC card on the center console to approve.
//
// Parameters:
//   - publicKeyBytes: the 65-byte uncompressed P-256 public key to add
//   - isOwner: if true, the key gets owner-level permissions
//   - timeoutMs: maximum time in milliseconds for the operation
func (s *Session) SendAddKeyRequest(publicKeyBytes []byte, isOwner bool, timeoutMs int64) error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutMs)*time.Millisecond)
	defer cancel()

	pubKey, err := ecdh.P256().NewPublicKey(publicKeyBytes)
	if err != nil {
		// Try parsing as uncompressed point (with 0x04 prefix) via elliptic
		x, y := elliptic.UnmarshalCompressed(elliptic.P256(), publicKeyBytes)
		if x == nil {
			x, y = elliptic.Unmarshal(elliptic.P256(), publicKeyBytes)
		}
		if x == nil {
			return fmt.Errorf("invalid public key: %w", err)
		}
		// Re-encode as uncompressed for ecdh
		uncompressed := elliptic.Marshal(elliptic.P256(), x, y)
		pubKey, err = ecdh.P256().NewPublicKey(uncompressed)
		if err != nil {
			return fmt.Errorf("invalid public key: %w", err)
		}
	}

	return s.vehicle.SendAddKeyRequest(ctx, pubKey, isOwner, vcsec.KeyFormFactor_KEY_FORM_FACTOR_CLOUD_KEY)
}

// Stop disconnects from the vehicle and cleans up resources.
func (s *Session) Stop() {
	if s.vehicle != nil {
		s.vehicle.Disconnect()
	}
}
