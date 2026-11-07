//
//  CryptoManager.swift
//  Synapse Server
//
//  ECDH key exchange + AES-256-GCM encryption.
//  Uses Apple's CryptoKit for modern, hardware-accelerated crypto.
//

import Foundation
import CryptoKit

/// Manages the ECDH key exchange and AES-256-GCM encryption/decryption lifecycle.
final class CryptoManager {

    /// Our ECDH key pair.
    private(set) var privateKey: P256.KeyAgreement.PrivateKey
    var sharedSymmetricKey: SymmetricKey?

    init() {
        self.privateKey = P256.KeyAgreement.PrivateKey()
        self.sharedSymmetricKey = nil
    }

    // MARK: - Key Exchange

    /// Returns our public key as a Base64-encoded string.
    func publicKeyBase64() -> String {
        return Data(privateKey.publicKey.x963Representation).base64EncodedString()
    }

    /// Decodes a Base64-encoded peer public key (x963 format).
    func decodePeerPublicKey(_ base64String: String) throws -> P256.KeyAgreement.PublicKey {
        guard let data = Data(base64Encoded: base64String) else {
            throw CryptoError.invalidKey
        }
        return try P256.KeyAgreement.PublicKey(x963Representation: data)
    }

    /// Performs ECDH key agreement and derives a shared AES-256 symmetric key.
    /// `authSecret` (PIN bytes or the stored device token) is mixed into the HKDF info, so a peer
    /// that doesn't know it ends up with a different key. Must match Android's CryptoManager.
    func deriveSharedSecret(peerPublicKey: P256.KeyAgreement.PublicKey, authSecret: Data) throws {
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        self.sharedSymmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("SynapseEncryption".utf8),
            sharedInfo: Data("synapse-session-v1:".utf8) + authSecret,
            outputByteCount: 32 // 256-bit key
        )
    }

    // MARK: - Pairing authentication

    static let authModePin = "pin"
    static let authModeToken = "token"

    /// Base64(HMAC-SHA256(secret, "synapse-auth-v1:<mode>:<initiatorPublicKeyBase64>")).
    static func authProof(secret: Data, mode: String, publicKeyBase64: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data("synapse-auth-v1:\(mode):\(publicKeyBase64)".utf8),
            using: SymmetricKey(data: secret)
        )
        return Data(mac).base64EncodedString()
    }

    /// Constant-time check of a proof received from the initiator.
    static func verifyAuthProof(_ proofBase64: String, secret: Data, mode: String, publicKeyBase64: String) -> Bool {
        guard let proof = Data(base64Encoded: proofBase64) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(
            proof,
            authenticating: Data("synapse-auth-v1:\(mode):\(publicKeyBase64)".utf8),
            using: SymmetricKey(data: secret)
        )
    }

    /// Long-term pairing token derived from the current (PIN-authenticated) session key.
    func deriveDeviceToken() -> String? {
        guard let key = sharedSymmetricKey else { return nil }
        let mac = HMAC<SHA256>.authenticationCode(for: Data("synapse-device-token-v1".utf8), using: key)
        return Data(mac).base64EncodedString()
    }

    /// Clears the shared key and generates a fresh key pair for the next session.
    func resetSharedSecret() {
        sharedSymmetricKey = nil
        privateKey = P256.KeyAgreement.PrivateKey()
    }

    // MARK: - Encryption / Decryption

    /// Encrypts data using AES-256-GCM. Returns nonce + ciphertext + tag.
    func encrypt(_ data: Data) throws -> Data {
        guard let key = sharedSymmetricKey else {
            throw CryptoError.noSharedKey
        }
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }
        return combined
    }

    /// Decrypts data that was encrypted with AES-256-GCM.
    func decrypt(_ data: Data) throws -> Data {
        guard let key = sharedSymmetricKey else {
            throw CryptoError.noSharedKey
        }
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    enum CryptoError: Error, LocalizedError {
        case invalidKey
        case noSharedKey
        case encryptionFailed

        var errorDescription: String? {
            switch self {
            case .invalidKey: return "Geçersiz anahtar formatı"
            case .noSharedKey: return "Paylaşılan anahtar henüz oluşturulmadı"
            case .encryptionFailed: return "Şifreleme başarısız"
            }
        }
    }
}
