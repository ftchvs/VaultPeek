import Foundation
import PlaidBarCache
import PlaidBarCore

/// AppState wiring for the budgeting-v2 categories & groups editor (AND-547 —
/// deferred epic AND-524).
///
/// Reuses the AND-546 seams: it opens the opt-in ``BudgetingV2Store`` against the
/// active data directory and scopes it with the same ``readModelCacheKey()`` the
/// other disposable caches use, so the v2 schema is per-Plaid-environment. Like the
/// read-model and transaction caches the store is opened behind `try?`; a failure
/// leaves the editor empty/read-only and the app on v1 budgeting (additive,
/// fallback-safe).
extension AppState {
    /// Builds the editor model for the active environment, or a read-only model
    /// (`store: nil`) when v2 is unavailable (demo mode, no server context yet, or
    /// the store fails to open). The model loads its snapshot on appear, so a fresh
    /// instance per editor presentation is fine and keeps no long-lived disk handle.
    ///
    /// The store open is best-effort and never throws to the caller; a `nil` store
    /// yields an editor that can render the opt-in prompt but performs no I/O.
    @MainActor
    func makeCategoryEditorModel() -> CategoryEditorModel {
        guard !isDemoMode, let cacheKey = readModelCacheKey() else {
            // No environment context yet (or demo): editor stays read-only and v1
            // budgeting is untouched. A non-nil cacheKey is required so a seeded
            // snapshot is scoped; without one there is nothing to read or write.
            return CategoryEditorModel(store: nil, cacheKey: "")
        }
        let store = try? BudgetingV2Store(onDiskIn: activeStorageDirectoryURL)
        return CategoryEditorModel(store: store, cacheKey: cacheKey)
    }

    /// The current month as `YYYY-MM`, used to carry v1 budgets forward at opt-in and
    /// recover them on opt-out. Uses the same date convention the rest of the app
    /// sorts/keys budgets by.
    @MainActor
    func currentBudgetMonthKey(asOf date: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        return String(format: "%04d-%02d", year, month)
    }
}
