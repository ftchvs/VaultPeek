import SwiftUI
import PlaidBarCore

struct SetupView: View {
    @Environment(AppState.self) private var appState
    @State private var setupMode: SetupMode = .choose
    var onComplete: (() -> Void)?

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
                    summary: "Test institutions with Plaid sandbox credentials on PlaidBarServer.",
                    primaryTitle: "Open Link"
                )
            case .production:
                linkPrepView(
                    environment: .production,
                    icon: "lock.shield",
                    title: "Connect Production",
                    summary: "Real accounts with approved Plaid production credentials.",
                    primaryTitle: "Open Link"
                )
            case .connecting(let environment):
                connectingView(environment: environment)
            }
        }
        .padding()
        .frame(width: 520)
        .animation(.easeInOut(duration: 0.25), value: setupMode)
    }

    private var choiceView: some View {
        VStack(spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(SemanticColors.brand)
                    .frame(width: 42, height: 42)
                    .background(SemanticColors.brand.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("PlaidBar")
                        .font(.title2.weight(.bold))
                    Text("Menu bar finance, one click away.")
                        .font(.callout.weight(.medium))
                    Text("Choose demo data or connect through your local PlaidBarServer.")
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.sm)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            OnboardingModeStrip(
                onDemo: startDemoMode,
                onSandbox: { setupMode = .sandbox },
                onProduction: { setupMode = .production }
            )

            VStack(spacing: Spacing.sm) {
                OnboardingChoiceButton(
                    title: "View Demo",
                    subtitle: "Local sample data. No Plaid credentials.",
                    icon: "play.circle",
                    color: SemanticColors.brandSecondary
                ) {
                    startDemoMode()
                }

                OnboardingChoiceButton(
                    title: "Connect Sandbox",
                    subtitle: "Plaid test institutions.",
                    icon: "testtube.2",
                    color: SemanticColors.brand
                ) {
                    setupMode = .sandbox
                }

                OnboardingChoiceButton(
                    title: "Connect Production",
                    subtitle: "Approved Plaid access for real accounts.",
                    icon: "lock.shield",
                    color: SemanticColors.positive
                ) {
                    setupMode = .production
                }
            }

            SetupSupportLinks()
        }
    }

    private func linkPrepView(
        environment: PlaidEnvironment,
        icon: String,
        title: String,
        summary: String,
        primaryTitle: String
    ) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(environment == .production ? SemanticColors.positive : SemanticColors.brand)

            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)

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
                    text: "No PlaidBar cloud backend, analytics, or telemetry."
                )
            }
            .padding(Spacing.md)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

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
            .opacity(isPreflightReady(for: environment) ? 1 : 0.45)

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

    private func connectingView(environment: PlaidEnvironment) -> some View {
        let completion = appState.firstRunCompletionState

        return VStack(spacing: Spacing.lg) {
            if completion.step != .ready && completion.step != .blocked {
                ProgressView()
                    .scaleEffect(1.5)
            }

            Text(connectingTitle(for: completion))
                .font(.title3)

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
                Label(primaryCompletionActionTitle(for: completion), systemImage: primaryCompletionActionIcon(for: completion))
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
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
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
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct SetupSupportLinks: View {
    var body: some View {
        HStack(spacing: Spacing.md) {
            supportLink(
                "Troubleshooting",
                systemImage: "wrench.and.screwdriver",
                url: "https://github.com/ftchvs/PlaidBar/blob/main/docs/troubleshooting.md"
            )

            supportLink(
                "Privacy",
                systemImage: "lock.shield",
                url: "https://github.com/ftchvs/PlaidBar/blob/main/docs/privacy.md"
            )

            supportLink(
                "Security",
                systemImage: "exclamationmark.shield",
                url: "https://github.com/ftchvs/PlaidBar/blob/main/SECURITY.md"
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

private struct OnboardingModeStrip: View {
    let onDemo: () -> Void
    let onSandbox: () -> Void
    let onProduction: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ModePill(title: "Demo", subtitle: "Local", icon: "play.circle.fill", tint: SemanticColors.brandSecondary, action: onDemo)
            ModePill(title: "Sandbox", subtitle: "Plaid test", icon: "testtube.2", tint: SemanticColors.brand, action: onSandbox)
            ModePill(title: "Production", subtitle: "Real data", icon: "lock.shield.fill", tint: SemanticColors.positive, action: onProduction)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ModePill: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.bold))
                    Text(subtitle)
                        .microText()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
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
                    .frame(width: 24)

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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                Text("PREFLIGHT")
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
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func preflightRow(_ row: OnboardingPreflightRow) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: row.iconName)
                .foregroundStyle(color(for: row.state))
                .frame(width: 18)

            Text(row.title)
                .foregroundStyle(.secondary)

            Spacer(minLength: Spacing.sm)

            Text(row.value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color(for: row.state))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title): \(row.value)")
        .accessibilityHint(row.accessibilityHint)
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
}
