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
        let json = #"{"added":[],"modified":[],"removed":[],"hasMore":true,"pendingCursors":{"item-1":"c1"},"pendingCursorUpdatedAts":{"item-1":1800000100}}"#
        let response = try JSONDecoder().decode(SyncResponse.self, from: Data(json.utf8))
        #expect(response.pendingCursors["item-1"] == "c1")
        #expect(response.pendingCursorUpdatedAts["item-1"] == Date(timeIntervalSince1970: 1_800_000_100))
    }
}
