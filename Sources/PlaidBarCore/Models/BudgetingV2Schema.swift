import Foundation

/// Budgeting v2 persisted schema — pure, `Sendable` value types (AND-546).
///
/// ## What this is (and is not)
///
/// This file is the **schema foundation** for the deferred budgeting-v2 epic
/// (AND-524): the persisted `Category` / `CategoryGroup` / `Budget(month, rollover)`
/// records that *replace the flat-enum* ``SpendingCategory`` primary key with a
/// stable, user-editable category table. It is intentionally **only the data
/// model + seed** — the editor UI, per-month budgets, rebalance, splits, rules
/// manager, and sync (AND-547…AND-553) are separate later PRs and are **not**
/// built here.
///
/// ## v1-safety contract
///
/// The schema is **purely additive**. It does not change any ``SpendingCategory``
/// `rawValue`, the v1 ``CategoryBudgetDTO`` shape, or the v1 `/api/budgets`
/// storage. A user who does **not** opt into v2 never reads or writes any of these
/// records; the v2 store (`PlaidBarCache.BudgetingV2Store`) is only seeded on an
/// explicit opt-in, and tearing it down restores v1 untouched (the records are
/// disposable and rebuildable from ``SpendingCategory`` at any time).
///
/// ## Seeding preserves today's categorization
///
/// The new ``BudgetCategoryV2`` table is seeded one-to-one from the existing
/// ``SpendingCategory`` set (``BudgetingV2Seed/categories``), keyed by the same
/// `rawValue` so a v1 budget or a categorized transaction maps to exactly its v2
/// category without reclassification. Groups seed from ``CategoryGroup`` the same
/// way. Current categorization is therefore preserved bit-for-bit at opt-in.

// MARK: - Category group (v2 persisted parent)

/// A persisted budgeting-v2 category **group** (parent of the 2-level tree).
///
/// Seeds one-to-one from the closed ``CategoryGroup`` taxonomy: `id` is the
/// group's stable `rawValue`, so a v2 category can reference its parent by a
/// migration-stable key. Additive — it does not alter ``CategoryGroup`` itself.
public struct BudgetCategoryGroupV2: Codable, Sendable, Hashable, Identifiable {
    /// Stable identity — the seeded ``CategoryGroup`` `rawValue` (e.g. `HOUSING`).
    /// A user-created group (a later epic) would use a fresh UUID string here; the
    /// foundation only ever seeds the closed taxonomy, so every id round-trips back
    /// to a ``CategoryGroup``.
    public let id: String
    /// Human-readable group title (seeded from ``CategoryGroup/title``).
    public let name: String
    /// Top-to-bottom display order (seeded from ``CategoryGroup/sortIndex``).
    public let sortIndex: Int
    /// The ``CategoryGroup`` this row seeded from, when `id` is a seeded taxonomy
    /// key. `nil` for a (future) user-created group with no v1 ancestor. Lets a
    /// reverse migration map a v2 group back to its v1 origin losslessly.
    public let seededFromGroup: CategoryGroup?

    public init(id: String, name: String, sortIndex: Int, seededFromGroup: CategoryGroup?) {
        self.id = id
        self.name = name
        self.sortIndex = sortIndex
        self.seededFromGroup = seededFromGroup
    }

    /// Seed a v2 group row from a closed-taxonomy ``CategoryGroup``.
    public init(seedingFrom group: CategoryGroup) {
        self.init(
            id: group.rawValue,
            name: group.title,
            sortIndex: group.sortIndex,
            seededFromGroup: group
        )
    }
}

// MARK: - Category (v2 persisted leaf)

/// A persisted budgeting-v2 **category** (leaf of the 2-level tree).
///
/// Seeds one-to-one from ``SpendingCategory``: `id` is the category's stable
/// `rawValue` (the same Plaid `personal_finance_category.primary` key the v1 enum
/// uses), so a v1 budget keyed on that category — and every already-categorized
/// transaction — maps to its v2 row with no reclassification. `groupId` references
/// the seeded ``BudgetCategoryGroupV2``.
public struct BudgetCategoryV2: Codable, Sendable, Hashable, Identifiable {
    /// Stable identity — the seeded ``SpendingCategory`` `rawValue`. A
    /// user-created category (a later epic) would use a fresh UUID string; the
    /// foundation only ever seeds the closed enum, so every id round-trips back to
    /// a ``SpendingCategory`` via ``seededFromCategory``.
    public let id: String
    /// Display name (seeded from ``SpendingCategory/displayName``). User-editable in
    /// a later epic; the foundation just carries the v1 name forward.
    public let name: String
    /// SF Symbol for the category icon (seeded from ``SpendingCategory/iconName``).
    public let iconName: String
    /// Parent group id (the seeded ``BudgetCategoryGroupV2/id``).
    public let groupId: String
    /// The ``SpendingCategory`` this row seeded from, preserving the exact v1
    /// taxonomy link. `nil` only for a (future) user-created category with no v1
    /// ancestor — never for a seeded row. Lets a reverse migration drop straight
    /// back to the v1 enum key without a name lookup.
    public let seededFromCategory: SpendingCategory?

