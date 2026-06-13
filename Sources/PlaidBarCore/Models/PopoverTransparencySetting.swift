import Foundation

public struct PopoverTransparencySetting: Sendable, Equatable {
    public static let storageKey = "appearance.popoverTransparency"
    public static let defaultValue = 70.0
    public static let minimumValue = 20.0
    public static let maximumValue = 85.0

    public let value: Double

    public init(value: Double) {
        self.value = min(Self.maximumValue, max(Self.minimumValue, value))
    }

    public var displayPercent: Int {
        Int(value.rounded())
    }

    public var normalizedProgress: Double {
        (value - Self.minimumValue) / (Self.maximumValue - Self.minimumValue)
    }

    /// Higher transparency needs slightly more surface separation so cards
    /// remain readable over busy desktops. This is visual-only and does not
    /// change the persisted transparency value.
    public var surfaceDepthMultiplier: Double {
        let multiplier = 0.86 + (normalizedProgress * 0.28)
        return (multiplier * 100).rounded() / 100
    }

    /// Solid fill layered over `.ultraThinMaterial`. Lower values produce a
    /// more opaque panel; higher values preserve more desktop read-through.
    /// The floor keeps text and numeric finance values legible at maximum
    /// transparency.
    public var materialOverlayOpacity: Double {
        let progress = (value - Self.minimumValue) / (Self.maximumValue - Self.minimumValue)
        let opacity = 0.32 - (progress * 0.26)
        return (opacity * 100).rounded() / 100
    }

    /// Named quick-pick presets spanning the legible transparency range. They map
    /// to the anchor values (most opaque / recommended default / most glass) so
    /// the Appearance preset row stays in sync with the slider.
    public enum Preset: String, CaseIterable, Sendable, Identifiable {
        case solid
        case balanced
        case glass

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .solid: "Solid"
            case .balanced: "Balanced"
            case .glass: "Glass"
            }
        }

        public var value: Double {
            switch self {
            case .solid: PopoverTransparencySetting.minimumValue
            case .balanced: PopoverTransparencySetting.defaultValue
            case .glass: PopoverTransparencySetting.maximumValue
            }
        }
    }

    /// The preset whose value matches the current setting, for highlighting the
    /// active quick-pick. Nil when the value was fine-tuned off a preset.
    public var matchingPreset: Preset? {
        // Slider steps and preset values are whole numbers, so an exact match is
        // all that's needed; the small epsilon only guards Double comparison.
        Preset.allCases.first { abs($0.value - value) < 0.01 }
    }
}
