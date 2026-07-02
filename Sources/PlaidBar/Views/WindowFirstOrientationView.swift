import PlaidBarCore
import SwiftUI

/// The one-time **window-first orientation moment** (AND-640): a first-launch
/// sheet shown on the primary `Window` to users arriving from the menu-bar era.
///
/// It explains the two surfaces — the menu bar is the calm glance, the window is
/// the deeper workspace — and that the privacy controls (App Lock / Privacy Mask)
/// apply to **both**. It carries only orientation copy (no financial values), so
/// it is safe regardless of Privacy Mask / App Lock state.
///
/// The copy is the pure, headless `WindowFirstOrientationCopy` model in
/// `PlaidBarCore`, so the wording is unit-tested and this view is a thin renderer.
/// Presentation (gating on the per-environment dismissal flag + the window-first
/// feature flag, and persisting dismissal) is owned by the `Window` scene; this
/// view only renders and reports dismissal via `onDismiss`.
struct WindowFirstOrientationView: View {
    /// Reduce Motion gates the once-per-appearance icon reveal so the sheet does
    /// not animate for users who asked for less motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let copy: WindowFirstOrientationCopy
    let onDismiss: () -> Void

    /// Drives the gentle staggered fade-in of the orientation points. Flipped on
    /// appear; under Reduce Motion the change is applied without animation so the
    /// content is simply present.
    @State private var hasAppeared = false

    init(
        copy: WindowFirstOrientationCopy = .standard,
        onDismiss: @escaping () -> Void
    ) {
        self.copy = copy
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            header

            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(copy.points) { point in
                    OrientationPointRow(point: point)
                }
            }

            dismissButton
        }
        .padding(Spacing.xl)
        .frame(width: 460)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            withAnimation(MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion)) {
                hasAppeared = true
            }
        }
        // One container element so VoiceOver announces the whole sheet as a single
        // coherent welcome (title + subtitle + each point), rather than reading
        // each fragment separately.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(copy.accessibilitySummary)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Image(systemName: "macwindow.badge.plus")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(SemanticColors.brand)
                .accessibilityHidden(true)

            Text(copy.title)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(copy.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // The container label already announces title + subtitle; hide the
        // duplicate visible text from VoiceOver so it is not read twice.
        .accessibilityHidden(true)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Text(copy.dismissButtonTitle)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel(copy.dismissAccessibilityLabel)
        .accessibilityHint(copy.dismissAccessibilityHint)
    }
}

/// A single orientation point: a brand-tinted SF Symbol beside a title and one
/// explanatory line. The glyph is decorative (hidden from VoiceOver); the row's
/// announced label is the pre-composed phrase from the pure copy model, so the
/// meaning is never carried by the icon (or its color) alone.
private struct OrientationPointRow: View {
    let point: WindowFirstOrientationCopy.Point

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: point.systemImage)
                .font(.title3.weight(.medium))
                .foregroundStyle(SemanticColors.brand)
                .frame(width: Sizing.iconChip)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(point.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Text(point.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .solidDataSurface(cornerRadius: Radius.panel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(point.accessibilityLabel)
    }
}

#if canImport(PreviewsMacros)
#Preview {
    WindowFirstOrientationView(onDismiss: {})
}
#endif
