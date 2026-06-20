import AppIntents
import PlaidBarCore
import SwiftUI

// MARK: - Spotlight mini-dashboard SnippetIntent (AND-586, Epic 8)
//
// `SnippetIntent` (macOS 26+) lets an intent render a small SwiftUI view inline in
// Spotlight / Siri results — a "mini-dashboard" the user sees without opening the
// app. This one reads the shared `FinanceSnapshot` from the App Group and renders
// it through `SnippetDashboardPresentation` (the pure PlaidBarCore model that owns
// row selection, formatting, and the masked/unavailable decision), so the snippet
// never leaks a figure past App Lock / Privacy Mask and the layout logic stays
// unit-tested at the Core layer.
//
// It lives in the app target (not Core / the widget extension) because the snippet
// view is SwiftUI and is extracted against the app. Tapping the snippet's footer
// deep-links into the window via the shared `RouteDeepLink` dashboard URL.

@available(macOS 26.0, *)
struct FinanceDashboardSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "VaultPeek Dashboard"
    static let description = IntentDescription(
        "A glance at your balance, safe-to-spend, and spending — inline in Spotlight."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let model = SnippetDashboardPresentation.model(from: AppGroupSnapshotStore.loadIfAvailable())
        return .result(view: FinanceDashboardSnippetView(model: model))
    }
}

// MARK: - Snippet view

@available(macOS 26.0, *)
private struct FinanceDashboardSnippetView: View {
    let model: SnippetDashboardPresentation.Model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if model.isWithheld {
                withheldRow
            } else {
                metrics
                if !model.categories.isEmpty {
                    Divider()
                    categoriesSection
                }
            }

            footer
        }
        .padding(14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.accessibilityLabel)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .imageScale(.small)
            Text("VaultPeek")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            Text(model.headline)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var metrics: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(model.rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Label(row.title, systemImage: row.systemImage)
                        .labelStyle(.iconOnly)
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(row.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top categories")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(model.categories) { category in
                HStack(spacing: 8) {
                    Label(category.title, systemImage: category.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(category.value)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
    }

    private var withheldRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye.slash")
                .imageScale(.small)
            Text(model.headline)
                .font(.callout.weight(.medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }

    private var footer: some View {
        Text("Updated \(model.updatedAt, style: .time)")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
