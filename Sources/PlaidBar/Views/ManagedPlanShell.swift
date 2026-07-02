import PlaidBarCore
import SwiftUI

// MARK: - Plan selection shell
//
// FOUNDATION ONLY. These views are honest UX shells for the proposed managed
// consumer plans (AND-350). They persist a *local preference* and render the
// proposed institution limits, but nothing here enforces a limit, charges
// money, or talks to a managed backend — that work stays deferred. Demo and
// bring-your-own (BYO) Plaid-keys modes remain fully free and ungated; this
// picker only appears on the production path as a preview.

/// Restrained plan picker over `SubscriptionPlan.allCases`. Shows each plan's
/// display name and proposed institution limit, with a one-line preview note so
/// the copy never implies billing exists today.
struct PlanSelectionShell: View {
    @Binding var selectedPlan: SubscriptionPlan
    var billingSubscription: BillingSubscription?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Plan")
                .sectionTitle()
                .foregroundStyle(.secondary)

            Picker("Plan", selection: $selectedPlan) {
                ForEach(SubscriptionPlan.allCases) { plan in
                    Text(plan.displayName).tag(plan)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Subscription plan")

            HStack(spacing: Spacing.xs) {
                Image(systemName: "building.columns")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(selectedPlan.priceDescription)
                    .detailText()
            }
            .accessibilityElement(children: .combine)

            if let billingSubscription {
                BillingStatusRow(subscription: billingSubscription)
            }

            Text(
                "Managed plans are a preview — billing and managed bank linking aren't "
                    + "available yet. Demo and bring-your-own-keys connections stay free."
            )
            .detailText()
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .solidDataSurface(cornerRadius: Radius.panel)
    }
}

private struct BillingStatusRow: View {
    let subscription: BillingSubscription

    private var gate: BillingFeatureGateResult {
        BillingFeatureGate.evaluate(featureName: "managed plan features", subscription: subscription)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: iconName)
                    .foregroundStyle(subscription.status.allowsPaidFeatures ? .secondary : SemanticColors.warning)
                    .frame(width: 16)
                Text("Billing: \(subscription.status.displayName)")
                    .font(.caption.weight(.medium))
            }
            .accessibilityElement(children: .combine)

            if case .locked(let lock) = gate {
                Text("\(lock.message) \(lock.recoveryAction)")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            } else if subscription.status == .trialing {
                Text(subscription.status.recoveryAction)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var iconName: String {
        subscription.status.allowsPaidFeatures ? "checkmark.circle" : "lock.circle"
    }
}

/// "X of Y institutions connected" usage widget plus an upgrade affordance when
/// the proposed limit is reached. Conveys at-limit state with text and an icon,
/// never color alone. The upgrade action is a placeholder — there is no billing.
struct InstitutionUsageWidget: View {
    let usage: InstitutionUsage
    /// Whether to surface the upgrade affordance when at limit. Demo/BYO surfaces
    /// pass a `nil`-limit usage, which is never at limit, so the CTA stays hidden.
    var showsUpgradeWhenAtLimit: Bool = true

    @State private var showUpgradeNote = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: iconName)
                    .foregroundStyle(usage.isAtLimit ? SemanticColors.warning : .secondary)
                    .frame(width: 18)

                Text(usage.summaryText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: Spacing.sm)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)

            if usage.isAtLimit, showsUpgradeWhenAtLimit {
                Button {
                    showUpgradeNote = true
                } label: {
                    Label("Upgrade plan", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityHint("Managed plans are a preview; opens an explanation.")
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .solidDataSurface(cornerRadius: Radius.panel)
        .alert("Managed plans are coming soon", isPresented: $showUpgradeNote) {
            Button("OK", role: .cancel) {}
            if let docsURL = URL(string: PlaidBarConstants.repositoryFileURL("docs/privacy.md")) {
                Link("Learn more", destination: docsURL)
            }
        } message: {
            Text(
                "Higher institution limits arrive with managed bank linking, which isn't "
                    + "available yet. For now, demo and bring-your-own-keys connections stay free."
            )
        }
    }

    /// Filled glyph at limit, hollow otherwise — a shape change, not a tint
    /// change, so the at-limit signal survives color-blindness and grayscale.
    private var iconName: String {
        usage.isAtLimit ? "exclamationmark.circle.fill" : "checkmark.circle"
    }

    private var accessibilityLabel: String {
        usage.isAtLimit ? "\(usage.summaryText), at plan limit" : usage.summaryText
    }
}
