import Foundation

/// Observable state of a `TeslaVehicleClient`'s BLE session.
public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case scanning
    case connecting
    case handshaking
    case connected
}
