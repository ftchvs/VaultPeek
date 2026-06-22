import PlaidBarCore
import SwiftUI

/// Onboarding: one mode choice (Demo / Sandbox / Production), one preflight
/// checklist, one connect step. Renders at the dashboard's 480pt width so
/// setup and dashboard never snap between window sizes.
struct SetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var setupMode: SetupMode = .choose
    // Locally-remembered plan preference. UI-only: it grants no entitlement and
    // gates nothing. Managed billing/enforcement is deferred (AND-350 scope).
    @AppStorage(SubscriptionPlan.storageKey) private var selectedPlanRawValue = SubscriptionPlan.defaultPlan.rawValue
    var onComplete: (() -> Void)?

    private var selectedPlan: Binding<SubscriptionPlan> {
        Binding(
            get: { SubscriptionPlan(rawValue: selectedPlanRawValue) ?? .free },
            set: { selectedPlanRawValue = $0.rawValue }
        )
    }

    enum SetupMode: Sendable, Equatable {
        case choose
        case sandbox
        case production
        case connecting(PlaidEnvironment)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            switch setupMode {
            case .choose:
                choiceView
            case .sandbox:
                linkPrepView(
                    environment: .sandbox,
                    icon: "testtube.2",
                    title: "Connect Sandbox",
                    summary: "Test institutions with Plaid sandbox credentials on the VaultPeek companion server.",
                    primaryTitle: "Open Link"
                )
            case .production:
                linkPrepView(
                    environment: .production,
                    icon: "lock.shield",
                    title: "Connect Production",
                    summary: "Real accounts and real financial data. Requires Plaid production "
                        + "approval and production credentials.",
                    primaryTitle: "Open Link"
                )
            case let .connecting(environment):
                connectingView(environment: environment)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .animation(
            MotionTokens.animation(MotionTokens.standard, reduceMotion: reduceMotion),
            value: setupMode
        )
    }

    // MARK: - Choose

    private var choiceView: some View {
        VStack(spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(SemanticColors.brand)
                    .frame(width: 40, height: 40)
                    .background(SemanticColors.brand.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.panel))

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(PlaidBarConstants.appName)
                        .font(.title3.weight(.semibold))
                    Text(
                        "Your accounts, one click away. Choose demo data or connect through the local VaultPeek companion server."
                    )
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // One mode chooser. Each row is the single authoritative way to
            // enter its mode — never duplicated by a second strip of pills.
            VStack(spacing: Spacing.sm) {
                OnboardingChoiceButton(
                    title: "View Demo",
                    subtitle: "Local sample data. No Plaid credentials, no server.",
                    icon: "play.circle",
                    color: SemanticColors.brandSecondary
                ) {
                    startDemoMode()
                }

                OnboardingChoiceButton(
                    title: "Connect Sandbox",
                    subtitle: "Plaid test institutions on your local server.",
                    icon: "testtube.2",
                    color: SemanticColors.brand
                ) {
                    setupMode = .sandbox
                }

                OnboardingChoiceButton(
                    title: "Connect Production",
                    subtitle: "Real financial data. Requires Plaid production approval.",
                    icon: "lock.shield",
                    color: SemanticColors.positive
                ) {
                    setupMode = .production
                }
            }

            whereYourDataLivesDisclosure

            SetupSupportLinks()
        }
    }

    /// Onboarding transparency disclosure (AND-491). Reachable before any mode
    /// choice — including the credential-less "View Demo" path — so users can see
    /// where VaultPeek stores data before connecting anything.
    private var whereYourDataLivesDisclosure: some View {
        let receipt = LocalTrustReceipt.whereYourDataLives(
            storagePath: appState.activeStorageDirectoryDisplayText
        )
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(receipt.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Image(systemName: row.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(row.detail)
                            .detailText()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.title). \(row.detail)")
                }
            }
            .padding(.top, Spacing.xs)
        } label: {
            Label(receipt.title, systemImage: "lock.shield")
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Link preparation

    private func linkPrepView(
        environment: PlaidEnvironment,
        icon: String,
        title: String,
        summary: String,
        primaryTitle: String
    ) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(environment == .production ? SemanticColors.positive : SemanticColors.brand)

            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text(summary)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                StorageDisclosureRow(
                    icon: "externaldrive",
                    text: "Tokens and synced data stay local: \(appState.activeStorageDirectoryDisplayText)."
                )
                StorageDisclosureRow(
                    icon: "server.rack",
                    text: "Plaid credentials stay in the local server environment."
                )
                StorageDisclosureRow(
                    icon: "eye.slash",
                    text: "Today VaultPeek runs fully on your Mac — no cloud backend, "
                        + "analytics, or telemetry. A managed cloud bridge for bank linking "
                        + "is planned but isn't available yet; even then your financial data "
                        + "would never be stored off your Mac, though it would transit a "
                        + "VaultPeek proxy. Today's connections use your own Plaid keys."
                )
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(.inset)

            // Plan preview + usage shell. Production shows the managed-plan
            // *preview* picker, but today's production path is still BYO Plaid
            // keys, which stays fully ungated. So the usage meter uses a nil limit
            // (count-only, no cap, no upgrade CTA) until real managed origin +
            // entitlements exist.
            // The count reflects all linked institutions (`statusItemCount`), not
            // only currently-healthy ones, so an item needing reauth still counts.
            if environment == .production {
                PlanSelectionShell(
                    selectedPlan: selectedPlan,
                    billingSubscription: appState.billingSubscription
                )
            }
            InstitutionUsageWidget(
                usage: InstitutionUsage(connectedCount: appState.statusItemCount, limit: nil),
                showsUpgradeWhenAtLimit: false
            )

            OnboardingPreflightPanel(environment: environment)
                .environment(appState)

            if let error = appState.error {
                SetupRecoveryCallout(
                    title: "Check setup",
                    detail: error,
                    icon: "exclamationmark.triangle.fill",
                    color: SemanticColors.negative
                )
            }

            Text(preflightHint(for: environment))
                .detailText()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                setupMode = .connecting(environment)
                Task {
                    let opened = await appState.connectForOnboarding(expectedEnvironment: environment)
                    if !opened {
                        setupMode = environment == .production ? .production : .sandbox
                    }
                }
            } label: {
                Label(primaryTitle, systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isLoading || !isPreflightReady(for: environment))

            Button("Back") {
                setupMode = .choose
            }
            .buttonStyle(.borderless)

            SetupSupportLinks()
        }
        .task {
            await appState.checkServerConnection()
        }
    }

    // MARK: - Connecting

    private func connectingView(environment: PlaidEnvironment) -> some View {
        let completion = appState.firstRunCompletionState

        return VStack(spacing: Spacing.lg) {
            if completion.step != .ready, completion.step != .blocked {
                ProgressView()
                    .controlSize(.large)
            }

            Text(connectingTitle(for: completion))
                .font(.title3.weight(.semibold))

            Text(connectingDetail(for: completion, environment: environment))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)

            FirstRunCompletionPanel(state: completion)

            Button {
                Task {
                    if await appState.completeFirstRunCheck() {
                        onComplete?()
                    }
                }
            } label: {
                Label(
                    primaryCompletionActionTitle(for: completion),
                    systemImage: primaryCompletionActionIcon(for: completion)
                )
            }
            .buttonStyle(.bordered)
            .disabled(appState.isLoading || (!completion.canRetry && !completion.isReady))

            if completion.step == .openPlaidLink {
                Button {
                    Task {
                        _ = await appState.connectForOnboarding(expectedEnvironment: environment)
                    }
                } label: {
                    Label("Open Link", systemImage: "link")
                }
                .buttonStyle(.bordered)
                .disabled(appState.isLoading)
            }

            Button("Cancel") {
                setupMode = environment == .production ? .production : .sandbox
            }
            .buttonStyle(.borderless)
        }
    }

    private func startDemoMode() {
        appState.startDemoMode()
        onComplete?()
    }

    private func isPreflightReady(for environment: PlaidEnvironment) -> Bool {
        appState.onboardingPreflight(for: environment).isReady
    }

    private func preflightHint(for environment: PlaidEnvironment) -> String {
        appState.onboardingPreflight(for: environment).hint
    }

    private func connectingTitle(for completion: FirstRunCompletionState) -> String {
        switch completion.step {
        case .openPlaidLink:
            "Waiting for Plaid Link"
        case .loadAccounts:
            "Item linked"
        case .syncTransactions:
            "First sync"
        case .ready:
            "Dashboard ready"
        case .blocked:
            "Check setup"
        }
    }

    private func connectingDetail(
        for completion: FirstRunCompletionState,
        environment: PlaidEnvironment
    ) -> String {
        switch completion.step {
        case .openPlaidLink:
            "Finish Plaid Link in your browser, then check again."
        case .loadAccounts:
            "Load balances before opening the dashboard."
        case .syncTransactions:
            "Run the first transaction sync to complete setup."
        case .ready:
            "Setup is complete."
        case .blocked:
            "Resolve the issue below, then check again."
        }
    }

    private func primaryCompletionActionTitle(for completion: FirstRunCompletionState) -> String {
        switch completion.step {
        case .openPlaidLink:
            "Check Again"
        case .loadAccounts:
            "Load Accounts"
        case .syncTransactions:
            "Run First Sync"
        case .ready:
            "Open Dashboard"
        case .blocked:
            "Check Again"
        }
    }

    private func primaryCompletionActionIcon(for completion: FirstRunCompletionState) -> String {
        switch completion.step {
        case .openPlaidLink, .blocked:
            "arrow.clockwise"
        case .loadAccounts:
            "building.columns"
        case .syncTransactions:
            "arrow.triangle.2.circlepath"
        case .ready:
            "checkmark.circle"
        }
    }
}

