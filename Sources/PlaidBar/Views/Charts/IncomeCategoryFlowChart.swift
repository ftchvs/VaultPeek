import PlaidBarCore
import SwiftUI

/// Inspector-column wrapper for the Income → Category flow (AND-500): header +
/// close control, the flow chart when there is data, and load/empty states —
/// mirroring `RecurringPaymentsView`'s chrome so the right column stays uniform.
struct IncomeCategoryFlowInspector: View {
    let presentation: IncomeCategoryFlowPresentation
    var loadState: DashboardLoadState?
    /// When true (Privacy Mask on), every income/spend amount the flow exposes is
    /// masked so this drill-in is not a privacy-mode bypass for financial data.
    /// The structure (source/category labels, ribbon shape) still renders.
    var isPrivacyMasked: Bool = false
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.4)

            if presentation.isEmpty {
                switch loadState?.phase {
                case .loading:
                    state("Mapping income flow", systemImage: "arrow.left.arrow.right", detail: "VaultPeek is reading synced local transactions.")
                case .offline:
                    state("Income flow unavailable", systemImage: "wifi.slash", detail: "VaultPeek can't reach the local server, so the flow isn't available yet. Reconnect to refresh.")
                case .error:
                    state("Income flow unavailable", systemImage: "exclamationmark.triangle", detail: "The last refresh didn't finish, so the flow isn't available yet. Refresh to try again.")
                default:
                    state(presentation.emptyTitle, systemImage: "arrow.left.arrow.right", detail: presentation.emptyDetail)
                }
            } else {
                ScrollView {
                    IncomeCategoryFlowChart(presentation: presentation, isPrivacyMasked: isPrivacyMasked)
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Income to category flow. \(presentation.summaryText)")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Income flow")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(presentation.summaryText)
                    .microText()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Spacing.sm)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Sizing.hitTargetMin, minHeight: Sizing.hitTargetMin)
            }
            .buttonStyle(.borderless)
            .help("Close income flow")
            .accessibilityLabel("Close income flow")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(Spacing.md)
    }

    private func state(_ title: String, systemImage: String, detail: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(detail)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.md)
    }
}

/// Income → Category flow ("Sankey") surface (AND-500).
///
/// Swift Charts has no native flow mark, so this is hand-rendered: node columns
/// as rounded rectangles and proportional ribbons as cubic Bézier bands in a
/// `Canvas`, sized by `GeometryReader`. The geometry is computed by the pure
/// `FlowLayout` engine in PlaidBarCore (unit-tested there). Every node carries a
/// text label + amount and the surface a VoiceOver summary, so meaning never
/// rides on color alone (ACCESSIBILITY.md). Flows are aggregate-proportional —
/// honestly labeled, since per-transaction income→category data does not exist.
struct IncomeCategoryFlowChart: View {
    let presentation: IncomeCategoryFlowPresentation
    /// When true (Privacy Mask on), the visible income/spend amounts and the
    /// VoiceOver amounts are masked; the flow geometry and labels still render.
    var isPrivacyMasked: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealFraction: CGFloat = 0

