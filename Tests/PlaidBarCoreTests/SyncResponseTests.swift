import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Sync response payloads")
struct SyncResponseTests {
    @Test("Sync cursor commit request carries cursors and cursor update times")
    func commitRequest() {
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let request = SyncCursorCommitRequest(
            cursors: ["item-1": "cursor-1"],
            cursorUpdatedAts: ["item-1": updatedAt]
        )
        #expect(request.cursors["item-1"] == "cursor-1")
        #expect(request.cursorUpdatedAts["item-1"] == updatedAt)
    }

    @Test("Decoding cursor commit request tolerates missing cursor update times")
    func decodeCommitRequestWithoutCursorUpdatedAts() throws {
        let json = #"{"cursors":{"item-1":"cursor-1"}}"#
        let request = try JSONDecoder().decode(SyncCursorCommitRequest.self, from: Data(json.utf8))
        #expect(request.cursors["item-1"] == "cursor-1")
        #expect(request.cursorUpdatedAts.isEmpty)
    }

    @Test("Memberwise init defaults pending cursors to empty")
    func memberwiseInit() {
        let response = SyncResponse(added: [], modified: [], removed: [], hasMore: true)
        #expect(response.pendingCursors.isEmpty)
        #expect(response.pendingCursorUpdatedAts.isEmpty)
        #expect(response.hasMore)
    }

    @Test("Decoding tolerates a missing pendingCursors field")
    func decodeDefaultsPendingCursors() throws {
        let json = #"{"added":[],"modified":[],"removed":["t1"],"hasMore":false}"#
        let response = try JSONDecoder().decode(SyncResponse.self, from: Data(json.utf8))
        #expect(response.pendingCursors.isEmpty)
        #expect(response.pendingCursorUpdatedAts.isEmpty)
        #expect(response.hasMore == false)
        #expect(response.removed == ["t1"])
    }

    @Test("Decoding reads present pending cursor fields")
    func decodePendingCursors() throws {
        // The wire contract for cursor-update timestamps is ISO-8601 date
        // strings: the server encodes `SyncResponse` with an `.iso8601`
        // `JSONEncoder` (TransactionRoutes) and the app's `ServerClient`
        // decodes with an `.iso8601` `JSONDecoder`. Decode the way production
        // does so this test exercises the real round-trip rather than the
        // default `.deferredToDate` reference-date strategy.
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let json = #"""
        {"added":[],"modified":[],"removed":[],"hasMore":true,"pendingCursors":{"item-1":"c1"},"pendingCursorUpdatedAts":{"item-1":"2027-01-15T08:01:40Z"}}
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(SyncResponse.self, from: Data(json.utf8))
        #expect(response.pendingCursors["item-1"] == "c1")
        #expect(response.pendingCursorUpdatedAts["item-1"] == updatedAt)
    }

    @Test("Cursor update times round-trip losslessly through the ISO-8601 wire contract")
    func cursorUpdatedAtsRoundTripISO8601() throws {
        // Mirrors the production encode/decode pair: server encodes the response
        // with `.iso8601`, the app decodes with `.iso8601`. The timestamp must
        // survive the round-trip so a committed cursor's observation time is
        // preserved (the basis of #685's "pending until cursor commit" clear).
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let original = SyncResponse(
            added: [],
            modified: [],
            removed: [],
            hasMore: false,
            pendingCursors: ["item-1": "c1"],
            pendingCursorUpdatedAts: ["item-1": updatedAt]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SyncResponse.self, from: try encoder.encode(original))
        #expect(decoded.pendingCursorUpdatedAts["item-1"] == updatedAt)
    }
}
