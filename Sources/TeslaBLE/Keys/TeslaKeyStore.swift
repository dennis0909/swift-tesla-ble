import CryptoKit
import Foundation

/// Pluggable storage for per-VIN Tesla ECDH private keys.
///
/// TeslaBLE reads and writes keys through this protocol so applications
/// can provide their own storage strategy (Keychain, file, iCloud, test
/// in-memory, etc). The default Keychain-backed implementation is
/// `KeychainTeslaKeyStore`.
public protocol TeslaKeyStore: Sendable {
    /// Returns the stored key for the given VIN, or `nil` if none exists.
    func loadPrivateKey(forVIN vin: String) throws -> P256.KeyAgreement.PrivateKey?

    /// Persists the given key, overwriting any existing entry for this VIN.
    func savePrivateKey(_ key: P256.KeyAgreement.PrivateKey, forVIN vin: String) throws

    /// Removes the stored key for the given VIN. Idempotent: no error if
    /// the key does not exist.
    func deletePrivateKey(forVIN vin: String) throws
}