private struct FirstRunCompletionPanel: View {
    let state: FirstRunCompletionState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(state.title)
                    .font(.callout.weight(.semibold))
                Spacer(minLength: Spacing.sm)
            }

            Text(state.detail)
                .detailText()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.inset)
    }

    private var icon: String {
        switch state.step {
        case .ready:
            "checkmark.circle.fill"
        case .blocked:
            "exclamationmark.triangle.fill"
        case .openPlaidLink:
            "link.circle"
        case .loadAccounts:
            "building.columns"
        case .syncTransactions:
            "arrow.triangle.2.circlepath"
        }
    }

    private var color: Color {
        switch state.step {
        case .ready:
            SemanticColors.positive
        case .blocked:
            SemanticColors.negative
        case .openPlaidLink, .loadAccounts, .syncTransactions:
            SemanticColors.brand
        }
    }
}

private struct SetupRecoveryCallout: View {
    let title: String
    let detail: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.emphasized(color))
        .accessibilityElement(children: .combine)
    }
}

private struct SetupSupportLinks: View {
    var body: some View {
        HStack(spacing: Spacing.md) {
            supportLink(
                "Troubleshooting",
                systemImage: "wrench.and.screwdriver",
                url: PlaidBarConstants.repositoryFileURL("docs/troubleshooting.md")
            )

            supportLink(
                "Privacy",
                systemImage: "lock.shield",
                url: PlaidBarConstants.repositoryFileURL("docs/privacy.md")
            )

            supportLink(
                "Security",
                systemImage: "exclamationmark.shield",
                url: PlaidBarConstants.repositoryFileURL("SECURITY.md")
            )
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func supportLink(
        _ title: String,
        systemImage: String,
        url: String
    ) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

private struct OnboardingChoiceButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: Sizing.iconChip)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: Spacing.sm)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(true)
        .hoverHighlight(cornerRadius: Radius.panel)
        .glassSurface(.inset)
    }
}

