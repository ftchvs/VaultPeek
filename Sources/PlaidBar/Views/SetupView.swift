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
                    summary: "Uses Plaid's sandbox API with Plaid-hosted test institutions. This still requires your sandbox client ID and secret on the local server.",
                    primaryTitle: "Open Sandbox Link"
                )
            case .production:
                linkPrepView(
                    environment: .production,
                    icon: "lock.shield",
                    title: "Use Production Credentials",
                    summary: "Uses real Plaid production access. Production requires Plaid approval and will connect accounts with real financial data.",
                    primaryTitle: "Open Production Link"
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
                    Text("Choose a data source before anything connects. Demo mode is local; sandbox and production require your local PlaidBarServer.")
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
                    subtitle: "Local fixture data. No Plaid credentials or network calls.",
                    icon: "play.circle",
                    color: SemanticColors.brandSecondary
                ) {
                    startDemoMode()
                }

                OnboardingChoiceButton(
                    title: "Connect Sandbox",
                    subtitle: "Requires sandbox credentials on PlaidBarServer.",
                    icon: "testtube.2",
                    color: SemanticColors.brand
                ) {
                    setupMode = .sandbox
                }

                OnboardingChoiceButton(
                    title: "Use Production Credentials",
                    subtitle: "Requires Plaid approval. Connects real accounts.",
                    icon: "lock.shield",
                    color: SemanticColors.positive
                ) {
                    setupMode = .production
                }
            }
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
                    text: "PlaidBar stores access tokens and synced account data locally under \(appState.localStoragePathText)."
                )
                StorageDisclosureRow(
                    icon: "server.rack",
                    text: "Plaid credentials stay in the local server environment, not in the menu bar app."
                )
                StorageDisclosureRow(
                    icon: "eye.slash",
                    text: "There is no PlaidBar cloud backend, analytics, or telemetry."
                )
            }
            .padding(Spacing.md)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

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
            .disabled(appState.isLoading)

            Button("Back") {
                setupMode = .choose
            }
            .buttonStyle(.borderless)
        }
    }

    private func connectingView(environment: PlaidEnvironment) -> some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Opening Plaid Link...")
                .font(.title3)

            Text("Complete the \(environment.rawValue) login in your browser, then return here.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)

            Button {
                Task {
                    await appState.refreshAccounts()
                    if appState.isSetupComplete {
                        await appState.syncTransactions()
                        onComplete?()
                    }
                }
            } label: {
                Label("Check Connection", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

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
