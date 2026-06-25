import Foundation
import Testing
@testable import PlaidBarCore

@Suite("Window-first orientation copy")
struct WindowFirstOrientationCopyTests {
    // MARK: - Shipped copy shape

    @Test("Standard copy has a title, subtitle, three points, and a dismiss control")
    func standardShape() {
        let copy = WindowFirstOrientationCopy.standard

        #expect(!copy.title.isEmpty)
        #expect(!copy.subtitle.isEmpty)
        #expect(copy.points.count == 3)
        #expect(!copy.dismissButtonTitle.isEmpty)
        #expect(!copy.dismissAccessibilityLabel.isEmpty)
        #expect(!copy.dismissAccessibilityHint.isEmpty)
    }

    @Test("The three points cover the menu-bar glance, the window workspace, and shared privacy")
    func pointsCoverTheThreeOrientationBeats() {
        let copy = WindowFirstOrientationCopy.standard
        let ids = copy.points.map(\.id)

        #expect(ids == ["menuBar", "window", "privacy"])
        // Each point is fully populated so the view never renders an empty row.
        for point in copy.points {
            #expect(!point.id.isEmpty)
            #expect(!point.systemImage.isEmpty)
            #expect(!point.title.isEmpty)
            #expect(!point.body.isEmpty)
        }
    }

    @Test("Point ids are unique so they are stable ForEach identities")
    func pointIdsAreUnique() {
        let ids = WindowFirstOrientationCopy.standard.points.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("The privacy point names both App Lock and Privacy Mask and that they cover both surfaces")
    func privacyPointMentionsBothControlsAndBothSurfaces() {
        guard let privacy = WindowFirstOrientationCopy.standard.points.first(where: { $0.id == "privacy" }) else {
            Issue.record("Expected a privacy orientation point")
            return
        }
        let text = "\(privacy.title) \(privacy.body)"
        #expect(text.contains("App Lock"))
        #expect(text.contains("Privacy Mask"))
        // The orientation's whole point: privacy applies to BOTH surfaces.
        #expect(text.localizedCaseInsensitiveContains("both"))
    }

    // MARK: - Privacy-safe (no financial values)

    @Test("Orientation copy carries no digits — it is pure orientation, never a value surface")
    func copyContainsNoFinancialValues() {
        // The orientation moment must be safe to show under Privacy Mask / App Lock,
        // so it must contain no numbers (which could read as balances/amounts).
        let allText = ([
            WindowFirstOrientationCopy.standard.title,
            WindowFirstOrientationCopy.standard.subtitle,
            WindowFirstOrientationCopy.standard.dismissButtonTitle,
            WindowFirstOrientationCopy.standard.dismissAccessibilityLabel,
            WindowFirstOrientationCopy.standard.dismissAccessibilityHint,
        ] + WindowFirstOrientationCopy.standard.points.flatMap { [$0.title, $0.body] })
            .joined(separator: " ")

        let containsDigit = allText.contains { $0.isNumber }
        #expect(containsDigit == false)
    }

    // MARK: - Accessibility

    @Test("Each point's accessibility label folds title and body into one announced phrase")
    func pointAccessibilityLabelFoldsTitleAndBody() {
        for point in WindowFirstOrientationCopy.standard.points {
            #expect(point.accessibilityLabel == "\(point.title). \(point.body)")
        }
    }

    @Test("The sheet accessibility summary contains the title, subtitle, and every point")
    func accessibilitySummaryContainsEverything() {
        let copy = WindowFirstOrientationCopy.standard
        let summary = copy.accessibilitySummary

        #expect(summary.contains(copy.title))
        #expect(summary.contains(copy.subtitle))
        for point in copy.points {
            #expect(summary.contains(point.accessibilityLabel))
        }
    }

    // MARK: - Value semantics

    @Test("Copy is Equatable by value")
    func equatableByValue() {
        #expect(WindowFirstOrientationCopy.standard == WindowFirstOrientationCopy.standard)

        let mutated = WindowFirstOrientationCopy(
            title: "Different",
            subtitle: WindowFirstOrientationCopy.standard.subtitle,
            points: WindowFirstOrientationCopy.standard.points,
            dismissButtonTitle: WindowFirstOrientationCopy.standard.dismissButtonTitle,
            dismissAccessibilityLabel: WindowFirstOrientationCopy.standard.dismissAccessibilityLabel,
            dismissAccessibilityHint: WindowFirstOrientationCopy.standard.dismissAccessibilityHint
        )
        #expect(mutated != WindowFirstOrientationCopy.standard)
    }
}
