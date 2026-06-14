import PlaidBarCore
import SwiftUI

struct WeeklyReviewCard: View {
    @Environment(AppState.self) private var appState

    private var presentation: WeeklyReviewPresentation {
        appState.weeklyReviewPresentation
    }

    var body: some View {
        let presentation = presentation

        VStack(alignment: .leading, spacing: Spacing.sm) {
            header(presentation)

            if presentation.isBlockedByTransactionReviewDependency {
                dependencyState
            } else if presentation.items.isEmpty || presentation.remainingCount == 0 {
                positiveState(presentation)
            } else {
                checklist(presentation)
            }
        }
        .padding(Spacing.sm)
        .glassSurface(.raised)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary(presentation))
    }

    private func header(_ presentation: WeeklyReviewPresentation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Label("Weekly Review", systemImage: "calendar.badge.checkmark")
                .sectionTitle()
                .foregroundStyle(.secondary)

            Spacer(minLength: Spacing.sm)

            Label(presentation.outcome.title, systemImage: outcomeIcon(presentation.outcome))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(outcomeTint(presentation.outcome))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(outcomeTint(presentation.outcome).opacity(0.11), in: Capsule())
                .accessibilityLabel("Weekly review status: \(presentation.outcome.title)")
        }
    }

    private var dependencyState: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Weekly review unlocks after the transaction review inbox can say which transactions are trusted.")
                .microText()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label("Waiting for AND-399 review state", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SemanticColors.warning)
                .accessibilityLabel("Waiting for transaction review state")
        }
        .padding(Spacing.sm)
        .nativeInsetSurface()
    }

    private func positiveState(_ presentation: WeeklyReviewPresentation) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SemanticColors.positive)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Nothing needs review")
                    .font(.caption.weight(.semibold))
                Text(nextReviewText(presentation))
                    .microText()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Spacing.sm)

            Button {
                appState.completeWeeklyReview()
            } label: {
                Label("Complete", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Complete weekly review")
            .accessibilityLabel("Complete weekly review")
        }
        .padding(Spacing.sm)
        .nativeInsetSurface(stroke: SemanticColors.positive.opacity(0.18))
    }

    private func checklist(_ presentation: WeeklyReviewPresentation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Text("\(presentation.completedCount)/\(presentation.totalCount) complete")
                    .microText()
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if presentation.reviewedTransactionCount > 0 {
                    Text("\(presentation.reviewedTransactionCount) reviewed this week")
                        .microText()
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ForEach(presentation.items) { item in
                WeeklyReviewItemRow(
                    item: item,
                    isCompleted: appState.weeklyReviewState.completedItemIds.contains(item.id),
                    isDisabled: appState.isLoading,
                    onToggle: { appState.toggleWeeklyReviewItem(item) },
                    onAction: { appState.performWeeklyReviewAction(item) }
                )
            }

            Button {
                appState.completeWeeklyReview()
            } label: {
                Label("Complete Review", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(presentation.totalCount == 0)
            .accessibilityHint("Records this weekly review locally on this Mac.")
        }
    }

    private func nextReviewText(_ presentation: WeeklyReviewPresentation) -> String {
        guard let nextReviewDueAt = presentation.nextReviewDueAt else {
            return "Complete this review to start the weekly cadence."
        }
        return "Next review \(Formatters.relativeDate(nextReviewDueAt))."
    }

    private func accessibilitySummary(_ presentation: WeeklyReviewPresentation) -> String {
        if presentation.isBlockedByTransactionReviewDependency {
            return "Weekly review. Transaction review inbox required before this checklist can run."
        }
        return "Weekly review. \(presentation.outcome.title). \(presentation.completedCount) of \(presentation.totalCount) items complete."
    }

    private func outcomeIcon(_ outcome: WeeklyReviewOutcome) -> String {
        switch outcome {
        case .looksGood: "checkmark.circle.fill"
        case .reviewItems: "exclamationmark.circle.fill"
        case .payAttention: "exclamationmark.triangle.fill"
        case .waitingForTransactionReview: "checklist"
        }
    }

    private func outcomeTint(_ outcome: WeeklyReviewOutcome) -> Color {
        switch outcome {
        case .looksGood: SemanticColors.positive
        case .reviewItems, .waitingForTransactionReview: SemanticColors.warning
        case .payAttention: SemanticColors.negative
        }
    }
}

private struct WeeklyReviewItemRow: View {
    let item: WeeklyReviewItem
    let isCompleted: Bool
    let isDisabled: Bool
    let onToggle: () -> Void
    let onAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                    .font(.callout.weight(.semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isCompleted ? SemanticColors.positive : tint)
            .help(isCompleted ? "Mark incomplete" : "Mark complete")
            .accessibilityLabel(isCompleted ? "Completed" : "Not completed")
            .accessibilityValue(item.title)

            Image(systemName: item.severity.statusSymbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .strikethrough(isCompleted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(item.detail)
                    .microText()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.xs)

            Button(action: onAction) {
                Label(item.action.title, systemImage: item.action.iconName)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help(item.action.title)
            .accessibilityLabel(item.action.title)
            .accessibilityHint(item.accessibilityHint)
            .disabled(isDisabled)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.rowVertical)
        .nativeInsetSurface(stroke: isCompleted ? SemanticColors.positive.opacity(0.16) : tint.opacity(0.14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityValue(isCompleted ? "Completed" : "Not completed")
    }

    private var tint: Color {
        switch item.severity {
        case .healthy: .secondary
        case .warning: SemanticColors.warning
        case .blocked: SemanticColors.negative
        }
    }
}
