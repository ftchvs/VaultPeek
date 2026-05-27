import SwiftUI
import PlaidBarCore

struct SetupView: View {
    @Environment(AppState.self) private var appState
    @State private var setupMode: SetupMode = .choose

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
        .frame(width: 360)
        .animation(.easeInOut(duration: 0.25), value: setupMode)
    }

    private var choiceView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(SemanticColors.brand)

            VStack(spacing: Spacing.xs) {
                Text("Welcome to PlaidBar")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Choose exactly what data source to use before anything connects.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            VStack(spacing: Spacing.sm) {
                OnboardingChoiceButton(
                    title: "View Demo",
                    subtitle: "Local fixture data. No Plaid credentials or network calls.",
                    icon: "play.circle",
                    color: SemanticColors.brandSecondary
                ) {
                    appState.startDemoMode()
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
