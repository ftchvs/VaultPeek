# VaultPeek macOS 26 — Window-First Architecture Evaluation

**Date:** 2026-06-19 · **Status:** Proposed (pending ratification) · **Supersedes the product-model half of AND-384**

This folder is the formal evaluation of whether VaultPeek should evolve from a
menu-bar **popover-primary** application into a full native macOS 26 application
where the primary experience lives in a dedicated window and the menu bar becomes
a launcher + glance surface. It was produced by a 5-agent parallel research pass
plus synthesis.

## The one-sentence answer

**Yes — adopt a window-first *hybrid* — but understand that this is a
*consolidation of what VaultPeek already shipped*, not a risky greenfield
migration.** The app is already multi-window in code; only its doctrine, its
navigation shell, and one declarative scene are missing.

## Read in this order

| # | Document | Deliverable |
|---|----------|-------------|
| 00 | [Executive Recommendation](00-executive-recommendation.md) | Exec rec · effort · sequence · survives/rebuilds % |
| — | [ADR-001: Window-First Architecture](ADR-001-window-first-architecture.md) | ADR replacing AND-384 |
| 01 | [Current-State Architecture](01-current-state-architecture.md) | Architecture assessment · tech debt · complexity |
| 02 | [Product Strategy](02-product-strategy.md) | Product recommendation · UX tradeoffs · platform strategy |
| 03 | [Repository Archaeology](03-archaeology.md) | History · lessons · migration risks |
| 04 | [macOS 26 Platform Research](04-platform-research.md) | Best practices · recommended patterns · UX opportunities |
| 04a | [Apple Docs Verification (sosumi.ai)](04a-apple-docs-sosumi.md) | Authoritative Apple-docs confirmation of 04 |
| 05 | [Information Architecture](05-information-architecture.md) | IA · navigation model · screen hierarchy · principles |
| — | [Survives vs Rebuilds Matrix](survives-vs-rebuilds-matrix.md) | What survives / adapts / rebuilds |
| — | [Migration Roadmap](migration-roadmap.md) | Phased roadmap + sequencing |
| — | [Risk Register](risk-register.md) | Risks, likelihood, impact, mitigation |

## Linear

Filed under team **Andeslab (AND)**, project
[VaultPeek macOS 26 — Window-First Architecture](https://linear.app/andeslab/project/vaultpeek-macos-26-window-first-architecture-80d1c1afaa2c)
— 11 epics + 30 sub-issues, all in **Backlog pending Gate 0**, with dependencies,
acceptance criteria, technical/design notes, and sequencing.

| Epic | Linear | Sub-issues |
|------|--------|-----------|
| Gate 0 — Decision & Doctrine | AND-578 | AND-589, 590 |
| 1 — Application Shell | AND-579 | AND-591, 592, 593 |
| 2 — Navigation Architecture | AND-580 | AND-594, 595, 596, 597 |
| 3 — Window Lifecycle Migration | AND-581 | AND-598, 599, 600 |
| 4 — Transaction Workspace | AND-582 | AND-601, 602, 603 |
| 5 — Planning & Budgeting (+ Goals) | AND-583 | AND-604, 605, 606 |
| 6 — Review Inbox | AND-584 | AND-607, 608, 609 |
| 7 — Insights & Intelligence | AND-585 | AND-610, 611 |
| 8 — Widgets & App Intents | AND-586 | AND-612, 613, 614 |
| 9 — Menu Bar Simplification | AND-587 | AND-615, 616 |
| 10 — Liquid Glass Polish | AND-588 | AND-617, 618 |

Critical path: **AND-578 → 579 → 580 → 581 → {582, 583, 584, 585} → 587**.

## How to challenge this

Every document includes the strongest counter-argument to its own conclusion.
The headline counter-case — *"the autonomous build loop overshot the popover
doctrine; the disciplined move is to delete windows, not bless them"* — is taken
seriously and rebutted explicitly in
[00](00-executive-recommendation.md#the-honest-counter-case) and the ADR's
rejected options. If you disagree, that is the section to attack.