    public init(
        id: String,
        name: String,
        iconName: String,
        groupId: String,
        seededFromCategory: SpendingCategory?
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.groupId = groupId
        self.seededFromCategory = seededFromCategory
    }

    /// Seed a v2 category row from a ``SpendingCategory``, linking it to the group
    /// the category rolls up into (``SpendingCategory/group``).
    public init(seedingFrom category: SpendingCategory) {
        self.init(
            id: category.rawValue,
            name: category.displayName,
            iconName: category.iconName,
            groupId: category.group.rawValue,
            seededFromCategory: category
        )
    }
}

// MARK: - Monthly budget (v2 — per-month + rollover)

/// A persisted budgeting-v2 **budget**: a per-month limit for one category, with
/// an optional rollover of the prior month's unspent remainder.
///
/// This is the v2 replacement for the v1 ``CategoryBudgetDTO`` (a single, undated
/// `monthlyLimit` per category). The new record adds a `month` dimension — so a
/// limit can change month to month (AND-548) — and a `rollover` flag carried by
/// the foundation for the later rebalance epic (AND-550). The foundation only
/// *stores* these fields; the per-month editor and rollover math land later.
public struct MonthlyBudgetV2: Codable, Sendable, Hashable, Identifiable {
    /// The budgeted month as `YYYY-MM` (the first-of-month bucket). Lexicographic
    /// order equals chronological order, matching the `YYYY-MM-DD` convention the
    /// rest of the app sorts transactions by.
    public let month: String
    /// The v2 category this budget applies to (``BudgetCategoryV2/id``).
    public let categoryId: String
    /// The limit for `month`, in the account's display currency.
    public let monthlyLimit: Double
    /// Whether an unspent remainder rolls into the next month. Stored by the
    /// foundation; the rollover *calculation* is a later epic (AND-550).
    public let rollover: Bool

    /// Stable identity — one budget per (month, category).
    public var id: String { "\(month)|\(categoryId)" }

    public init(month: String, categoryId: String, monthlyLimit: Double, rollover: Bool = false) {
        self.month = month
        self.categoryId = categoryId
        self.monthlyLimit = monthlyLimit
        self.rollover = rollover
    }

    /// Seed a v2 monthly budget from a v1 ``CategoryBudgetDTO`` for a given month.
    /// The v1 limit is undated, so opt-in seeds it as the chosen month's limit with
    /// rollover off, preserving the v1 number exactly.
    public init(seedingFrom v1Budget: CategoryBudgetDTO, month: String) {
        self.init(
            month: month,
            categoryId: v1Budget.category.rawValue,
            monthlyLimit: v1Budget.monthlyLimit,
            rollover: false
        )
    }
}

// MARK: - Schema snapshot (the persisted v2 record)

/// The full budgeting-v2 schema snapshot persisted by `PlaidBarCache`.
///
/// One snapshot holds the seeded category/group tables plus any per-month budgets
/// for a single Plaid environment. It is `Codable` so the cache store can persist
/// it as a JSON blob, and `schemaVersion`-tagged so a forward migration can
/// self-heal a stale snapshot (read as a miss, reseed) exactly like the disposable
/// read-model cache.
public struct BudgetingV2Schema: Codable, Sendable, Hashable {
    /// Current schema version. Bump when the persisted shape changes so older
    /// snapshots read as a miss and reseed (additive, never a destructive upgrade).
    public static let currentSchemaVersion = 1

    /// The schema version this snapshot was written with.
    public let schemaVersion: Int
    /// Seeded (and, later, user) category groups, in stable order.
    public let groups: [BudgetCategoryGroupV2]
    /// Seeded (and, later, user) categories, in stable order.
    public let categories: [BudgetCategoryV2]
    /// Per-month budgets. Empty at first seed (the foundation seeds the taxonomy,
    /// not budgets) unless v1 budgets were carried in at opt-in.
    public let budgets: [MonthlyBudgetV2]

    public init(
        schemaVersion: Int = BudgetingV2Schema.currentSchemaVersion,
        groups: [BudgetCategoryGroupV2],
        categories: [BudgetCategoryV2],
        budgets: [MonthlyBudgetV2]
    ) {
        self.schemaVersion = schemaVersion
        self.groups = groups
        self.categories = categories
        self.budgets = budgets
    }

    /// Whether this snapshot matches the current schema version. A stale snapshot is
    /// treated as a cache miss by the store and reseeded.
    public var isCurrentSchema: Bool {
        schemaVersion == Self.currentSchemaVersion
    }

    /// Look up a seeded category by its stable id (the ``SpendingCategory``
    /// `rawValue`). `O(n)` over the small closed table — fine for the foundation.
    public func category(id: String) -> BudgetCategoryV2? {
        categories.first { $0.id == id }
    }

    /// Look up a seeded group by its stable id (the ``CategoryGroup`` `rawValue`).
    public func group(id: String) -> BudgetCategoryGroupV2? {
        groups.first { $0.id == id }
    }
}
