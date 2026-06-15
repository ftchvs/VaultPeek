import CryptoKit
import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import PlaidBarCore

protocol PlaidWebhookVerifier: Sendable {
    func verify(jwt: String, body: Data, now: Date) async throws
}

protocol PlaidWebhookSignatureValidator: Sendable {
    func validate(jwt: String, header: PlaidWebhookJWTHeader, claims: PlaidWebhookJWTClaims) async throws
}

struct UnconfiguredPlaidWebhookSignatureValidator: PlaidWebhookSignatureValidator {
    func validate(jwt: String, header: PlaidWebhookJWTHeader, claims: PlaidWebhookJWTClaims) async throws {
        throw PlaidWebhookVerificationError.signatureVerificationUnavailable
    }
}

struct StrictPlaidWebhookVerifier: PlaidWebhookVerifier {
    var maxClockSkew: TimeInterval = 5 * 60
    var signatureValidator: any PlaidWebhookSignatureValidator = UnconfiguredPlaidWebhookSignatureValidator()

    func verify(jwt: String, body: Data, now: Date = Date()) async throws {
        let components = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else {
            throw PlaidWebhookVerificationError.malformedJWT
        }

        let decoder = JSONDecoder()
        let header = try decoder.decode(
            PlaidWebhookJWTHeader.self,
            from: Self.base64URLDecode(String(components[0]))
        )
        guard header.alg == "ES256" else {
            throw PlaidWebhookVerificationError.unsupportedAlgorithm
        }

        let claims = try decoder.decode(
            PlaidWebhookJWTClaims.self,
            from: Self.base64URLDecode(String(components[1]))
        )
        guard abs(now.timeIntervalSince1970 - TimeInterval(claims.iat)) <= maxClockSkew else {
            throw PlaidWebhookVerificationError.staleIssuedAt
        }

        guard let bodyHash = claims.requestBodySHA256 ?? claims.bodySHA256,
              bodyHash == Self.sha256Hex(body)
        else {
            throw PlaidWebhookVerificationError.bodyHashMismatch
        }

        try await signatureValidator.validate(jwt: jwt, header: header, claims: claims)
    }

    private static func base64URLDecode(_ value: String) throws -> Data {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        guard let data = Data(base64Encoded: base64) else {
            throw PlaidWebhookVerificationError.malformedJWT
        }
        return data
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct PlaidWebhookJWTHeader: Decodable, Sendable {
    let alg: String
    let kid: String?
}

struct PlaidWebhookJWTClaims: Decodable, Sendable {
    let iat: Int
    let requestBodySHA256: String?
    let bodySHA256: String?

    private enum CodingKeys: String, CodingKey {
        case iat
        case requestBodySHA256 = "request_body_sha256"
        case bodySHA256 = "body_hash"
    }
}

enum PlaidWebhookVerificationError: Error, Equatable {
    case malformedJWT
    case unsupportedAlgorithm
    case staleIssuedAt
    case bodyHashMismatch
    case signatureVerificationUnavailable
}

struct PlaidWebhookEvent: Decodable, Sendable {
    let webhookType: String
    let webhookCode: String
    let itemId: String
    let requestId: String?
    let timestamp: Date?

    private enum CodingKeys: String, CodingKey {
        case webhookType = "webhook_type"
        case webhookCode = "webhook_code"
        case itemId = "item_id"
        case requestId = "request_id"
        case timestamp
        case eventTime = "event_time"
        case updatedAt = "updated_at"
    }

    init(
        webhookType: String,
        webhookCode: String,
        itemId: String,
        requestId: String? = nil,
        timestamp: Date? = nil
    ) {
        self.webhookType = webhookType
        self.webhookCode = webhookCode
        self.itemId = itemId
        self.requestId = requestId
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        webhookType = try container.decode(String.self, forKey: .webhookType)
        webhookCode = try container.decode(String.self, forKey: .webhookCode)
        itemId = try container.decode(String.self, forKey: .itemId)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)

        timestamp = try Self.decodeDate(container, keys: [.timestamp, .eventTime, .updatedAt])
    }

    func signal(receivedAt: Date, bodyHash: String) -> WebhookItemSignal {
        WebhookItemSignal(
            itemId: itemId,
            webhookType: webhookType,
            webhookCode: webhookCode,
            requestId: requestId,
            idempotencyHash: Self.idempotencyHash(
                itemId: itemId,
                webhookType: webhookType,
                webhookCode: webhookCode,
                requestId: requestId,
                eventAt: timestamp,
                bodyHash: bodyHash
            ),
            eventAt: timestamp,
            receivedAt: receivedAt,
            status: Self.statusSignal(webhookCode: webhookCode),
            needsSync: Self.needsSync(webhookCode: webhookCode)
        )
    }

    static func statusSignal(webhookCode: String) -> WebhookItemStatusSignal {
        switch webhookCode {
        case "ERROR", "ITEM_LOGIN_REQUIRED":
            return .loginRequired
        case "LOGIN_REPAIRED", "PENDING_EXPIRATION":
            return .connected
        case "LOGIN_REPAIRED_WITH_NEW_ACCOUNTS":
            return .connected
        default:
            return .unchanged
        }
    }

    static func needsSync(webhookCode: String) -> Bool {
        [
            "DEFAULT_UPDATE",
            "HISTORICAL_UPDATE",
            "INITIAL_UPDATE",
            "TRANSACTIONS_REMOVED",
            "SYNC_UPDATES_AVAILABLE",
        ].contains(webhookCode)
    }

    static func idempotencyHash(
        itemId: String,
        webhookType: String,
        webhookCode: String,
        requestId: String?,
        eventAt: Date?,
        bodyHash: String
    ) -> String {
        let material = [
            itemId,
            webhookType,
            webhookCode,
            requestId ?? "",
            eventAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
            bodyHash,
        ].joined(separator: "\u{1f}")
        return StrictPlaidWebhookVerifier.sha256Hex(Data(material.utf8))
    }

    private static func decodeDate(
        _ container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) throws -> Date? {
        for key in keys {
            guard let value = try container.decodeIfPresent(String.self, forKey: key) else { continue }
            if let date = ISO8601DateFormatter().date(from: value) {
                return date
            }
        }
        return nil
    }
}

struct WebhookRoutes: Sendable {
    let verifier: any PlaidWebhookVerifier
    let tokenStore: TokenStore
    let eventStore: WebhookEventStore
    var now: @Sendable () -> Date = { Date() }

