import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Sync response payloads")
struct SyncResponseTests {
    @Test("Sync cursor commit request carries its cursors")
    func commitRequest() {
        let request = SyncCursorCommitRequest(cursors: ["item-1": "cursor-1"])
        #expect(request.cursors["item-1"] == "cursor-1")
    }

    @Test("Memberwise init defaults pending cursors to empty")
    func memberwiseInit() {
        let response = SyncResponse(added: [], modified: [], removed: [], hasMore: true)
        #expect(response.pendingCursors.isEmpty)
        #expect(response.hasMore)
    }

    @Test("Decoding tolerates a missing pendingCursors field")
    func decodeDefaultsPendingCursors() throws {
        let json = #"{"added":[],"modified":[],"removed":["t1"],"hasMore":false}"#
        let response = try JSONDecoder().decode(SyncResponse.self, from: Data(json.utf8))
        #expect(response.pendingCursors.isEmpty)
        #expect(response.hasMore == false)
        #expect(response.removed == ["t1"])
    }

    @Test("Decoding reads a present pendingCursors field")
    func decodePendingCursors() throws {
        let json = #"{"added":[],"modified":[],"removed":[],"hasMore":true,"pendingCursors":{"item-1":"c1"}}"#
        let response = try JSONDecoder().decode(SyncResponse.self, from: Data(json.utf8))
        #expect(response.pendingCursors["item-1"] == "c1")
    }
}
