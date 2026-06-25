import CryptoKit
import Foundation

/// Real ES256 (ECDSA P-256 / SHA-256) signature validator for Plaid webhook
/// JWTs (AND-646).
///
/// GATED / NON-ACTIVATING BY DEFAULT. The shipped server still wires
/// `UnconfiguredPlaidWebhookSignatureValidator` (which always throws
/// `.signatureVerificationUnavailable`), so the webhook receiver stays dormant
/// exactly as before. This type only participates when the operator explicitly
/// opts in via `PlaidWebhookVerificationConfig` (see `ServerConfig`); absent
/// that opt-in nothing constructs it and webhook processing remains off.
///
/// Plaid signs each webhook with an ES256 JWT in the `Plaid-Verification`
/// header. Verification has two halves, split here so each is independently
/// testable:
///   1. **Structural / claims / body-hash** checks — already done by
///      `StrictPlaidWebhookVerifier` (alg, iat skew, request-body SHA-256).
///   2. **Cryptographic signature** — this type. It resolves the EC public key
///      for the JWT's `kid` from a `PlaidWebhookKeySource`, reconstructs the
///      JWS signing input (`header.payload`), and verifies the P-256 signature.
///
/// The cryptographic core (`verifySignature`) takes a `P256.Signing.PublicKey`
/// and is fully unit-testable with a synthetic keypair — no Plaid call, no
/// credentials. Production key resolution (fetch-by-`kid` from Plaid's
/// `/webhook_verification_key/get`) lives behind `PlaidWebhookKeySource` and is
/// only constructed when the operator provisions it.
struct ES256PlaidWebhookSignatureValidator: PlaidWebhookSignatureValidator {
    let keySource: any PlaidWebhookKeySource

    func validate(jwt: String, header: PlaidWebhookJWTHeader, claims: PlaidWebhookJWTClaims) async throws {
        guard let kid = header.kid, !kid.isEmpty else {
            throw PlaidWebhookSignatureError.missingKeyID
        }
        let key = try await keySource.publicKey(forKeyID: kid)
        try Self.verifySignature(jwt: jwt, publicKey: key)
    }

    /// Verifies the ES256 signature of a compact JWS string against a P-256
    /// public key. Pure and synchronous: reconstructs the signing input
    /// (`base64url(header) "." base64url(payload)`), decodes the third segment
    /// as the raw 64-byte `r||s` signature, and checks it with SHA-256/P-256.
    /// Throws on any structural or cryptographic failure (never returns `false`).
    static func verifySignature(jwt: String, publicKey: P256.Signing.PublicKey) throws {
        let components = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else {
            throw PlaidWebhookSignatureError.malformedJWT
        }
        let signingInput = "\(components[0]).\(components[1])"
        guard let signingData = signingInput.data(using: .utf8) else {
            throw PlaidWebhookSignatureError.malformedJWT
        }
        let signatureBytes = try base64URLDecode(String(components[2]))
        // JWS ES256 signatures are the raw fixed-width concatenation r||s
        // (32 + 32 bytes), not DER. CryptoKit's `rawRepresentation` initializer
        // expects exactly that layout.
        guard signatureBytes.count == 64 else {
            throw PlaidWebhookSignatureError.malformedSignature
        }
        let signature: P256.Signing.ECDSASignature
        do {
            signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureBytes)
        } catch {
            throw PlaidWebhookSignatureError.malformedSignature
        }
        guard publicKey.isValidSignature(signature, for: SHA256.hash(data: signingData)) else {
            throw PlaidWebhookSignatureError.signatureMismatch
        }
    }

    private static func base64URLDecode(_ value: String) throws -> Data {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        guard let data = Data(base64Encoded: base64) else {
            throw PlaidWebhookSignatureError.malformedSignature
        }
        return data
    }
}

/// Resolves the EC public key Plaid signed a webhook with, keyed by the JWT
/// `kid`. Abstracted so the cryptographic validator stays testable with a
/// synthetic key and the production fetch (Plaid `/webhook_verification_key/get`,
/// which needs the server's Plaid credentials) is injected, cached, and
/// owner-gated.
protocol PlaidWebhookKeySource: Sendable {
    func publicKey(forKeyID kid: String) async throws -> P256.Signing.PublicKey
}

/// A `kid`-indexed, in-memory set of trusted P-256 keys. Used by tests (with a
/// synthetic keypair) and as the storage shape a real Plaid-backed resolver
/// would populate. Pure and `Sendable`; never reaches out to the network.
struct StaticPlaidWebhookKeySource: PlaidWebhookKeySource {
    let keysByID: [String: P256.Signing.PublicKey]

    func publicKey(forKeyID kid: String) async throws -> P256.Signing.PublicKey {
        guard let key = keysByID[kid] else {
            throw PlaidWebhookSignatureError.unknownKeyID
        }
        return key
    }
}

/// Parses a Plaid `JWK` (`{"kty":"EC","crv":"P-256","x":..,"y":..}`) into a
/// `P256.Signing.PublicKey`. Plaid's `/webhook_verification_key/get` returns the
/// signing key in exactly this JWK shape, so a real key source can decode the
/// response into this DTO and build the key with no extra crypto plumbing.
struct PlaidWebhookJWK: Decodable, Sendable, Equatable {
    let kty: String
    let crv: String
    let x: String
    let y: String
    let kid: String?

    /// Builds the P-256 public key from the JWK's affine coordinates. The X9.63
    /// uncompressed-point encoding CryptoKit expects is `0x04 || x || y`, each
    /// coordinate a fixed 32-byte big-endian integer (base64url in the JWK).
    func publicKey() throws -> P256.Signing.PublicKey {
        guard kty == "EC", crv == "P-256" else {
            throw PlaidWebhookSignatureError.unsupportedKeyType
        }
        let xBytes = try Self.base64URLDecode(x)
        let yBytes = try Self.base64URLDecode(y)
        guard xBytes.count == 32, yBytes.count == 32 else {
            throw PlaidWebhookSignatureError.malformedKey
        }
        var x963 = Data([0x04])
        x963.append(xBytes)
        x963.append(yBytes)
        do {
            return try P256.Signing.PublicKey(x963Representation: x963)
        } catch {
            throw PlaidWebhookSignatureError.malformedKey
        }
    }

    private static func base64URLDecode(_ value: String) throws -> Data {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        guard let data = Data(base64Encoded: base64) else {
            throw PlaidWebhookSignatureError.malformedKey
        }
        return data
    }
}

enum PlaidWebhookSignatureError: Error, Equatable {
    case missingKeyID
    case unknownKeyID
    case malformedJWT
    case malformedSignature
    case malformedKey
    case unsupportedKeyType
    case signatureMismatch
}
