import Foundation

/// FNV-1a 64-bit hashing — dependency-free and stable across process launches.
///
/// Swift's `Hasher` is per-process salted, so it can't be persisted; this is the
/// shared implementation behind every place that needs a stable string
/// fingerprint (cache filenames, sync-diff identities, Spotlight identifiers,
/// logo cache keys). Previously copy-pasted into four files across all three
/// targets — kept here once so the algorithm can never drift between the writers
/// and readers of a persisted hash.
///
/// Two hex renderings are offered because existing on-disk/identifier formats
/// depend on them and must not change: `hexPadded` (fixed 16-char width) and
/// `hex` (minimal width). They wrap the same `fnv1a64` value.
public enum StableHash {
    /// Raw FNV-1a 64-bit hash of the string's UTF-8 bytes.
    public static func fnv1a64(_ value: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV offset basis
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3 // FNV prime
        }
        return hash
    }

    /// Lowercase hex, zero-padded to a fixed 16 characters.
    public static func hexPadded(_ value: String) -> String {
        String(format: "%016llx", fnv1a64(value))
    }

    /// Lowercase hex with no leading-zero padding (variable width).
    public static func hex(_ value: String) -> String {
        String(fnv1a64(value), radix: 16)
    }
}
