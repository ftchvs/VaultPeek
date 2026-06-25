import AppIntents
import PlaidBarCore
import SwiftUI

// MARK: - Focused finance SnippetIntents (AND-637)
//
// `SnippetIntent` (macOS 26+) renders a small SwiftUI view inline in Spotlight /
// Siri / Shortcuts results. `FinanceDashboardSnippetIntent` already renders the
// *combined* mini-dashboard; these give each headline metric — safe-to-spend,
// next bills, credit utilization — its own richer, single-purpose snippet.
//
// Each follows the same contract as the dashboard snippet:
//   • The system may call `perform()` MULTIPLE times, so every intent RE-LOADS the
//     shared `FinanceSnapshot` inside `perform()` and rebuilds its model — it never
//     caches a value-bearing model across invocations.
//   • All row selection / formatting / masking lives in the pure
//     `FinanceSnippetPresentation` (PlaidBarCore); these views are thin renderers.
//   • A masked / missing / empty snapshot yields the withheld affordance — no real
//     figure is ever drawn past App Lock / Privacy Mask.
//
// They live in the app target (not Core / the widget extension) because the views
// are SwiftUI and are extracted against the app, exactly like the dashboard
// snippet. `PlaidBarShortcutsProvider` lists them so Shortcuts/Spotlight discover
// them alongside the value-returning intents.

// MARK: - Safe to spend

@available(macOS 26.0, *)
struct SafeToSpendSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Safe to Spend Snippet"
    static let description = IntentDescription(
        "A glance at your safe-to-spend amount, confidence, and horizon — inline in Spotlight."
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let model = FinanceSnippetPresentation.safeToSpend(from: AppGroupSnapshotStore.loadIfAvailable())
        return .result(view: SafeToSpendSnippetView(model: model))
    }
}

@available(macOS 26.0, *)
private struct SafeToSpendSnippetView: View {
    let model: FinanceSnippetPresentation.SafeToSpendModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SnippetHeader(title: "Safe to Spend", systemImage: "wallet.pass")

            if let reason = model.withholdReason {
                WithheldRow(reason: reason)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if model.isOverBudget {
                        Image(systemName: "exclamationmark.triangle")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    }
                    Text(model.amount)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let confidence = model.confidenceLabel {
                    Label(confidence, systemImage: model.confidenceSystemImage ?? "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let horizon = model.horizonLabel {
                    Text(horizon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            SnippetFooter(updatedAt: model.updatedAt)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.accessibilityLabel)
    }
}

// MARK: - Next recurring bills

@available(macOS 26.0, *)
struct NextBillsSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Next Bills Snippet"
    static let description = IntentDescription(
        "Your next few recurring bills with dates and amounts — inline in Spotlight."
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let model = FinanceSnippetPresentation.nextBills(from: AppGroupSnapshotStore.loadIfAvailable())
        return .result(view: NextBillsSnippetView(model: model))
    }
}

@available(macOS 26.0, *)
private struct NextBillsSnippetView: View {
    let model: FinanceSnippetPresentation.NextBillsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SnippetHeader(title: model.headline, systemImage: "calendar.badge.clock")

            if let reason = model.withholdReason {
                WithheldRow(reason: reason)
            } else if model.rows.isEmpty {
                Text("Nothing due in your tracked window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.rows) { row in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.merchantName)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text(row.dueLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(row.amount)
                            .font(.callout)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                if model.remainderCount > 0 {
                    Text("+\(model.remainderCount) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            SnippetFooter(updatedAt: model.updatedAt)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.accessibilityLabel)
    }
}

// MARK: - Credit utilization gauge

@available(macOS 26.0, *)
struct CreditUtilizationSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "Credit Utilization Snippet"
    static let description = IntentDescription(
        "Your aggregate credit utilization as a gauge — inline in Spotlight."
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let model = FinanceSnippetPresentation.creditUtilization(from: AppGroupSnapshotStore.loadIfAvailable())
        return .result(view: CreditUtilizationSnippetView(model: model))
    }
}

@available(macOS 26.0, *)
private struct CreditUtilizationSnippetView: View {
    let model: FinanceSnippetPresentation.CreditUtilizationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SnippetHeader(title: "Credit Utilization", systemImage: "creditcard")

            if let reason = model.withholdReason {
                WithheldRow(reason: reason)
            } else if let message = model.noLimitMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    if model.isHigh {
                        Image(systemName: "exclamationmark.triangle")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    }
                    Text(model.percentText)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    if model.isHigh {
                        Text("High")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                if let fraction = model.fraction {
                    // Gauge fill encodes the same percent; the numeric label above
                    // carries the meaning so the bar is never the only signal.
                    Gauge(value: fraction) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(model.isHigh ? .secondary : .primary)
                }
            }

            SnippetFooter(updatedAt: model.updatedAt)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.accessibilityLabel)
    }
}

// MARK: - Shared snippet chrome

@available(macOS 26.0, *)
private struct SnippetHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

@available(macOS 26.0, *)
private struct SnippetFooter: View {
    let updatedAt: Date

    var body: some View {
        Text("Updated \(updatedAt, style: .time)")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

@available(macOS 26.0, *)
private struct WithheldRow: View {
    let reason: FinanceSnippetPresentation.WithholdReason

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: reason.systemImage)
                .imageScale(.small)
            Text(reason.headline)
                .font(.callout.weight(.medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }
}
