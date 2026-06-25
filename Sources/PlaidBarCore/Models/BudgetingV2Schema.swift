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
    /// A user-created group (AND-547) uses a fresh `"grp_<uuid>"` string here; a
    /// seeded group keeps the closed-taxonomy `rawValue`, so every *seeded* id
    /// round-trips back to a ``CategoryGroup`` while a custom one never collides.
    public let id: String
    /// Human-readable group title (seeded from ``CategoryGroup/title``; user-editable
    /// via the categories editor, AND-547).
    public let name: String
    /// Top-to-bottom display order (seeded from ``CategoryGroup/sortIndex``;
    /// user-reorderable via the categories editor, AND-547).
    public let sortIndex: Int
    /// The ``CategoryGroup`` this row seeded from, when `id` is a seeded taxonomy
    /// key. `nil` for a user-created group (AND-547) with no v1 ancestor. Lets a
    /// reverse migration map a v2 group back to its v1 origin losslessly, and lets
    /// the editor distinguish a deletable custom group from a protected system one.
    public let seededFromGroup: CategoryGroup?

    /// Whether this group was created by the user (AND-547) rather than seeded from
    /// the closed taxonomy. Derived from ``seededFromGroup`` so the two can never
    /// disagree: a seeded group always has an ancestor, a custom one never does.
    public var isCustom: Bool { seededFromGroup == nil }

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
    /// Stable identity — the seeded ``SpendingCategory`` `rawValue`. A user-created
    /// category (AND-547) uses a fresh `"cat_<uuid>"` string; a seeded row keeps the
    /// closed-enum `rawValue`, so every *seeded* id round-trips back to a
    /// ``SpendingCategory`` via ``seededFromCategory`` while a custom one never
    /// collides with — or shadows — a Plaid key.
    public let id: String
    /// Display name (seeded from ``SpendingCategory/displayName``). User-renamable
    /// via the categories editor (AND-547) for both system and custom rows.
    public let name: String
    /// SF Symbol for the category icon (seeded from ``SpendingCategory/iconName``).
    public let iconName: String
    /// Optional user emoji glyph shown in place of (or alongside) ``iconName`` in
    /// the editor and dashboard (AND-547). `nil` for a seeded row that the user has
    /// not re-emoji'd, so a not-edited category renders exactly as v1 did.
    /// Decoded as `nil` when absent, so a pre-AND-547 snapshot keeps the SF Symbol.
    public let emoji: String?
    /// Display color as a `#RRGGBB` hex string (seeded from
    /// ``SpendingCategory/colorHex``). User-recolorable via the editor (AND-547).
    /// Decoded as the seeded color (or a neutral fallback for a custom row) when
    /// absent, so a pre-AND-547 snapshot keeps the v1 chart color.
    public let colorHex: String
    /// Parent group id (the seeded ``BudgetCategoryGroupV2/id``). User-movable
    /// between groups via the editor (AND-547).
    public let groupId: String
    /// Within-group display order (AND-547). Seeded rows default to `0` and fall
    /// back to display-name ordering; the editor assigns explicit indices on
    /// reorder. Decoded as `0` when absent so a pre-AND-547 snapshot is stable.
    public let sortIndex: Int
    /// The ``SpendingCategory`` this row seeded from, preserving the exact v1
    /// taxonomy link **even after a rename/recolor** — renaming a system category
    /// never breaks its `systemKey → Plaid` mapping. `nil` only for a user-created
    /// category (AND-547) with no v1 ancestor. Lets a reverse migration drop
    /// straight back to the v1 enum key without a name lookup, and lets the editor
    /// tell a deletable custom row from a protected system one.
    public let seededFromCategory: SpendingCategory?

    /// Whether this category was created by the user (AND-547) rather than seeded
    /// from the closed enum. Derived from ``seededFromCategory`` so a system row can
    /// never be misclassified as deletable: a seeded row always has a v1 ancestor.
    public var isCustom: Bool { seededFromCategory == nil }

    public init(
        id: String,
        name: String,
        iconName: String,
        emoji: String? = nil,
        colorHex: String,
        groupId: String,
        sortIndex: Int = 0,
        seededFromCategory: SpendingCategory?
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.emoji = emoji
        self.colorHex = colorHex
        self.groupId = groupId
        self.sortIndex = sortIndex
        self.seededFromCategory = seededFromCategory
    }

    /// Seed a v2 category row from a ``SpendingCategory``, linking it to the group
    /// the category rolls up into (``SpendingCategory/group``) and carrying the v1
    /// chart color forward so an unedited category is visually identical to v1.
    public init(seedingFrom category: SpendingCategory) {
        self.init(
            id: category.rawValue,
            name: category.displayName,
            iconName: category.iconName,
            emoji: nil,
            colorHex: category.colorHex,
            groupId: category.group.rawValue,
            sortIndex: 0,
            seededFromCategory: category
        )
    }

    // MARK: - Backward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case id, name, iconName, emoji, colorHex, groupId, sortIndex, seededFromCategory
    }

    /// Custom decoder so a snapshot written **before AND-547** (no `emoji` /
    /// `colorHex` / `sortIndex` keys) still decodes: the new fields default rather
    /// than throwing, keeping the v2 store self-healing and the upgrade additive.
    /// A missing color falls back to the seeded ``SpendingCategory/colorHex`` when
    /// the row links to one, else a neutral gray, so no row is ever color-less.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        iconName = try container.decode(String.self, forKey: .iconName)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        groupId = try container.decode(String.self, forKey: .groupId)
        sortIndex = try container.decodeIfPresent(Int.self, forKey: .sortIndex) ?? 0
        let seeded = try container.decodeIfPresent(SpendingCategory.self, forKey: .seededFromCategory)
        seededFromCategory = seeded
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
            ?? seeded?.colorHex
            ?? BudgetCategoryV2.neutralColorHex
    }

    /// Neutral fallback color for a custom row whose snapshot somehow omits one
    /// (matches ``SpendingCategory/other`` so it reads as an unstyled category).
    public static let neutralColorHex = "#BDC3C7"
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