private struct StorageDisclosureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingPreflightPanel: View {
    @Environment(AppState.self) private var appState
    let environment: PlaidEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Preflight")
                    .sectionTitle()
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task { await appState.checkServerConnection() }
                } label: {
                    Label("Check Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            VStack(spacing: Spacing.xs) {
                ForEach(appState.onboardingPreflight(for: environment).rows) { row in
                    preflightRow(row)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(.inset)
    }

    private func preflightRow(_ row: OnboardingPreflightRow) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: row.iconName)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(row.title)
                .foregroundStyle(.secondary)

            Spacer(minLength: Spacing.sm)

            // The state icon changes shape per state (never tint alone),
            // and the value text stays contrast-safe instead of being
            // colored at caption size.
            if let stateIcon = stateIconName(for: row.state) {
                Image(systemName: stateIcon)
                    .foregroundStyle(color(for: row.state))
            }

            Text(row.value)
                .font(.caption.weight(.medium))
                .foregroundStyle(valueStyle(for: row.state))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(preflightRowAccessibilityLabel(for: row))
        .accessibilityHint(row.accessibilityHint)
    }

    /// The explicit label suppresses the state icon for VoiceOver, so the
    /// ready/blocked/checking signal the icon shape conveys is appended to
    /// the label text instead.
    private func preflightRowAccessibilityLabel(for row: OnboardingPreflightRow) -> String {
        let base = "\(row.title): \(row.value)"
        return switch row.state {
        case .ready: "\(base), ready"
        case .blocked: "\(base), blocked"
        case .unknown: "\(base), checking"
        case .informational: base
        }
    }

    private func stateIconName(for state: OnboardingPreflightRowState) -> String? {
        switch state {
        case .ready:
            "checkmark.circle.fill"
        case .blocked:
            "xmark.circle.fill"
        case .unknown:
            "circle.dotted"
        case .informational:
            nil
        }
    }

    private func color(for state: OnboardingPreflightRowState) -> Color {
        switch state {
        case .ready:
            SemanticColors.positive
        case .blocked:
            SemanticColors.negative
        case .unknown, .informational:
            .secondary
        }
    }

    private func valueStyle(for state: OnboardingPreflightRowState) -> AnyShapeStyle {
        switch state {
        case .ready, .blocked:
            AnyShapeStyle(.primary)
        case .unknown, .informational:
            AnyShapeStyle(.secondary)
        }
    }
}
