import SwiftUI
import PlaidBarCore

struct SetupView: View {
    @Environment(AppState.self) private var appState
    @State private var setupMode: SetupMode = .welcome
    @State private var clientId = ""
    @State private var secret = ""

    enum SetupMode: Sendable {
        case welcome
        case sandbox
        case credentials
        case connecting
    }

    var body: some View {
        VStack(spacing: 16) {
            switch setupMode {
            case .welcome:
                welcomeView
            case .sandbox:
                sandboxView
            case .credentials:
                credentialsView
            case .connecting:
                connectingView
            }
        }
        .padding()
        .frame(width: 360)
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Welcome to PlaidBar")
                .font(.title2)
                .fontWeight(.bold)

            Text("Connect your bank accounts to see\nbalances and spending in your menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
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

                Button {
                    setupMode = .credentials
                } label: {
                    HStack {
                        Image(systemName: "key")
                        Text("Use my Plaid credentials")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var sandboxView: some View {
        VStack(spacing: 16) {
            Image(systemName: "testtube.2")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

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

    private var credentialsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("Plaid Credentials")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Enter your Plaid API credentials. Get them at dashboard.plaid.com")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.callout)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Client ID", text: $clientId)
                    .textFieldStyle(.roundedBorder)
                SecureField("Secret", text: $secret)
                    .textFieldStyle(.roundedBorder)
            }

            Button("Connect") {
                setupMode = .connecting
                Task { await appState.addAccount() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(clientId.isEmpty || secret.isEmpty)

            Button("Back") {
                setupMode = .welcome
            }
            .buttonStyle(.borderless)
        }
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
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
