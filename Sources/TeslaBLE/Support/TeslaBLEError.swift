import Foundation

public enum TeslaBLEError: Error, Sendable {
    case bluetoothUnavailable
    case scanTimeout
    case connectionFailed(underlying: String)
    case serviceNotFound
    case characteristicsNotFound
    case notConnected
    case messageTooLarge
    case handshakeFailed(underlying: String)
    case fetchFailed(underlying: String)
    case addKeyFailed(underlying: String)
    case keychain(OSStatus)
}

extension TeslaBLEError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable:
            "Bluetooth is unavailable"
        case .scanTimeout:
            "Vehicle not found within scan timeout"
        case let .connectionFailed(underlying):
            "BLE connection failed: \(underlying)"
        case .serviceNotFound:
            "Tesla vehicle service not found on peripheral"
        case .characteristicsNotFound:
            "Tesla vehicle characteristics not found"
        case .notConnected:
            "Not connected to a vehicle"
        case .messageTooLarge:
            "Outgoing message exceeds maximum size"
        case let .handshakeFailed(underlying):
            "Session handshake failed: \(underlying)"
        case let .fetchFailed(underlying):
            "Vehicle data fetch failed: \(underlying)"
        case let .addKeyFailed(underlying):
            "AddKey request failed: \(underlying)"
        case let .keychain(status):
            "Keychain error (OSStatus \(status))"
        }
    }
}
