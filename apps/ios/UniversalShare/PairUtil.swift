import CryptoKit
import Foundation

/// PIN asla ağa gönderilmez. Sunucunun gönderdiği hex salt'a HMAC-SHA256 proof
/// üretilir. Go proof.go ile aynı algoritma: HMAC(key=PIN, msg=saltHex) → hex.
enum PairUtil {
    static func proof(pin: String, saltHex: String) -> String {
        let key = SymmetricKey(data: Data(pin.utf8))
        let msg = Data(saltHex.utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: msg, using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}
