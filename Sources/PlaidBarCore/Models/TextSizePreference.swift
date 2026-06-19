import Foundation

/// In-app text-size / display-scaling preference (AND-570).
///
/// macOS does **not** honor the system Dynamic Type setting for third-party
/// apps, so users cannot enlarge VaultPeek's text from System Settings the way
/// they can on iOS. VaultPeek's typography already *responds* to a
/// `DynamicTypeSize` environment value (`@ScaledMetric`, shipped in AND-515) —
/// this preference is the missing user control that *sets* that value, applied
/// once at the scene root so every surface scales together.
///
/// This is a pure, `Sendable`, SwiftUI-free Core model so the case → size
/// mapping, persisted `rawValue`, and display label can be unit-tested without
/// importing SwiftUI. The app layer maps `ForcedDynamicTypeSize` to the actual
/// `SwiftUI.DynamicTypeSize` (mirroring how `AppAppearanceMode` maps to
/// `ForcedColorScheme` → `SwiftUI.ColorScheme`).
///
/// The case set is intentionally clamped to the `.large … .accessibility3`
/// band that the hero/display typography in `Typography.swift` already supports
/// (`.dynamicTypeSize(.xSmall ... .accessibility3)`), so no surface is pushed
/// past a step it has decided to cap at.
public enum TextSizePreference: String, CaseIterable, Sendable, Identifiable {
    /// The macOS-standard text size — VaultPeek's default, equivalent to
    /// `DynamicTypeSize.large` (the system's "L" default step).
    case `default`
    /// One step up — `DynamicTypeSize.xLarge`.
    case large
    /// Two steps up — `DynamicTypeSize.xxLarge`.
    case xLarge
    /// The first accessibility step — `DynamicTypeSize.accessibility1`. Large
    /// enough to noticeably reflow layout; still within the typography clamp.
    case accessibility

    public static let storageKey = "appearance.textSize"
    public static let defaultValue: TextSizePreference = .default

    public var id: String { rawValue }

    /// Human-readable label shown in Settings.
    public var title: String {
        switch self {
        case .default: "Default"
        case .large: "Large"
        case .xLarge: "Extra Large"
        case .accessibility: "Accessibility"
        }
    }

    /// A short caption describing the relative effect, used as supplementary
    /// (never color-only) feedback next to the control.
    public var detail: String {
        switch self {
        case .default: "Standard macOS text size."
        case .large: "Slightly larger text across VaultPeek."
        case .xLarge: "Noticeably larger text across VaultPeek."
        case .accessibility: "Largest text — best for low vision; some layouts reflow."
        }
    }

    /// The SwiftUI-free Dynamic Type step this preference maps to. The app layer
    /// converts this to `SwiftUI.DynamicTypeSize` at the scene root.
    public var forcedDynamicTypeSize: ForcedDynamicTypeSize {
        switch self {
        case .default: .large
        case .large: .xLarge
        case .xLarge: .xxLarge
        case .accessibility: .accessibility1
        }
    }

    /// Resolves the effective step. A `--text-size` CLI override (QA aid) wins
    /// over the stored preference, mirroring how `--appearance` overrides the
    /// stored appearance mode. `nil` override → stored preference decides.
    public static func resolved(
        cliOverride: TextSizePreference?,
        storedPreference: TextSizePreference
    ) -> ForcedDynamicTypeSize {
        (cliOverride ?? storedPreference).forcedDynamicTypeSize
    }
}

/// A concrete Dynamic Type step, kept SwiftUI-free so it lives in Core and can
/// be unit-tested. The raw values match `SwiftUI.DynamicTypeSize` case names so
/// the app-layer bridge is an unambiguous 1:1 mapping.
public enum ForcedDynamicTypeSize: String, CaseIterable, Sendable, Equatable {
    case large
    case xLarge
    case xxLarge
    case accessibility1

    /// Monotonic rank (smallest → largest) for ordering/clamping logic and
    /// assertions, independent of the SwiftUI enum's `Comparable` conformance.
    public var rank: Int {
        switch self {
        case .large: 0
        case .xLarge: 1
        case .xxLarge: 2
        case .accessibility1: 3
        }
    }
}
