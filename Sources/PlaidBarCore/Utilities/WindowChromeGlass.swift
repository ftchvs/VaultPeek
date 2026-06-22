import Foundation

/// Pure decision for the **window-first shell's chrome background** (Epic 10 /
/// AND-588).
///
/// VaultPeek's Liquid Glass is applied to the navigation layer only — the window
/// container background behind the sidebar / toolbar / nav bars — and **never**
/// to lists, tables, charts, or dense data. The window container
/// background is *custom* translucency (`.containerBackground(.ultraThinMaterial,
/// for: .window)`), and per the Epic 10 contract custom translucency must
/// self-manage its accessibility degradation rather than rely on the framework
/// to thin the material: when the user has **Reduce Transparency** on, the chrome
/// must fall back to a fully solid window background so it stays legible in light
/// and dark.
///
/// This is the SwiftUI-free decision the scene consults, so the rule is
/// unit-tested independently of AppKit/SwiftUI. The view layer maps
/// ``WindowChromeBackground/glass`` to the ultra-thin material and
/// ``WindowChromeBackground/solid`` to the opaque window background color.
public enum WindowChromeBackground: Sendable, Equatable {
    /// Liquid Glass: the ultra-thin material behind the navigation chrome.
    case glass
    /// Opaque, fully solid window background (the Reduce Transparency fallback).
    case solid
}

public enum WindowChromeGlass {
    /// Resolve the window-first shell's chrome background.
    ///
    /// - Parameter reduceTransparency: the resolved Reduce Transparency state —
    ///   `true` when the system accessibility setting is on **or** the user chose
    ///   reduced decorative effects (the system setting always wins; see
    ///   ``DecorativeEffectsPreference``). When `true` the chrome must be solid.
    /// - Returns: ``WindowChromeBackground/solid`` when transparency is reduced,
    ///   otherwise ``WindowChromeBackground/glass``.
    public static func chromeBackground(reduceTransparency: Bool) -> WindowChromeBackground {
        reduceTransparency ? .solid : .glass
    }

    /// Whether a given surface in the window-first shell is allowed to carry a
    /// Liquid Glass material. Glass is for the **navigation layer** only; **data**
    /// surfaces (lists, tables, charts, dense rows) always stay solid so values
    /// never sample a translucent backdrop.
    ///
    /// This encodes the chrome-vs-data policy as a pure, testable rule: the view
    /// layer classifies each surface as ``WindowSurfaceKind`` and this decides
    /// whether glass may be applied. It is intentionally independent of Reduce
    /// Transparency — that gates *how* glass degrades
    /// (``chromeBackground(reduceTransparency:)``), whereas this gates *whether* a
    /// surface is eligible for glass at all.
    public static func allowsGlass(on surface: WindowSurfaceKind) -> Bool {
        switch surface {
        case .chrome:
            return true
        case .data:
            return false
        }
    }
}

/// Classifies a window-first surface for the glass-on-chrome-only policy.
/// `CaseIterable` so the chrome-vs-data policy can be asserted exhaustively in
/// tests — every surface kind has an explicit glass eligibility.
public enum WindowSurfaceKind: Sendable, Equatable, CaseIterable {
    /// Navigation chrome — sidebar, toolbar, nav bars, window container. May use
    /// Liquid Glass.
    case chrome
    /// Data — lists, tables, charts, dense rows / values. Always solid; never
    /// glass.
    case data
}
