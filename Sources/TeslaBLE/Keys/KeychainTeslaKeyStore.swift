import CryptoKit
import Foundation
import Security

/// Default Keychain-backed `TeslaKeyStore`.
///
/// Keys are stored under `kSecClassGenericPassword` with account format
/// `"privateKey-<VIN>"` and accessibility
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. The raw representation is
/// `P256.KeyAgreement.PrivateKey.x963Representation` (65 bytes:
/// `0x04 || X || Y` for the public point plus the 32-byte private scalar).
///
/// To migrate from a legacy `KeyManager` that used the account format
/// `"privateKey-<VIN>"` with a known `service`, construct with that same
/// `service` and existing keys load transparently.
public struct KeychainTeslaKeyStore: TeslaKeyStore {
    private let service: String

    public init(service: String) {
        self.service = service
    }

    public func loadPrivateKey(forVIN vin: String) throws -> P256.KeyAgreement.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: vin),
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw TeslaBLEError.keychain(status)
        }
        return try P256.KeyAgreement.PrivateKey(x963Representation: data)
    }

    public func savePrivateKey(_ key: P256.KeyAgreement.PrivateKey, forVIN vin: String) throws {
        try deletePrivateKey(forVIN: vin)
        let data = key.x963Representation
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: vin),
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TeslaBLEError.keychain(status)
        }
    }

    public func deletePrivateKey(forVIN vin: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: vin),
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TeslaBLEError.keychain(status)
        }
    }

    private func account(for vin: String) -> String {
        "privateKey-\(vin)"
    }
}
