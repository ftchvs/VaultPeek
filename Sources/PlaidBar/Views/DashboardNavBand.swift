import PlaidBarCore
import SwiftUI

// MARK: - Account Filters

/// The dashboard account filter is the core `DashboardAccountFilterKind`
/// reused directly. The persisted `@AppStorage("dashboard.accountFilter")`
/// raw values ("All", "Cash", "Credit", "Savings", "Debt", "Status") are the
/// core enum's raw values, so stored selections decode exactly as before.
typealias DashboardAccountFilter = DashboardAccountFilterKind

extension DashboardAccountFilterKind {
    /// View-layer convenience that resolves degraded item ids from app state.
    @MainActor
    func includes(_ account: AccountDTO, appState: AppState) -> Bool {
        includes(account, degradedItemIds: appState.degradedItemIds)
    }
}

// MARK: - Filter Bar

/// Native segmented control for the dashboard's primary filter. Native
/// before novel: the system control brings focus rings, vibrancy, light
/// mode, and RTL for free. ⌘1–6 shortcuts are preserved via hidden
/// equivalents; the per-filter counts live in the rows themselves and in
/// each segment's help/accessibility text rather than in segment labels.
struct DashboardFilterBar: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: DashboardAccountFilter
    /// Whether an account row is drilled in, so the container's VoiceOver
    /// label keeps the row-selection state the old caption used to announce.
    let hasSelectedAccount: Bool

    var body: some View {
        let items = DashboardNavBarModel.items(
            accounts: appState.accounts,
            degradedItemIds: appState.degradedItemIds
        )

        Picker("Account filter", selection: $selection) {
            ForEach(items) { item in
                Text(item.title)
                    .accessibilityLabel(item.accessibilityLabel)
                    .accessibilityValue(item.accessibilityValue)
                    .tag(item.kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .help(rollupText(items: items))
        .background {
            // Hidden, non-interactive keyboard equivalents: ⌘1-6 switch
            // filters exactly as the old custom segments did.
            ForEach(items) { item in
                Button("") { selection = item.kind }
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
        .accessibilityElement(children: .contain)
        // The selected-filter rollup lives in the container *label*, not the
        // container value: macOS VoiceOver announces a group's label when
        // entering it but does not reliably read a group's AXValue. The
        // per-segment counts are rolled into the label too, because per-item
        // modifiers do not reliably survive NSSegmentedControl bridging.
        .accessibilityLabel(
            "\(DashboardNavBarModel.containerAccessibilityLabel(selected: selection, items: items, hasSelectedAccount: hasSelectedAccount)). \(rollupText(items: items))"
        )
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
}
