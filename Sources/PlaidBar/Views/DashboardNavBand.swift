import PlaidBarCore
import SwiftUI

// MARK: - Account Filters

/// The dashboard account filter is the core `DashboardAccountFilterKind`
/// reused directly. It is persisted by the per-window `NavigationModel` under the
/// `dashboard.accountFilter` key (AND-594) using the core enum's raw values
/// ("All", "Cash", "Credit", "Savings", "Debt", "Investments", "Status"), so
/// stored selections decode exactly as the previous view-level `@AppStorage` did.
typealias DashboardAccountFilter = DashboardAccountFilterKind

extension DashboardAccountFilterKind {
    /// View-layer convenience that resolves degraded item ids from app state.
    @MainActor
    func includes(_ account: AccountDTO, appState: AppState) -> Bool {
        includes(account, degradedItemIds: appState.degradedItemIds)
    }
}

// MARK: - Filter Bar

/// Segmented control for the dashboard's primary filter with an animated
/// shared-element reflow (AND-577): a single glass selection pill glides between
/// segments via `matchedGeometryEffect` rather than the selection cutting
/// instantly from one to the next. Quiet and premium, not flashy.
///
/// This is a custom control rather than `Picker(.segmented)` because the
/// AppKit-bridged `NSSegmentedControl` does not expose its selection indicator
/// to SwiftUI's geometry system, so a matched-geometry glide is impossible on
/// it. The custom control re-earns the affordances the bridge gave for free:
/// per-segment VoiceOver label/value, a container rollup label, ⌘1–⌘N
/// shortcuts, the Status attention glyph, light/dark, and RTL (the `HStack`
/// flips with layout direction, and the pill glides along with it).
///
/// Additive + reversible: with Reduce Motion on, the pill snaps instantly with
/// no geometry animation — the exact end state the native control produced
/// before this change. The selection itself is never altered here.
struct DashboardFilterBar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: DashboardAccountFilter
    /// Whether an account row is drilled in, so the container's VoiceOver
    /// label keeps the row-selection state the old caption used to announce.
    let hasSelectedAccount: Bool

    /// Namespace for the gliding selection pill. Scoped to this view so the
    /// matched-geometry pair never collides with the popover's glass namespace.
    @Namespace private var pillNamespace

    var body: some View {
        let items = DashboardNavBarModel.items(
            accounts: appState.accounts,
            degradedItemIds: appState.degradedItemIds
        )
        let statusItem = items.first { $0.kind == .status }

        HStack(spacing: Spacing.xs) {
            segmentedControl(items: items)
                .background { keyboardShortcuts(items: items) }
                .accessibilityElement(children: .contain)
                // The selected-filter rollup lives in the container *label*, not the
                // container value: macOS VoiceOver announces a group's label when
                // entering it but does not reliably read a group's AXValue. The
                // per-segment counts are rolled into the label too, for one
                // glanceable announcement of the whole bar.
                .accessibilityLabel(
                    "\(DashboardNavBarModel.containerAccessibilityLabel(selected: selection, items: items, hasSelectedAccount: hasSelectedAccount)). \(rollupText(items: items))"
                )

            // Visible, non-color attention signal for the Status segment. The
            // symbol's shape (not its tint) carries the meaning; the warning
            // color is redundant reinforcement only.
            if let statusItem, statusItem.showsAttentionBadge, let iconName = statusItem.statusIconName {
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundStyle(SemanticColors.warning)
                    .help(statusItem.statusIndicatorAccessibilityLabel ?? "Needs attention")
                    .accessibilityLabel(statusItem.statusIndicatorAccessibilityLabel ?? "Needs attention")
            }
        }
    }

    // MARK: - Segmented control

    private func segmentedControl(items: [DashboardNavBarItem]) -> some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                segment(for: item)
            }
        }
        .padding(SegmentMetrics.trackPadding)
        .background(track)
        .help(rollupText(items: items))
    }

    private func segment(for item: DashboardNavBarItem) -> some View {
        let isSelected = DashboardFilterReflowModel.isSelected(item.kind, selected: selection)

        return Button {
            select(item.kind)
        } label: {
            Text(item.title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : AppearanceTextColors.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, SegmentMetrics.horizontalPadding)
                .padding(.vertical, SegmentMetrics.verticalPadding)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .background {
                    // The single gliding pill: rendered only behind the selected
                    // segment. matchedGeometryEffect carries the same logical view
                    // from one segment's frame to the next on selection change, so
                    // the pill interpolates its position — it slides rather than
                    // cross-fades. Under Reduce Motion the assignment happens with
                    // no animation, so the pill jumps (today's behavior).
                    if isSelected {
                        selectionPill
                            .matchedGeometryEffect(
                                id: DashboardFilterReflowModel.geometryIDPrefix,
                                in: pillNamespace
                            )
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(item.accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .help(item.helpText)
    }

    private var selectionPill: some View {
        RoundedRectangle(cornerRadius: SegmentMetrics.pillRadius, style: .continuous)
            .fill(Color.primary.opacity(SurfaceTokens.selectedFillOpacity))
            .overlay {
                RoundedRectangle(cornerRadius: SegmentMetrics.pillRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(SurfaceTokens.panelStrokeOpacity), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
    }

    private var track: some View {
        RoundedRectangle(cornerRadius: SegmentMetrics.trackRadius, style: .continuous)
            .fill(Color.primary.opacity(SurfaceTokens.insetFillOpacity))
            .overlay {
                RoundedRectangle(cornerRadius: SegmentMetrics.trackRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(SurfaceTokens.panelStrokeOpacity), lineWidth: 1)
            }
    }

    /// Applies the selection and, unless Reduce Motion is on, glides the pill to
    /// the new segment. With Reduce Motion on the assignment is made outside any
    /// animation, so the pill snaps instantly — identical to the prior control.
    private func select(_ kind: DashboardAccountFilter) {
        guard kind != selection else { return }
        if DashboardFilterReflowModel.shouldAnimateGlide(reduceMotion: reduceMotion) {
            withAnimation(MotionTokens.standard) {
                selection = kind
            }
        } else {
            selection = kind
        }
    }

    /// Hidden, non-interactive keyboard equivalents: ⌘1-N switch filters exactly
    /// as the prior segmented control did. They route through `select(_:)` so
    /// keyboard switches glide too (and snap under Reduce Motion).
    private func keyboardShortcuts(items: [DashboardNavBarItem]) -> some View {
        ForEach(items) { item in
            Button("") { select(item.kind) }
                .keyboardShortcut(
                    KeyEquivalent(Character("\(item.shortcutOrdinal)")),
                    modifiers: .command
                )
                .buttonStyle(.plain)
                .focusable(false)
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// "All 4, Cash 2, Credit 2 (needs attention), …" — counts for every
    /// segment, used in the container accessibility label and the tooltip.
    private func rollupText(items: [DashboardNavBarItem]) -> String {
        items.map { item in
            item.showsAttentionBadge
                ? "\(item.title) \(item.count), needs attention"
                : "\(item.title) \(item.count)"
        }
        .joined(separator: ", ")
    }

    private enum SegmentMetrics {
        static let horizontalPadding: CGFloat = Spacing.sm
        static let verticalPadding: CGFloat = Spacing.xxs + 1
        static let trackPadding: CGFloat = 2
        static let trackRadius: CGFloat = Radius.control
        static let pillRadius: CGFloat = Radius.control - 1
    }
}
