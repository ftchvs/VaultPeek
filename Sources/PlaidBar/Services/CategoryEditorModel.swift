import Foundation
import OSLog
import PlaidBarCache
import PlaidBarCore

/// App-side state for the budgeting-v2 categories & groups editor (AND-547 —
/// deferred epic AND-524).
///
/// Owns the opt-in ``BudgetingV2Store`` and the in-memory ``BudgetingV2Schema`` the
/// editor view renders, and routes every mutation through the pure
/// ``BudgetCategoryEditor`` in `PlaidBarCore` (all validation/CRUD logic is there
/// and unit-tested; this model only persists the result and surfaces errors).
///
/// ## Opt-in & additive
/// The editor is **opt-in**: until the user explicitly opens it and seeds v2, no v2
/// snapshot exists and v1 budgeting is byte-for-byte unchanged. `load()` only reads
/// an existing snapshot; `optIn()` seeds one (carrying any v1 budgets forward).
/// Opting out (`optOut(month:)`) recovers the v1 budgets and clears the snapshot,
/// restoring v1 untouched.
///
/// ## Fallback-safe
/// The store is opened with `try?` and every persist is best-effort; a store failure
/// leaves the editor read-only and the rest of the app on v1.
///
/// ## Privacy / isolation
/// The store writes only to the local private data dir (never the App Group or
/// iCloud) and only `Sendable` values cross the actor boundary. The editor surfaces
/// category *labels and budget limits*, which are financial data — so the hosting
/// view respects Privacy Mask / App Lock exactly like every other budget surface.
@MainActor
@Observable
public final class CategoryEditorModel {
    private static let logger = Logger(subsystem: "com.ftchvs.PlaidBar", category: "CategoryEditor")

    /// The currently loaded v2 schema, or `nil` when the user has not opted in (or
    /// the store is unavailable). The editor view shows the opt-in prompt when `nil`.
    public private(set) var schema: BudgetingV2Schema?

    /// The most recent user-facing edit error, cleared on the next successful edit.
    /// Carried as text by the view (never color-alone, ACCESSIBILITY.md).
    public private(set) var lastError: BudgetCategoryEditor.BudgetCategoryEditError?

    /// True while a load/seed/persist round-trip is in flight (disables controls).
    public private(set) var isBusy = false

    private let store: BudgetingV2Store?
    private let cacheKey: String

    /// - Parameters:
    ///   - store: the opened v2 store, or `nil` (demo / disabled / open failed) — in
    ///     which case the editor stays empty and read-only.
    ///   - cacheKey: the environment+directory-scoped key (the same one the other
    ///     caches use), so the v2 snapshot is scoped per Plaid environment.
    public init(store: BudgetingV2Store?, cacheKey: String) {
        self.store = store
        self.cacheKey = cacheKey
    }

    /// Whether the user has opted into v2 (a schema is loaded).
    public var isOptedIn: Bool { schema != nil }

    /// Groups in display order (by `sortIndex`, then name) for the editor list.
    public var orderedGroups: [BudgetCategoryGroupV2] {
        (schema?.groups ?? []).sorted { lhs, rhs in
            lhs.sortIndex != rhs.sortIndex ? lhs.sortIndex < rhs.sortIndex : lhs.name < rhs.name
        }
    }

    /// Categories in `group`, in within-group display order (by `sortIndex`, then name).
    public func categories(in group: BudgetCategoryGroupV2) -> [BudgetCategoryV2] {
        (schema?.categories ?? [])
            .filter { $0.groupId == group.id }
            .sorted { lhs, rhs in
                lhs.sortIndex != rhs.sortIndex ? lhs.sortIndex < rhs.sortIndex : lhs.name < rhs.name
            }
    }

    // MARK: - Load / opt-in / opt-out

    /// Load an existing v2 snapshot (no-op when not opted in). Best-effort.
    public func load() async {
        guard let store else { return }
        isBusy = true
        defer { isBusy = false }
        schema = try? await store.load(cacheKey: cacheKey)
    }