    private let chartHeight: CGFloat = 180
    private let nodeWidth: Double = 14
    private let nodeGap: Double = 8

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                columnHeader("Income", amount: masked(presentation.totalIncomeText))
                Spacer()
                columnHeader("Spending", amount: masked(presentation.totalSpendText))
            }

            GeometryReader { proxy in
                let layout = FlowLayout.compute(
                    graph: presentation.graph,
                    width: Double(proxy.size.width),
                    height: Double(proxy.size.height),
                    nodeGap: nodeGap,
                    nodeWidth: nodeWidth
                )
                Canvas { context, _ in
                    drawRibbons(layout: layout, context: &context)
                    drawNodes(layout: layout, context: &context)
                }
                .mask(alignment: .leading) {
                    Rectangle().frame(width: proxy.size.width * revealFraction)
                }
            }
            .frame(height: chartHeight)

            // Text legend so each ribbon/node has a readable label off-color.
            legend

            // Visible caveat so sighted users aren't misled into reading the
            // ribbons as real per-transaction source→category attribution. The
            // model only splits each source by total spend share; the chart must
            // not overstate what the data proves (previously only in VoiceOver).
            Text("Ribbons are aggregate-proportional, not per-transaction income-to-category attribution.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            guard !reduceMotion else { revealFraction = 1; return }
            revealFraction = 0
            withAnimation(MotionTokens.chartReveal.delay(0.1)) {
                revealFraction = 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Mask a baked currency string when Privacy Mask is on; otherwise pass through.
    private func masked(_ value: String) -> String {
        PrivacyMaskPresentation.value(value, isEnabled: isPrivacyMasked)
    }

    /// VoiceOver label. When masked, the structure (source/category labels, order)
    /// is preserved but every amount is replaced, so the drill-in never speaks
    /// exact financial values while Privacy Mask is on.
    private var accessibilityLabel: String {
        guard isPrivacyMasked else { return presentation.accessibilityLabel }
        if presentation.isEmpty {
            return presentation.accessibilityLabel
        }
        let hidden = PrivacyMaskPresentation.compactValue
        let sourceList = presentation.sources.map { "\($0.label) \(hidden)" }.joined(separator: ", ")
        let categoryList = presentation.categories.map { "\($0.label) \(hidden)" }.joined(separator: ", ")
        return "Income to category flow. Income: \(sourceList). Spending: \(categoryList). Flows are aggregate-proportional, not per-transaction. Amounts hidden while Privacy Mask is on."
    }

    private func columnHeader(_ title: String, amount: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(amount)
                .microText()
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ForEach(presentation.categories) { category in
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(color(forNodeID: category.id))
                        .frame(width: 7, height: 7)
                    Text(category.label)
                        .font(.caption2)
                    Spacer(minLength: Spacing.sm)
                    Text(masked(category.amountText))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Canvas drawing

    private func drawNodes(layout: FlowLayout, context: inout GraphicsContext) {
        for rect in layout.sourceRects {
            fillNode(rect, color: incomeColor, context: &context)
        }
        for rect in layout.categoryRects {
            fillNode(rect, color: color(forNodeID: rect.id), context: &context)
        }
    }

    private func fillNode(_ rect: FlowRect, color: Color, context: inout GraphicsContext) {
        let cgRect = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        let path = Path(roundedRect: cgRect, cornerRadius: 3)
        context.fill(path, with: .color(color))
    }

    private func drawRibbons(layout: FlowLayout, context: inout GraphicsContext) {
        for ribbon in layout.ribbons {
            var path = Path()
            let halfThickness = ribbon.thickness / 2
            // Top edge of the band (start top → end top), then bottom edge back.
            path.move(to: CGPoint(x: ribbon.startX, y: ribbon.startY - halfThickness))
            path.addCurve(
                to: CGPoint(x: ribbon.endX, y: ribbon.endY - halfThickness),
                control1: CGPoint(x: ribbon.control1X, y: ribbon.control1Y - halfThickness),
                control2: CGPoint(x: ribbon.control2X, y: ribbon.control2Y - halfThickness)
            )
            path.addLine(to: CGPoint(x: ribbon.endX, y: ribbon.endY + halfThickness))
            path.addCurve(
                to: CGPoint(x: ribbon.startX, y: ribbon.startY + halfThickness),
                control1: CGPoint(x: ribbon.control2X, y: ribbon.control2Y + halfThickness),
                control2: CGPoint(x: ribbon.control1X, y: ribbon.control1Y + halfThickness)
            )
            path.closeSubpath()
            context.fill(path, with: .color(color(forNodeID: ribbon.categoryID).opacity(0.28)))
        }
    }

    // MARK: - Colors

    private var incomeColor: Color { SemanticColors.positive }

    private func color(forNodeID id: String) -> Color {
        if id.hasPrefix("income:") { return incomeColor }
        if let category = SpendingCategory(rawValue: id) {
            return CategoryAccentTokens.color(for: category)
        }
        return .secondary
    }
}
