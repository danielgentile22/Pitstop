//
//  NonceCrypto.swift
//  GeoPoop
//
//  Nonce utilities for Sign in with Apple.
//
//  The protocol requires a two-value nonce:
//    • rawNonce   — a cryptographically random string, sent to Supabase so it
//                   can verify the round-trip.
//    • hashedNonce — SHA-256(rawNonce), sent to Apple in the auth request.
//                   Apple embeds it in the returned identity-token JWT.
//
//  Supabase receives both: it hashes the rawNonce itself and confirms it
//  matches the hash Apple embedded in the JWT. This prevents replay attacks
//  where a stolen token is submitted without the matching rawNonce.
//

import CryptoKit
import Foundation

enum NonceCrypto {

    /// Generates a cryptographically random URL-safe nonce string.
    ///
    /// Uses `SecRandomCopyBytes` (CSPRNG) to sample from a 66-character
    /// charset. Characters outside the charset are discarded (rejection
    /// sampling) so there is no modulo bias.
    static func generateRawNonce(length: Int = 32) -> String {
        precondition(length > 0, "Nonce length must be positive")
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = [Character]()
        result.reserveCapacity(length)
        var remaining = length

        while remaining > 0 {
            // Generate a batch of 16 raw bytes at a time to amortize
            // the syscall overhead of SecRandomCopyBytes.
            var batch = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, batch.count, &batch)
            precondition(status == errSecSuccess,
                         "SecRandomCopyBytes failed — OSStatus \(status)")

            for byte in batch {
                guard remaining > 0 else { break }
                // Reject values that would cause modulo bias
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }

        return String(result)
    }

    /// Returns the lowercase hex-encoded SHA-256 digest of `input`.
    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
