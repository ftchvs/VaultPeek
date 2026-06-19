import Foundation
@testable import PlaidBarCore
import Testing

@Suite("StableHash Tests")
struct StableHashTests {
    @Test("fnv1a64: canonical FNV-1a 64-bit vectors")
    func canonicalVectors() {
        // Empty string hashes to the FNV-1a 64-bit offset basis.
        #expect(StableHash.fnv1a64("") == 0xcbf2_9ce4_8422_2325)
        // "a" is a published FNV-1a-64 reference vector.
        #expect(StableHash.fnv1a64("a") == 0xaf63_dc4c_8601_ec8c)
    }

    @Test("hexPadded: lowercase, fixed 16-character width")
    func hexPaddedFormat() {
        #expect(StableHash.hexPadded("") == "cbf29ce484222325")
        #expect(StableHash.hexPadded("a") == "af63dc4c8601ec8c")
        #expect(StableHash.hexPadded("account-1") == "de637fc248681e56")
        // A hash with a leading-zero nibble keeps the zero (always 16 chars).
        #expect(StableHash.hexPadded("k0") == "08be0e07b562230e")
        #expect(StableHash.hexPadded("k0").count == 16)
    }

    @Test("hex: lowercase, minimal width (leading zeros dropped)")
    func hexFormat() {
        #expect(StableHash.hex("") == "cbf29ce484222325")
        #expect(StableHash.hex("account-1") == "de637fc248681e56")
        // Same underlying value as hexPadded("k0") but with the leading zero gone.
        #expect(StableHash.hex("k0") == "8be0e07b562230e")
    }

    @Test("hex and hexPadded encode the same value, differing only in padding")
    func paddedVsUnpadded() {
        for input in ["", "a", "k0", "account-1", "https://example.com/logo.png"] {
            let value = StableHash.fnv1a64(input)
            #expect(StableHash.hexPadded(input).count == 16)
            #expect(UInt64(StableHash.hexPadded(input), radix: 16) == value)
            #expect(UInt64(StableHash.hex(input), radix: 16) == value)
        }
    }
}
