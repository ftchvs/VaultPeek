import Foundation

/// Local-only appearance & display-comfort preferences for VaultPeek (AND-365).
///
/// These are pure, `Sendable` models with precedence rules so the resolution can
/// be unit-tested independently of SwiftUI/AppKit. The cardinal rule encoded
/// here: **system accessibility settings always win** over the app preference
/// (Reduce Motion, Reduce Transparency, Increase Contrast), and the
/// `--appearance` CLI override wins over the stored appearance mode.

// MARK: - Appearance mode

public enum AppAppearanceMode: String, CaseIterable, Sendable, Identifiable {
    case followSystem
    case light
    case dark

    public static let storageKey = "appearance.appColorScheme"
    public static let defaultValue: AppAppearanceMode = .followSystem

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .followSystem: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The color scheme this mode forces, or `nil` to follow the system.
    public var forcedScheme: ForcedColorScheme? {
        switch self {
        case .followSystem: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The effective forced scheme given a `--appearance` CLI override, which
    /// always wins (QA aid). `nil` means follow the system appearance.
    public static func resolvedScheme(
        cliOverride: ForcedColorScheme?,
        storedMode: AppAppearanceMode
    ) -> ForcedColorScheme? {
        cliOverride ?? storedMode.forcedScheme
    }
}

/// A concrete forced color scheme, kept SwiftUI-free so it lives in Core.
public enum ForcedColorScheme: String, Sendable, Equatable {
    case light
    case dark
}

// MARK: - Accent color

/// User-chosen brand/accent color (AND-647). This is **decorative/brand only** —
/// it tints hero glyphs, active controls, selection washes, and the app-wide
/// `.tint`. It MUST NEVER carry financial or status *meaning*: over/under budget,
/// gain/loss, currency, and sync status keep their own semantic colors plus the
/// non-color cues (icons, signs, labels) they already use, so changing the accent
/// can never flip the read of a value (ACCESSIBILITY.md). Mirrors the SwiftUI-free
/// Core pattern of `AppAppearanceMode`/`ForcedColorScheme`: the enum and its
/// resolution live here (pure, `Sendable`, unit-tested); the single SwiftUI
/// `Color` bridge lives in the app layer, alongside the `ForcedColorScheme →
/// ColorScheme` bridge.
public enum AppAccentColor: String, CaseIterable, Sendable, Identifiable {
    /// Follow the macOS system accent color (the default — VaultPeek does not
    /// override the user's system-wide choice unless they opt in here).
    case system
    case blue
    case purple
    case pink
    case red
    case orange
    case green
    case teal
    case graphite

    public static let storageKey = "appearance.accentColor"
    public static let defaultValue: AppAccentColor = .system

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .green: "Green"
        case .teal: "Teal"
        case .graphite: "Graphite"
        }
    }

    /// The resolved accent for this choice: `nil` swatch means "follow the system
    /// accent" (no app override). A concrete `AppAccentSwatch` is an sRGB triple
    /// the SwiftUI bridge turns into a `Color`. Kept pure so the choice → swatch
    /// mapping is unit-testable without SwiftUI/AppKit.
    public var swatch: AppAccentSwatch? {
        switch self {
        case .system: nil
        // sRGB components chosen to track Apple's system palette closely while
        // staying legible as a tint in both light and dark. These are brand
        // decoration only — never a semantic finance/status color.
        case .blue: AppAccentSwatch(red: 0.0, green: 0.478, blue: 1.0)
        case .purple: AppAccentSwatch(red: 0.686, green: 0.322, blue: 0.871)
        case .pink: AppAccentSwatch(red: 1.0, green: 0.176, blue: 0.333)
        case .red: AppAccentSwatch(red: 1.0, green: 0.231, blue: 0.188)
        case .orange: AppAccentSwatch(red: 1.0, green: 0.584, blue: 0.0)
        case .green: AppAccentSwatch(red: 0.196, green: 0.804, blue: 0.196)
        case .teal: AppAccentSwatch(red: 0.188, green: 0.69, blue: 0.78)
        case .graphite: AppAccentSwatch(red: 0.557, green: 0.557, blue: 0.576)
        }
    }

    /// Resolve the effective accent given an optional CLI override (a QA aid that
    /// mirrors `--appearance`) and the stored choice. The override wins, exactly
    /// like `AppAppearanceMode.resolvedScheme`. A `nil` result means "follow the
    /// system accent" (no app-level tint override).
    public static func resolvedSwatch(
        cliOverride: AppAccentColor?,
        storedAccent: AppAccentColor
    ) -> AppAccentSwatch? {
        (cliOverride ?? storedAccent).swatch
    }
}

/// An sRGB color triple for an accent, kept SwiftUI-free so it lives in Core.
/// The app layer bridges this to a single SwiftUI `Color`; Core stays testable.
public struct AppAccentSwatch: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

// MARK: - Contrast

public enum AppContrastPreference: String, CaseIterable, Sendable, Identifiable {
    case followSystem
    case standard
    case increased

    public static let storageKey = "appearance.contrast"
    public static let defaultValue: AppContrastPreference = .followSystem

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .followSystem: "Follow System"
        case .standard: "Standard"
        case .increased: "Increased"
        }
    }

    /// Whether increased contrast applies. The system "Increase Contrast"
    /// accessibility setting always wins; otherwise the app preference decides.
    public func resolvedIncreasedContrast(systemIncreaseContrast: Bool) -> Bool {
        if systemIncreaseContrast { return true }
        return self == .increased
    }
}

// MARK: - Decorative effects

public enum DecorativeEffectsPreference: String, CaseIterable, Sendable, Identifiable {
    case followSystem
    case on
    case reduced

    public static let storageKey = "appearance.decorativeEffects"
    public static let defaultValue: DecorativeEffectsPreference = .followSystem

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .followSystem: "Follow System"
        case .on: "On"
        case .reduced: "Reduced"
        }
    }

    /// Resolve which optional effects may render. `reduced` turns them off; the
    /// other modes defer to the system, which always wins: Reduce Motion gates
    /// motion and Reduce Transparency gates texture/glow.
    public func resolved(
        systemReduceMotion: Bool,
        systemReduceTransparency: Bool
    ) -> ResolvedDecorativeEffects {
        let userReduced = (self == .reduced)
        return ResolvedDecorativeEffects(
            allowsMotion: !systemReduceMotion && !userReduced,
            allowsTexture: !systemReduceTransparency && !userReduced
        )
    }
}

public struct ResolvedDecorativeEffects: Sendable, Equatable {
    public let allowsMotion: Bool
    public let allowsTexture: Bool

    public init(allowsMotion: Bool, allowsTexture: Bool) {
        self.allowsMotion = allowsMotion
        self.allowsTexture = allowsTexture
    }
}

// MARK: - Density

public enum AppDensityPreference: String, CaseIterable, Sendable, Identifiable {
    case comfortable
    case compact

    public static let storageKey = "appearance.density"
    public static let defaultValue: AppDensityPreference = .comfortable

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .comfortable: "Comfortable"
        case .compact: "Compact"
        }
    }
}
