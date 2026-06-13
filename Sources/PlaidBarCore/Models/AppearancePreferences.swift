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
