import Foundation
import PlaidBarCore

/// Manages background refresh timers for account data
@MainActor
final class RefreshService {
    private var refreshTask: Task<Void, Never>?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        stop()
        let state = appState
        refreshTask = Task {
            while !Task.isCancelled {
                await state.refreshAccounts()
                await state.syncTransactions()
                try? await Task.sleep(for: .seconds(state.refreshInterval))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