    func register(with router: Router<some RequestContext>) {
        router.group("webhooks")
            .post("plaid", use: receive)
    }

    @Sendable
    func receive(
        request: Request,
        context: some RequestContext
    ) async throws -> Response {
        guard let headerName = HTTPField.Name("Plaid-Verification"),
              let jwt = request.headers[headerName]
        else {
            throw HTTPError(.unauthorized, message: "Missing Plaid webhook verification header")
        }

        let buffer = try await request.body.collect(upTo: Self.maxBodyBytes)
        let body = Data(buffer: buffer)
        try await verifier.verify(jwt: jwt, body: body, now: now())

        let event: PlaidWebhookEvent
        do {
            event = try Self.decoder.decode(PlaidWebhookEvent.self, from: body)
        } catch {
            throw HTTPError(.badRequest, message: "Invalid Plaid webhook payload")
        }

        let signal = event.signal(
            receivedAt: now(),
            bodyHash: StrictPlaidWebhookVerifier.sha256Hex(body)
        )
        let result = try await eventStore.record(signal)
        if result.disposition == .stored {
            try await apply(signal)
        }

        return try Self.jsonResponse(WebhookReceiveResponse(disposition: result.disposition.rawValue))
    }

    private func apply(_ signal: WebhookItemSignal) async throws {
        guard try await tokenStore.getItem(id: signal.itemId) != nil else { return }
        switch signal.status {
        case .connected:
            try await tokenStore.updateItemStatus(id: signal.itemId, status: ItemConnectionStatus.connected.rawValue)
        case .loginRequired:
            try await tokenStore.updateItemStatus(id: signal.itemId, status: ItemConnectionStatus.loginRequired.rawValue)
        case .error:
            try await tokenStore.updateItemStatus(id: signal.itemId, status: ItemConnectionStatus.error.rawValue)
        case .unchanged:
            break
        }
    }

    private static let maxBodyBytes = 128 * 1024

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func jsonResponse(_ value: some Encodable) throws -> Response {
        let data = try JSONEncoder().encode(value)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }
}

private struct WebhookReceiveResponse: Encodable {
    let disposition: String
}

private extension WebhookStoreResult.Disposition {
    var rawValue: String {
        switch self {
        case .stored: "stored"
        case .duplicate: "duplicate"
        case .outOfOrder: "out_of_order"
        }
    }
}
