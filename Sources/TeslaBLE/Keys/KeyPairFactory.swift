import CryptoKit
import Foundation

/// Helpers for generating and serializing Tesla-compatible P-256 key pairs.
public enum KeyPairFactory {
    /// Generates a fresh P-256 ECDH private key.
    public static func generateKeyPair() -> P256.KeyAgreement.PrivateKey {
        P256.KeyAgreement.PrivateKey()
    }

    /// Returns the 65-byte uncompressed SEC1 representation of the key's
    /// public component (`0x04 || X || Y`), as required by
    /// `MobileSession.sendAddKeyRequest`.
    public static func publicKeyBytes(of key: P256.KeyAgreement.PrivateKey) -> Data {
        key.publicKey.x963Representation
    }
}