    /// Opt into v2: seed the schema from the closed taxonomy, optionally carrying the
    /// user's existing v1 budgets into `month`, and persist. Idempotent.
    public func optIn(carryingForward v1Budgets: [CategoryBudgetDTO] = [], month: String? = nil) async {
        guard let store else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            schema = try await store.seedV2(cacheKey: cacheKey, carryingForward: v1Budgets, month: month)
            lastError = nil
        } catch {
            Self.logger.error("v2 opt-in failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Opt out of v2: recover the v1 budgets for `month`, clear the snapshot, and
    /// return the recovered budgets so the caller can write them back to the v1
    /// `/api/budgets` store. v1 budgeting is restored untouched.
    @discardableResult
    public func optOut(month: String) async -> [CategoryBudgetDTO] {
        guard let store else { schema = nil; return [] }
        isBusy = true
        defer { isBusy = false }
        let recovered = (try? await store.optOut(cacheKey: cacheKey, month: month)) ?? []
        schema = nil
        return recovered
    }

    // MARK: - Category edits (delegate to the pure editor, then persist)

    /// Create a custom category. `id` is generated here (UUID) so the pure editor
    /// stays deterministic.
    public func addCategory(name: String, emoji: String?, colorHex: String, groupId: String) async {
        await apply { schema in
            BudgetCategoryEditor.addCategory(
                to: schema,
                id: BudgetCategoryEditor.customCategoryID(UUID().uuidString),
                name: name,
                emoji: emoji,
                colorHex: colorHex,
                groupId: groupId
            )
        }
    }

    /// Rename / recolor / re-emoji a category (system or custom). `emoji: .some(nil)`
    /// clears the glyph; `nil` leaves a field untouched.
    public func editCategory(
        categoryId: String,
        name: String? = nil,
        emoji: String?? = nil,
        colorHex: String? = nil
    ) async {
        await apply { schema in
            BudgetCategoryEditor.editCategory(
                in: schema, categoryId: categoryId, name: name, emoji: emoji, colorHex: colorHex
            )
        }
    }

    /// Move a category to another group.
    public func moveCategory(categoryId: String, toGroupId: String) async {
        await apply { schema in
            BudgetCategoryEditor.moveCategory(in: schema, categoryId: categoryId, toGroupId: toGroupId)
        }
    }

    /// Reorder categories within a group.
    public func reorderCategories(groupId: String, orderedCategoryIds: [String]) async {
        await apply { schema in
            BudgetCategoryEditor.reorderCategories(
                in: schema, groupId: groupId, orderedCategoryIds: orderedCategoryIds
            )
        }
    }

    /// Delete a custom category, reassigning its budgets to `reassignToCategoryId`
    /// (default: the `.other` system category). Returns the reassignment mapping so
    /// the caller can re-point any transaction-level overrides the same way.
    @discardableResult
    public func deleteCustomCategory(
        categoryId: String,
        reassignToCategoryId: String? = nil
    ) async -> BudgetCategoryEditor.DeletionResult? {
        guard let current = schema else { return nil }
        let result = BudgetCategoryEditor.deleteCustomCategory(
            in: current, categoryId: categoryId, reassignToCategoryId: reassignToCategoryId
        )
        switch result {
        case .success(let deletion):
            await persist(deletion.schema)
            return deletion
        case .failure(let error):
            lastError = error
            return nil
        }
    }

    // MARK: - Group edits

    /// Create a custom group.
    public func addGroup(name: String) async {
        await apply { schema in
            BudgetCategoryEditor.addGroup(
                to: schema, id: BudgetCategoryEditor.customGroupID(UUID().uuidString), name: name
            )
        }
    }

    /// Rename a group (system or custom).
    public func renameGroup(groupId: String, name: String) async {
        await apply { schema in
            BudgetCategoryEditor.renameGroup(in: schema, groupId: groupId, name: name)
        }
    }

    /// Reorder groups top-to-bottom.
    public func reorderGroups(orderedGroupIds: [String]) async {
        await apply { schema in
            BudgetCategoryEditor.reorderGroups(in: schema, orderedGroupIds: orderedGroupIds)
        }
    }

    /// Delete a custom group, moving its categories to `reassignToGroupId` (default:
    /// the `.other` system group).
    public func deleteCustomGroup(groupId: String, reassignToGroupId: String? = nil) async {
        await apply { schema in
            BudgetCategoryEditor.deleteCustomGroup(
                in: schema, groupId: groupId, reassignToGroupId: reassignToGroupId
            )
        }
    }

    // MARK: - Internals

    /// Run a pure edit against the current schema; on success persist + adopt the new
    /// snapshot and clear the error, on failure surface the error and leave the
    /// schema untouched (the edit is rejected, not partially applied).
    private func apply(
        _ edit: (BudgetingV2Schema) -> Result<BudgetingV2Schema, BudgetCategoryEditor.BudgetCategoryEditError>
    ) async {
        guard let current = schema else { return }
        switch edit(current) {
        case .success(let updated):
            await persist(updated)
        case .failure(let error):
            lastError = error
        }
    }

    /// Adopt `updated` in memory and persist it (best-effort). The in-memory schema
    /// is updated regardless so the UI reflects the edit even if a disk write fails;
    /// the snapshot is disposable and reseedable, so a transient write failure is
    /// non-fatal.
    private func persist(_ updated: BudgetingV2Schema) async {
        schema = updated
        lastError = nil
        guard let store else { return }
        do {
            try await store.save(cacheKey: cacheKey, schema: updated)
        } catch {
            Self.logger.error("v2 schema persist failed: \(String(describing: error), privacy: .public)")
        }
    }
}
