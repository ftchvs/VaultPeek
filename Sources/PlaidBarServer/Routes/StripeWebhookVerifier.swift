import CryptoKit
import Foundation

/// Verifies the authenticity of an incoming Stripe webhook before its normalized
/// projection is applied to billing state.
///
/// Mirrors the Plaid webhook path: the default implementation is **fail-closed**
/// (`UnconfiguredStripeWebhookVerifier`), so the seam rejects every event until a
/// real signing-secret-backed verifier is wired. This prevents a forged or
/// unsigned event from granting premium or raising the managed-link institution
/// limit once the route is exposed for real Stripe delivery.
protocol StripeWebhookVerifier: Sendable {
    /// Verifies `payload` (the EXACT received request bytes) against
    /// `signatureHeader` (the `Stripe-Signature` header). Throws on any failure;
    /// the caller must mutate no state when this throws.
    func verify(payload: Data, signatureHeader: String?, now: Date) async throws
}

enum StripeWebhookVerificationError: Error, Equatable {
    case signatureVerificationUnavailable
    case missingSignatureHeader
    case malformedSignatureHeader
    case timestampOutOfTolerance
    case signatureMismatch
}

/// Fail-closed default: rejects every webhook until a signing-secret-backed
/// verifier is configured. This is the production default until Stripe webhook
/// signature verification is wired (see `docs/strategy/stripe-entitlement-seam.md`).
struct UnconfiguredStripeWebhookVerifier: StripeWebhookVerifier {
    func verify(payload: Data, signatureHeader: String?, now: Date) async throws {
        throw StripeWebhookVerificationError.signatureVerificationUnavailable
    }
}

/// Verifies Stripe's `Stripe-Signature` header by recomputing the HMAC-SHA256 of
/// `"{t}.{rawBody}"` with the endpoint signing secret, over the EXACT received
/// bytes — never a re-serialized projection. Rejects stale timestamps (replay)
/// and any signature that does not match. Wire this with the configured signing
/// secret to make the seam production-ready.
struct StripeSignatureWebhookVerifier: StripeWebhookVerifier {
    let signingSecret: String
    var tolerance: TimeInterval = 5 * 60

    func verify(payload: Data, signatureHeader: String?, now: Date = Date()) async throws {
        guard let signatureHeader else {
            throw StripeWebhookVerificationError.missingSignatureHeader
        }
        let parsed = try Self.parse(signatureHeader)
        guard abs(now.timeIntervalSince1970 - parsed.timestamp) <= tolerance else {
            throw StripeWebhookVerificationError.timestampOutOfTolerance
        }
        var signedPayload = Data(parsed.timestampField.utf8)
        signedPayload.append(0x2e) // "."
        signedPayload.append(payload)
        let mac = HMAC<SHA256>.authenticationCode(
            for: signedPayload,
            using: SymmetricKey(data: Data(signingSecret.utf8))
        )
        let expected = mac.map { String(format: "%02x", $0) }.joined()
        guard parsed.signatures.contains(where: { Self.constantTimeEquals($0, expected) }) else {
            throw StripeWebhookVerificationError.signatureMismatch
        }
    }

    private static func parse(
        _ header: String
    ) throws -> (timestampField: String, timestamp: TimeInterval, signatures: [String]) {
        var timestampField: String?
        var signatures: [String] = []
        for element in header.split(separator: ",") {
            let pair = element.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let key = pair[0].trimmingCharacters(in: .whitespaces)
            let value = pair[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "t": timestampField = value
            case "v1": signatures.append(value)
            default: break
            }
        }
        guard let timestampField,
              let timestamp = TimeInterval(timestampField),
              !signatures.isEmpty
        else {
            throw StripeWebhookVerificationError.malformedSignatureHeader
        }
        return (timestampField, timestamp, signatures)
    }

    /// Length-checked, constant-time hex comparison.
    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        guard lhsBytes.count == rhsBytes.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhsBytes, rhsBytes) {
            difference |= left ^ right
        }
        return difference == 0
    }
}
