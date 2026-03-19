import SwiftUI
import PlaidBarCore

struct SetupView: View {
    @Environment(AppState.self) private var appState
    @State private var setupMode: SetupMode = .welcome

    enum SetupMode: Sendable {
        case welcome
        case sandbox
        case connecting
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Step indicator
            HStack(spacing: Spacing.sm) {
                ForEach(0..<2) { step in
                    Circle()
                        .fill(stepIndex >= step ? SemanticColors.brand : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, Spacing.sm)

            switch setupMode {
            case .welcome:
                welcomeView
            case .sandbox:
                sandboxView
            case .connecting:
                connectingView
            }
        }
        .padding()
        .frame(width: 360)
        .animation(.easeInOut(duration: 0.25), value: setupMode)
    }

    private var stepIndex: Int {
        switch setupMode {
        case .welcome: return 0
        case .sandbox: return 1
        case .connecting: return 1
        }
    }

    private var welcomeView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(SemanticColors.brand)

            Text("Welcome to PlaidBar")
                .font(.title2)
                .fontWeight(.bold)

            Text("Connect your bank accounts to see\nbalances and spending in your menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: Spacing.md) {
                Button {
                    setupMode = .sandbox
                } label: {
                    HStack {
                        Image(systemName: "play.circle")
                        Text("Try with sandbox (demo data)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

            }
        }
    }

    private var sandboxView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "testtube.2")
                .font(.system(size: 36))
                .foregroundStyle(SemanticColors.brandSecondary)

            Text("Sandbox Mode")
                .font(.title3)
                .fontWeight(.semibold)

            Text("This will connect to Plaid's sandbox with demo bank data. No real financial data is used.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)

            Button("Add Demo Account") {
                setupMode = .connecting
                Task { await appState.addAccount() }
            }
            .buttonStyle(.borderedProminent)

            Button("Back") {
                setupMode = .welcome
            }
            .buttonStyle(.borderless)
        }
    }

    private var connectingView: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Connecting...")
                .font(.title3)

            Text("Complete the bank login in your browser, then return here.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)

            Button("Check Connection") {
                Task {
                    await appState.refreshAccounts()
                    if appState.isSetupComplete {
                        await appState.syncTransactions()
                    }
                }
            }
            .buttonStyle(.bordered)

            Button("Cancel") {
                setupMode = .welcome
            }
            .buttonStyle(.borderless)
        }
    }
}
