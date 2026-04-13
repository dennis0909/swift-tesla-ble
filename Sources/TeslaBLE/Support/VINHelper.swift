import CryptoKit
import Foundation

/// Computes the BLE advertisement local name for a Tesla vehicle.
///
/// Tesla vehicles advertise a deterministic BLE local name derived from their
/// VIN. TeslaBLE's scanner uses this helper to filter discovered
/// peripherals by exact local-name match.
enum VINHelper {
    /// Computes the BLE advertisement local name for a given VIN.
    ///
    /// Format: `"S"` + first 8 bytes of `SHA1(VIN)` as lowercase hex + `"C"`.
    static func bleLocalName(for vin: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(vin.utf8))
        let first8 = digest.prefix(8)
        let hex = first8.map { String(format: "%02x", $0) }.joined()
        return "S\(hex)C"
    }
}
