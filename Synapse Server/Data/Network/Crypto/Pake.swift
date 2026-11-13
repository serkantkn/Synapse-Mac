//
//  Pake.swift
//  Synapse Server
//
//  PIN pairing without an offline-guessable proof (CPace-style PAKE on P-256).
//  Byte-for-byte the same as Pake.swift in the iOS app and Pake.kt in the Android app.
//

import Foundation
import CryptoKit

/// Password-authenticated key exchange for the first pairing.
///
/// The old PIN proof was an HMAC over public data, so anyone who captured it could try all
/// 1,000,000 PINs offline. Here the PIN only picks the curve point both sides use for one extra
/// Diffie-Hellman exchange. An eavesdropper can't check a PIN guess without breaking that
/// exchange, and an active attacker gets one guess per attempt, which the attempt limit caps.
///
/// Messages (the phone always initiates):
/// 1. phone → here  `HANDSHAKE_REQUEST`  `auth_mode` "pake", `public_key`, `pake_share` (Ya)
/// 2. here → phone  `HANDSHAKE_RESPONSE` `status` "CHALLENGE", `public_key`, `pake_share` (Yb), `pake_confirm` (Cb)
/// 3. phone → here  `HANDSHAKE_CONFIRM`  `pake_confirm` (Ca)
/// 4. here → phone  `HANDSHAKE_RESPONSE` `status` "ACCEPTED", `public_key`
///
/// The resulting key (ISK) takes the PIN's place in the session-key derivation.
enum Pake {
    static let authMode = "pake"

    enum Role: String {
        case initiator, responder
    }

    enum PakeError: Error {
        case noGenerator
        case invalidShare
    }

    private static let label = "synapse-cpace-v1"
    /// Candidates tried for the generator; each is on the curve with probability ~1/2.
    private static let generatorAttempts = 64

    /// A curve point picked by the PIN and the initiator's session key. Nobody knows its
    /// discrete logarithm, which is what keeps PIN guesses from being checked offline.
    static func generator(pin: String, initiatorKey: String) throws -> P256.KeyAgreement.PublicKey {
        var found: P256.KeyAgreement.PublicKey?
        // Every candidate is tried, so the time taken doesn't depend on the PIN.
        for counter in 0..<generatorAttempts {
            var input = Data("\(label):generator".utf8)
            input.append(UInt8(counter))
            input.append(lengthPrefixed(Data(pin.utf8)))
            input.append(lengthPrefixed(Data(initiatorKey.utf8)))
            let x = Data(SHA256.hash(data: input))
            let candidate = try? point(x: x)
            if found == nil { found = candidate }
        }
        guard let found else { throw PakeError.noGenerator }
        return found
    }

    /// One side of the exchange: a fresh secret scalar and the share sent to the peer.
    struct Party {
        let role: Role
        let pin: String
        let initiatorKey: String
        let share: Data
        private let scalar: P256.KeyAgreement.PrivateKey

        /// `scalar` is only passed in tests; otherwise every exchange gets a fresh one.
        init(role: Role, pin: String, initiatorKey: String,
             scalar: P256.KeyAgreement.PrivateKey = P256.KeyAgreement.PrivateKey()) throws {
            self.role = role
            self.pin = pin
            self.initiatorKey = initiatorKey
            self.scalar = scalar
            share = try Pake.xCoordinate(scalar, try Pake.generator(pin: pin, initiatorKey: initiatorKey))
        }

        /// The shared key (ISK). Both sides get the same value only if they used the same PIN.
        func sharedKey(peerShare: Data, responderKey: String) throws -> Data {
            guard peerShare.count == 32 else { throw PakeError.invalidShare }
            let k = try Pake.xCoordinate(scalar, try Pake.point(x: peerShare))
            let initiatorShare = role == .initiator ? share : peerShare
            let responderShare = role == .initiator ? peerShare : share
            var input = Data("\(Pake.label):isk".utf8)
            input.append(Pake.lengthPrefixed(Data(initiatorKey.utf8)))
            input.append(Pake.lengthPrefixed(Data(responderKey.utf8)))
            input.append(Pake.lengthPrefixed(initiatorShare))
            input.append(Pake.lengthPrefixed(responderShare))
            input.append(Pake.lengthPrefixed(k))
            return Data(SHA256.hash(data: input))
        }
    }

    /// Proves to the peer that `role` derived the same key.
    static func confirmation(key: Data, role: Role) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data("\(label):confirm:\(role.rawValue)".utf8),
                                             using: SymmetricKey(data: key)))
    }

    /// Constant-time check of the peer's confirmation.
    static func verifyConfirmation(_ confirmation: Data, key: Data, role: Role) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(confirmation,
                                               authenticating: Data("\(label):confirm:\(role.rawValue)".utf8),
                                               using: SymmetricKey(data: key))
    }

    // MARK: - Helpers

    /// The curve point with this x and an even y. Throws when x isn't on the curve.
    private static func point(x: Data) throws -> P256.KeyAgreement.PublicKey {
        try P256.KeyAgreement.PublicKey(compressedRepresentation: Data([0x02]) + x)
    }

    /// x(scalar · point). Only the x coordinate is exchanged, which is all ECDH exposes; the
    /// sign of y doesn't change the x of a multiple, so both sides still agree.
    private static func xCoordinate(_ scalar: P256.KeyAgreement.PrivateKey,
                                    _ point: P256.KeyAgreement.PublicKey) throws -> Data {
        try scalar.sharedSecretFromKeyAgreement(with: point).withUnsafeBytes { Data($0) }
    }

    private static func lengthPrefixed(_ data: Data) -> Data {
        var length = UInt32(data.count).bigEndian
        return Data(bytes: &length, count: 4) + data
    }
}
