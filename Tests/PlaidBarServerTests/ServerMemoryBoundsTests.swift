import Foundation
@testable import PlaidBarServer
import Testing

/// Covers the bounded in-memory accumulations hardened in AND-666:
/// the Stripe billing idempotency set and the merchant-logo proxy size cap.
@Suite("Server in-memory bounds (AND-666)")
struct ServerMemoryBoundsTests {
    // MARK: - Stripe billing idempotency set

    @Test("Idempotency set de-dups within the retained window")
    func idempotencySetDeDupsWithinWindow() async throws {
        let store = StripeBillingEventStore(capacity: 8)

        #expect(await store.recordIfNew("evt_a") == true)
        #expect(await store.recordIfNew("evt_a") == false)  // immediate replay
        #expect(await store.recordIfNew("evt_b") == true)
        #expect(await store.recordIfNew("evt_b") == false)
        #expect(await store.recordIfNew("evt_a") == false)  // still remembered
        #expect(await store.count == 2)
    }

    @Test("Idempotency set never exceeds its capacity under many distinct inserts")
    func idempotencySetStaysBounded() async throws {
        let capacity = 16
        let store = StripeBillingEventStore(capacity: capacity)

        // Insert far more distinct ids than the cap; the set must never exceed it.
        for index in 0..<(capacity * 50) {
            #expect(await store.recordIfNew("evt_\(index)") == true)
            #expect(await store.count <= capacity)
        }
        #expect(await store.count == capacity)
    }

    @Test("FIFO eviction forgets the oldest id once the window slides past it")
    func idempotencySetEvictsOldestFIFO() async throws {
        let capacity = 4
        let store = StripeBillingEventStore(capacity: capacity)

        // Fill the window exactly: insertion order is evt_0 (oldest)..evt_3.
        for index in 0..<capacity {
            #expect(await store.recordIfNew("evt_\(index)") == true)
        }
        // evt_0 is still in-window, so a replay de-dups (and a duplicate does not
        // re-append, so it does not refresh evt_0's eviction position).
        #expect(await store.recordIfNew("evt_0") == false)

        // Push a new id; the window is full so the oldest id (evt_0) is evicted.
        #expect(await store.recordIfNew("evt_new") == true)
        #expect(await store.count == capacity)

        // The evicted id is no longer remembered, so it reads as new again. This
        // is acceptable: a post-eviction replay re-applies an idempotent save.
        #expect(await store.recordIfNew("evt_0") == true)

        // A still-in-window id continues to de-dup.
        #expect(await store.recordIfNew("evt_new") == false)
        #expect(await store.recordIfNew("evt_2") == false)
    }

    @Test("Capacity is clamped to at least one")
    func idempotencySetClampsCapacity() async throws {
        let store = StripeBillingEventStore(capacity: 0)
        #expect(await store.recordIfNew("evt_only") == true)
        #expect(await store.count == 1)
        // Second distinct id evicts the first under the clamped capacity of 1.
        #expect(await store.recordIfNew("evt_second") == true)
        #expect(await store.count == 1)
    }

    // MARK: - Merchant-logo proxy size cap

    @Test("Logo proxy rejects an over-cap advertised Content-Length")
    func logoProxyRejectsOverCapContentLength() {
        let cap = MerchantLogoRoutes.maxLogoBytes
        // Advertised length over the cap is rejected even though no body has
        // streamed yet (actual byte count zero).
        #expect(MerchantLogoRoutes.exceedsLogoSizeLimit(
            advertisedContentLength: cap + 1,
            actualByteCount: 0
        ))
        // Exactly at the cap is allowed.
        #expect(!MerchantLogoRoutes.exceedsLogoSizeLimit(
            advertisedContentLength: cap,
            actualByteCount: cap
        ))
        // A normal small logo passes.
        #expect(!MerchantLogoRoutes.exceedsLogoSizeLimit(
            advertisedContentLength: 4_096,
            actualByteCount: 4_096
        ))
    }

    @Test("Logo proxy rejects an over-cap body even when Content-Length lies or is absent")
    func logoProxyRejectsOverCapBodyWithoutHonestHeader() {
        let cap = MerchantLogoRoutes.maxLogoBytes
        // No advertised header but the materialized body is over the cap.
        #expect(MerchantLogoRoutes.exceedsLogoSizeLimit(
            advertisedContentLength: nil,
            actualByteCount: cap + 1
        ))
        // Header understates the size (chunked / dishonest upstream); the actual
        // byte count still trips the cap.
        #expect(MerchantLogoRoutes.exceedsLogoSizeLimit(
            advertisedContentLength: 1_024,
            actualByteCount: cap + 1
        ))
    }

    @Test("Logo proxy streaming append stops before the buffer exceeds the cap")
    func logoProxyStreamingAppendStopsAtCap() {
        var full = Data(count: MerchantLogoRoutes.maxLogoBytes)
        #expect(!MerchantLogoRoutes.appendLogoByte(0x00, to: &full))
        #expect(full.count == MerchantLogoRoutes.maxLogoBytes)

        var oneByteUnder = Data(count: MerchantLogoRoutes.maxLogoBytes - 1)
        #expect(MerchantLogoRoutes.appendLogoByte(0x00, to: &oneByteUnder))
        #expect(oneByteUnder.count == MerchantLogoRoutes.maxLogoBytes)
        #expect(!MerchantLogoRoutes.appendLogoByte(0x00, to: &oneByteUnder))
        #expect(oneByteUnder.count == MerchantLogoRoutes.maxLogoBytes)
    }

    @Test("Logo proxy passes through a recognized image Content-Type and falls back otherwise")
    func logoProxyDerivesContentType() throws {
        let url = try #require(URL(string: "https://plaid-merchant-logos.plaid.com/x.png"))

        let pngResponse = try #require(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "image/svg+xml; charset=utf-8"]
        ))
        #expect(MerchantLogoRoutes.contentType(from: pngResponse) == "image/svg+xml")

        let htmlResponse = try #require(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        ))
        #expect(MerchantLogoRoutes.contentType(from: htmlResponse) == "image/png")

        let noHeaderResponse = try #require(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil, headerFields: [:]
        ))
        #expect(MerchantLogoRoutes.contentType(from: noHeaderResponse) == "image/png")
    }

    @Test("Cached logo bytes are sniffed back to the right content type")
    func logoProxySniffsCachedContentType() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(MerchantLogoRoutes.sniffContentType(of: png) == "image/png")

        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        #expect(MerchantLogoRoutes.sniffContentType(of: jpeg) == "image/jpeg")

        let svg = Data("<svg xmlns=".utf8)
        #expect(MerchantLogoRoutes.sniffContentType(of: svg) == "image/svg+xml")

        let unknown = Data([0x00, 0x01, 0x02, 0x03])
        #expect(MerchantLogoRoutes.sniffContentType(of: unknown) == "image/png")
    }
}
