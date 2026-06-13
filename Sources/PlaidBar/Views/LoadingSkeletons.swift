import PlaidBarCore
import SwiftUI

// MARK: - Loading Redaction

/// Redacts a populated surface into placeholder bars while its first data
/// load is in flight. No-op outside the loading phase, so live and cached
/// content always render normally.
private struct LoadingRedaction: ViewModifier {
    let state: DashboardLoadState

    func body(content: Content) -> some View {
        if state.showsSkeleton {
            content
                .redacted(reason: .placeholder)
                .opacity(0.65)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(state.loadingAccessibilityLabel ?? "Loading")
        } else {
            content
        }
    }
}

extension View {
    func loadingRedaction(_ state: DashboardLoadState) -> some View {
        modifier(LoadingRedaction(state: state))
    }
}

// MARK: - Skeleton Pulse

/// Gentle opacity pulse for skeleton surfaces. Under Reduce Motion the
/// skeleton stays static — redaction alone carries the loading meaning, so
/// nothing depends on the movement.
private struct SkeletonPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(MotionTokens.loadingOpacity(isDimmed: isDimmed, reduceMotion: reduceMotion))
            .onAppear {
                startPulseIfAllowed()
            }
            .onChange(of: reduceMotion) { _, shouldReduceMotion in
                if shouldReduceMotion {
                    stopPulse()
                } else {
                    startPulseIfAllowed()
                }
            }
    }

    private func startPulseIfAllowed() {
        guard !reduceMotion else {
            stopPulse()
            return
        }

        isDimmed = false
        withAnimation(MotionTokens.animation(MotionTokens.loadingPulse, reduceMotion: reduceMotion)) {
            isDimmed = true
        }
    }

    private func stopPulse() {
        withAnimation(nil) {
            isDimmed = false
        }
    }
}

// MARK: - Account Row Skeletons

/// Redacted placeholder rows shown in place of the account list while the
/// first balances fetch is in flight. The placeholder copy never renders as
/// text — `.redacted(reason: .placeholder)` replaces it with neutral bars
/// sized like real rows, so boot reads as "loading" instead of "offline".
struct DashboardAccountRowSkeletonList: View {
    let loadState: DashboardLoadState
    var rowCount = 3

    private var accessibilityText: String {
        loadState.loadingAccessibilityLabel
            ?? "\(loadState.surface.loadingTitle). \(loadState.surface.loadingDetail)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< rowCount, id: \.self) { index in
                SkeletonAccountRow(showsDivider: index < rowCount - 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
        .modifier(SkeletonPulse())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .task {
            // Mirror ErrorBanner's announcement pattern: yield once so the
            // placeholder is mounted before VoiceOver speaks the load state.
            await Task.yield()
            AccessibilityNotification.Announcement(accessibilityText).post()
        }
    }
}

private struct SkeletonAccountRow: View {
    let showsDivider: Bool

    var body: some View {
        HStack(spacing: Spacing.compactRowContentSpacing) {
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(.quinary)
                .frame(width: Sizing.iconChip, height: Sizing.iconChip)

            VStack(alignment: .leading, spacing: Spacing.compactRowTextSpacing) {
                Text("Account placeholder")
                    .font(.callout.weight(.medium))
                Text("Checking ··0000 · Syncing")
                    .detailText()
            }
            .redacted(reason: .placeholder)

            Spacer(minLength: Spacing.compactRowContentSpacing)

            Text("$0,000.00")
                .dataText()
                .redacted(reason: .placeholder)
        }
        .padding(.horizontal, Spacing.compactRowHorizontalPadding)
        .padding(.vertical, Spacing.compactRowVerticalPadding)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Divider()
                    .opacity(0.4)
            }
        }
    }
}
