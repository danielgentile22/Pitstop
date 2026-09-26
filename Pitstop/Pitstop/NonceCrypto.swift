import CryptoKit
import Foundation

/// Sign in with Apple nonces: Apple gets `sha256(raw)` in the request and embeds it in the
/// identity token; the backend gets `raw` and checks it hashes to that value, blocking token replay.
enum NonceCrypto {

    /// URL-safe random nonce. Bytes outside the charset range are rejected, avoiding modulo bias.
    static func generateRawNonce(length: Int = 32) -> String {
        precondition(length > 0, "Nonce length must be positive")
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = [Character]()
        result.reserveCapacity(length)
        var remaining = length

        while remaining > 0 {
            var batch = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, batch.count, &batch)
            precondition(status == errSecSuccess,
                         "SecRandomCopyBytes failed with OSStatus \(status)")

            for byte in batch {
                guard remaining > 0 else { break }
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }

        return String(result)
    }

    /// Lowercase hex digest.
    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
