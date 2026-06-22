import PlaidBarCore
import SwiftUI

/// The ⌘K command palette overlay (AND-596).
///
/// A spotlight-style overlay rendered at the `AppShellView` window level: a
/// search field over the pure ``CommandRegistry``, with fuzzy filtering
/// (``FuzzyMatcher``), `↑`/`↓` to move, `Return` to execute, and `Esc` to
/// dismiss. It is **keyboard-first** — the field auto-focuses on present, and
/// every command is reachable without the mouse.
///
/// Selecting a command dispatches its `Kind` through ``CommandDispatcher``, which
/// calls the *existing* action paths (navigate → `NavigationModel.destination`;
/// act → the real refresh / Privacy Mask / settings / summon paths) — the palette
/// never reimplements behavior.
///
/// This view exists **only** in the window-first surface: it is presented from
/// `AppShellView`, which is only ever instantiated behind `WindowFirstFeatureFlag`
/// (default OFF). With the flag off the palette never appears, so flag-OFF
/// behavior is byte-identical to today.
struct CommandPalette: View {
    /// Drives present/dismiss; owned by `AppShellView` so the ⌘K command and the
    /// overlay share one source of truth.
    @Bindable var model: CommandPaletteModel
    /// Executes a chosen command against the live app actions.
    let dispatcher: CommandDispatcher

    @State private var query = ""
    @State private var highlightedIndex = 0
    @FocusState private var searchFieldFocused: Bool

    /// The registry filtered by the current query, best match first. Empty query
    /// shows the full command list (registry order).
    private var results: [CommandRegistry.Command] {
        model.registry.search(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsList
        }
        .frame(width: 560)
        .frame(maxHeight: 420)
        .glassSurface(.raised, cornerRadius: Radius.panel)
        .shadow(radius: 24, y: 8)
        .padding(.top, Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(scrim)
        .onAppear { searchFieldFocused = true }
        .onChange(of: query) { _, _ in
            // A new query reorders results — keep the highlight in range and on
            // the new best match.
            highlightedIndex = 0
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command palette")
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search commands…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFieldFocused)
                .onSubmit(executeHighlighted)
                .accessibilityLabel("Search commands")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        // Keyboard-first navigation: arrow keys move the highlight, Esc dismisses.
        // These attach to the field so they work while typing.
        .onKeyPress(.downArrow) { moveHighlight(by: 1); return .handled }
        .onKeyPress(.upArrow) { moveHighlight(by: -1); return .handled }
        .onKeyPress(.escape) { model.dismiss(); return .handled }
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if results.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                            CommandPaletteRow(
                                command: command,
                                isHighlighted: index == highlightedIndex
                            )
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { execute(command) }
                            // The row carries the `.isButton` trait, so VoiceOver
                            // announces it as a button and its activate gesture must
                            // run the command — `.onTapGesture` alone is invisible to
                            // VoiceOver (matches the `.accessibilityAction` pattern in
                            // MainPopover.swift account rows).
                            .accessibilityAction { execute(command) }
                            .onHover { hovering in
                                if hovering { highlightedIndex = index }
                            }
                        }
                    }
                }
                .padding(Spacing.xs)
            }
            .onChange(of: highlightedIndex) { _, index in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        Text("No commands match “\(query)”.")
            .detailText()
            .foregroundStyle(.secondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scrim: some View {
        // A dim scrim catches clicks outside the panel to dismiss, and darkens the
        // shell behind the overlay. Decorative, so hidden from VoiceOver.
        Color.black.opacity(0.18)
            .ignoresSafeArea()
            .onTapGesture { model.dismiss() }
            .accessibilityHidden(true)
    }

    // MARK: - Keyboard handling

    private func moveHighlight(by delta: Int) {
        guard !results.isEmpty else { return }
        let count = results.count
        highlightedIndex = (highlightedIndex + delta + count) % count
    }

    private func executeHighlighted() {
        guard results.indices.contains(highlightedIndex) else { return }
        execute(results[highlightedIndex])
    }

    private func execute(_ command: CommandRegistry.Command) {
        model.dismiss()
        dispatcher.run(command.kind)
    }
}

// MARK: - Row

/// One palette result row: icon + title + optional subtitle/shortcut. The title
/// carries the meaning; the icon is chrome and the highlight uses the native
/// selection treatment (never color alone — ACCESSIBILITY.md).
private struct CommandPaletteRow: View {
    let command: CommandRegistry.Command
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: command.systemImage)
                .frame(width: Sizing.iconNav)
                .foregroundStyle(isHighlighted ? Color.white : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(command.title)
                    .font(.body)
                    .foregroundStyle(isHighlighted ? Color.white : .primary)
                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .microText()
                        .foregroundStyle(isHighlighted ? Color.white.opacity(0.8) : .secondary)
                }
            }
            Spacer(minLength: Spacing.sm)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(Color.accentColor)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
    }

    private var accessibilityLabel: String {
        guard let subtitle = command.subtitle else { return command.title }
        return "\(command.title), \(subtitle)"
    }
}
