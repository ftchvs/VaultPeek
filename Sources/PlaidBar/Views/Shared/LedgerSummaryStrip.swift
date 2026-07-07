import PlaidBarCore
import SwiftUI

// MARK: - Ledger summary strip (design-elevation shared kit)
//
// The aggregate line above a filtered ledger: what the visible rows *sum to*,
// so a filter change answers "so what?" without scanning rows. Every figure
// arrives as a preformatted, mask-aware string — the strip renders, it never
// computes or formats money.

/// Horizontal aggregate strip: emphasized Net, labeled In / Out, row count,
/// and a trailing date-range caption, on a solid data surface (never glass —
/// R-08).
///
/// The Net figure uses the tabular data role (semibold, monospaced digits),
/// deliberately *not* the display-balance hero scale: this is a working
/// summary, not the page's headline. An optional trailing slot is reserved for
/// a future delta chip; it takes any view, so no Core delta type leaks in here.
struct LedgerSummaryStrip<Trailing: View>: View {
    /// Preformatted, mask-aware signed net ("−$1,204.18" or "••••").
    let netText: String
    /// Preformatted, mask-aware inflow total.
    let inText: String
    /// Preformatted, mask-aware outflow total.
    let outText: String
    /// How many rows the aggregates cover.
    let count: Int
    /// Preformatted range caption ("Mar 1 – Mar 31").
    let dateRangeText: String
    /// Reserved slot for a future delta chip; defaults to empty.
    @ViewBuilder var trailing: () -> Trailing

    init(
        netText: String,
        inText: String,
        outText: String,
        count: Int,
        dateRangeText: String,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.netText = netText
        self.inText = inText
        self.outText = outText
        self.count = count
        self.dateRangeText = dateRangeText
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.lg) {
            figure(label: "Net", value: netText, emphasized: true)
            figure(label: "In", value: inText)
            figure(label: "Out", value: outText)

            Text("\(count) \(count == 1 ? "transaction" : "transactions")")
                .microText()
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer(minLength: Spacing.sm)

            trailing()

            Text(dateRangeText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .solidDataSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func figure(label: String, value: String, emphasized: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(label)
                .microText()
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            if emphasized {
                Text(value)
                    .dataText()
            } else {
                Text(value)
                    .font(.caption.monospacedDigit())
            }
        }
        .lineLimit(1)
    }

    private var accessibilityText: String {
        "Net \(netText). In \(inText). Out \(outText). "
            + "\(count) \(count == 1 ? "transaction" : "transactions"). \(dateRangeText)."
    }
}

#if canImport(PreviewsMacros)
#Preview("Ledger summary strip") {
    VStack(spacing: Spacing.md) {
        LedgerSummaryStrip(
            netText: "−$1,204.18",
            inText: "$4,820.00",
            outText: "$6,024.18",
            count: 47,
            dateRangeText: "Mar 1 – Mar 31"
        )
        LedgerSummaryStrip(
            netText: "••••",
            inText: "••••",
            outText: "••••",
            count: 3,
            dateRangeText: "This week"
        )
    }
    .padding(Spacing.lg)
    .frame(width: 560)
}

#Preview("Ledger summary strip — dark") {
    LedgerSummaryStrip(
        netText: "+$316.40",
        inText: "$2,100.00",
        outText: "$1,783.60",
        count: 12,
        dateRangeText: "Feb 1 – Feb 28"
    )
    .padding(Spacing.lg)
    .frame(width: 560)
    .preferredColorScheme(.dark)
}
#endif
