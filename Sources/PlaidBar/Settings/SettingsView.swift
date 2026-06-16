import AppKit
import PlaidBarCore
import Sparkle
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("settings.selectedTab") private var selectedTab = SettingsTab.general.rawValue
    let updater: SPUUpdater

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .environment(appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general.rawValue)

            AccountSettingsView()
                .environment(appState)
                .tabItem {
                    Label("Accounts", systemImage: "building.columns")
                }
                .tag(SettingsTab.accounts.rawValue)

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag(SettingsTab.appearance.rawValue)

            NotificationSettingsView()
                .environment(appState)
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .tag(SettingsTab.notifications.rawValue)

            AboutView(updater: updater)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about.rawValue)
        }
        .frame(
            minWidth: 560,
            idealWidth: 620,
            maxWidth: 720,
            minHeight: 480,
            idealHeight: 560,
            maxHeight: 640
        )
    }
}

private enum SettingsTab: String {
    case general
    case accounts
    case appearance
    case notifications
    case about
}

struct AppearanceSettingsView: View {
    @AppStorage(PopoverTransparencySetting.storageKey) private var popoverTransparency = PopoverTransparencySetting.defaultValue
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceModeRaw = AppAppearanceMode.defaultValue.rawValue
    @AppStorage(AppContrastPreference.storageKey) private var contrastRaw = AppContrastPreference.defaultValue.rawValue
    @AppStorage(DecorativeEffectsPreference.storageKey) private var decorativeRaw = DecorativeEffectsPreference.defaultValue.rawValue
    @AppStorage(AppDensityPreference.storageKey) private var densityRaw = AppDensityPreference.defaultValue.rawValue
    @Environment(\.colorSchemeContrast) private var systemContrast

    private var transparencySetting: PopoverTransparencySetting {
        PopoverTransparencySetting(value: popoverTransparency)
    }

    private var appearanceMode: AppAppearanceMode { AppAppearanceMode(rawValue: appearanceModeRaw) ?? .followSystem }
    private var contrastPreference: AppContrastPreference { AppContrastPreference(rawValue: contrastRaw) ?? .followSystem }
    private var decorativePreference: DecorativeEffectsPreference { DecorativeEffectsPreference(rawValue: decorativeRaw) ?? .followSystem }
    private var density: AppDensityPreference { AppDensityPreference(rawValue: densityRaw) ?? .comfortable }

    /// Increased contrast applies when the app pref asks for it OR the system
    /// Increase Contrast accessibility setting is on (system always wins).
    private var increasedContrast: Bool {
        contrastPreference.resolvedIncreasedContrast(systemIncreaseContrast: systemContrast == .increased)
    }

    var body: some View {
        Form {
            Section("Popover") {
                // Live preview first: the popover material renders with the
                // current settings over synthetic labels, so transparency,
                // presets, decorative effects, contrast, and density all have
                // immediate, privacy-safe feedback (AND-364 / AND-365).
                AppearancePreviewCard(
                    setting: transparencySetting,
                    increasedContrast: increasedContrast,
                    density: density
                )
                .padding(.vertical, Spacing.xxs)

                // Full-width control block: the label/value row sits at the top,
                // the slider spans the row, and the captions track the slider —
                // so nothing clips at the minimum settings window width and
                // "Transparency" anchors to the top instead of floating against a
                // width-constrained LabeledContent trailing column. (AND-363)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text("Transparency")

                        Spacer(minLength: Spacing.md)

                        Text("\(transparencySetting.displayPercent)%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { transparencySetting.value },
                            set: { popoverTransparency = PopoverTransparencySetting(value: $0).value }
                        ),
                        in: PopoverTransparencySetting.minimumValue...PopoverTransparencySetting.maximumValue,
                        step: 1
                    )
                    .labelsHidden()
                    .accessibilityLabel("Popover transparency")
                    .accessibilityValue("\(transparencySetting.displayPercent) percent transparent")

                    HStack {
                        Text("More solid")
                        Spacer()
                        Text("More glass")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    // Quick-pick presets map to the anchor values; the active one
                    // is filled. Reset returns to the recommended default.
                    HStack(spacing: Spacing.sm) {
                        ForEach(PopoverTransparencySetting.Preset.allCases) { preset in
                            presetButton(preset)
                        }

                        Spacer(minLength: Spacing.sm)

                        Button("Reset") {
                            popoverTransparency = PopoverTransparencySetting.defaultValue
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(transparencySetting.value == PopoverTransparencySetting.defaultValue)
                        .help("Reset transparency to the default (\(Int(PopoverTransparencySetting.defaultValue))%)")
                        .accessibilityHint("Restores transparency to \(Int(PopoverTransparencySetting.defaultValue)) percent")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Transparency presets and reset")

                    Text("Adjusts the ultra-thin material overlay live. The range is capped to keep balances and status text legible on busy desktops.")
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Spacing.xxs)
            }

            Section("Display") {
                Picker("Appearance", selection: Binding(
                    get: { appearanceMode },
                    set: { appearanceModeRaw = $0.rawValue }
                )) {
                    ForEach(AppAppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityValue(appearanceMode.title)

                Picker("Contrast", selection: Binding(
                    get: { contrastPreference },
                    set: { contrastRaw = $0.rawValue }
                )) {
                    ForEach(AppContrastPreference.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityValue(contrastPreference.title)

                Picker("Decorative Effects", selection: Binding(
                    get: { decorativePreference },
                    set: { decorativeRaw = $0.rawValue }
                )) {
                    ForEach(DecorativeEffectsPreference.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityValue(decorativePreference.title)

                Picker("Density", selection: Binding(
                    get: { density },
                    set: { densityRaw = $0.rawValue }
                )) {
                    ForEach(AppDensityPreference.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityValue(density.title)

                Text("Light or Dark force VaultPeek regardless of the system setting. macOS Reduce Motion, Reduce Transparency, and Increase Contrast always take priority, and the --appearance launch flag overrides Appearance here. Density currently adjusts the preview and Appearance chrome; broader per-surface spacing is rolling out separately.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func presetButton(_ preset: PopoverTransparencySetting.Preset) -> some View {
        // The active preset is filled (prominent) and inactive ones are bordered,
        // so the current quick-pick reads as selected without relying on tint
        // alone; VoiceOver also gets the selected trait.
        if transparencySetting.matchingPreset == preset {
            Button(preset.title) { popoverTransparency = preset.value }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(preset.title) { popoverTransparency = preset.value }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

/// Privacy-safe live preview of the popover material at the current transparency.
/// Reuses the real `PopoverMaterialBackground` and surface tokens over synthetic
/// labels only — never real account names, balances, or data (AND-364).
private struct AppearancePreviewCard: View {
    let setting: PopoverTransparencySetting
    var increasedContrast = false
    var density: AppDensityPreference = .comfortable

    // Density adjusts only the preview's chrome spacing — never content.
    private var outerPadding: CGFloat { density == .compact ? Spacing.sm : Spacing.md }
    private var innerSpacing: CGFloat { density == .compact ? Spacing.xs : Spacing.sm }

    // Increased contrast strengthens the card border (a non-semantic surface
    // cue), never finance colors.
    private var strokeStyle: AnyShapeStyle {
        increasedContrast ? AnyShapeStyle(Color.primary.opacity(0.55)) : AnyShapeStyle(.separator)
    }
    private var strokeWidth: CGFloat { increasedContrast ? 1.5 : 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: innerSpacing) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Net Worth")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("$12,345")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }

                Spacer(minLength: Spacing.sm)

                Label("Synced", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.chipVertical)
                    .background(.quinary, in: Capsule())
            }

            HStack(spacing: Spacing.sm) {
                Image(systemName: "building.columns.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: Radius.control))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Sample Checking")
                        .font(.callout.weight(.medium))
                    Text("Preview only")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Spacing.sm)

                Text("$4,200.00")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
            }
            .padding(Spacing.sm)
            .glassSurface(.inset)
        }
        .padding(outerPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            PopoverMaterialBackground(transparencySetting: setting)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.panel)
                .stroke(strokeStyle, lineWidth: strokeWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Live preview of the popover at \(setting.displayPercent) percent transparency, with sample data only."
        )
    }
}

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(DetachedDashboardPreferences.keepOnTopStorageKey) private var keepDashboardOnTop = false
    @State private var isShowingResetConfirmation = false
    @State private var isShowingLocalAIProbeDetails = false
    @State private var resetResultMessage: String?
    @State private var resetErrorMessage: String?

    var body: some View {
        @Bindable var state = appState

        Form {
            Section {
                Picker("Menu bar shows", selection: $state.menuBarSummaryMode) {
                    ForEach(MenuBarSummaryMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                // The icon style changes only the healthy/default glyph; degraded
                // states keep their distinct glyph ladder. Works with Icon only.
                Picker("Menu bar icon", selection: $state.menuBarIconStyle) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Label(style.displayName, systemImage: style.healthySymbolName).tag(style)
                    }
                }

                Picker("Balance format", selection: $state.balanceFormat) {
                    Text("$12,450.32").tag(CurrencyFormat.full)
                    Text("$12.4K").tag(CurrencyFormat.abbreviated)
                    Text("$12,450").tag(CurrencyFormat.compact)
                }
                .disabled(appState.menuBarSummaryMode == .creditUtilization || appState.menuBarSummaryMode == .iconOnly)

                Picker("Refresh interval", selection: $state.refreshInterval) {
                    Text("5 minutes").tag(TimeInterval(5 * 60))
                    Text("15 minutes").tag(TimeInterval(15 * 60))
                    Text("30 minutes").tag(TimeInterval(30 * 60))
                    Text("1 hour").tag(TimeInterval(60 * 60))
                }

                LabeledContent("Credit warning") {
                    HStack(spacing: Spacing.xs) {
                        TextField(
                            "Credit warning threshold",
                            value: $state.creditUtilizationThreshold,
                            format: .number.precision(.fractionLength(0))
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Credit warning threshold")

                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }
                .help("Credit cards above this utilization threshold show warning colors")

                Toggle("Launch at login", isOn: $state.launchAtLogin)

                // AND-384: pop the dashboard out of the menu bar into a
                // floating desktop window the user can drag anywhere and that
                // survives app-switches. Bound to AppState (single source of
                // truth, persisted to the dashboard.detached key), so toggling
                // here opens/closes the floating window and stays in sync with
                // the in-dashboard pin/dock control.
                Toggle("Keep dashboard in a floating window", isOn: $state.isDashboardDetached)
                Text("Detaches the dashboard from the menu bar into a movable desktop window that stays open when you switch apps. Click the menu bar item to bring it back to the front; dock it again from the window or this toggle.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)

                // AND-384 glance mode: when on, the floating window floats above
                // other apps on every Space and does not steal focus — the
                // original "monitor at a glance while you work" behavior — as an
                // explicit opt-in rather than the default.
                Toggle("Keep the floating window on top", isOn: $keepDashboardOnTop)
                    .disabled(!state.isDashboardDetached)
                Text("Floats the window above other windows on every Space without taking focus from the app you're working in. Off (default): it behaves like a normal window — one Space, normal order, and visible in Mission Control and the Dock.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Local AI") {
                Toggle("Enable Local AI", isOn: $state.localAIEnabled)

                LabeledContent("Model") {
                    TextField("llama3.2", text: $state.localAIModelName)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .disabled(!appState.localAIEnabled)
                }

                LabeledContent("Availability") {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: LocalAIAvailabilityPresentation
                            .iconName(for: appState.localAIAvailability.state))
                            .foregroundStyle(localAIAvailabilityTint)
                            .accessibilityHidden(true)
                        Text(LocalAIAvailabilityPresentation.settingsLabel(for: appState.localAIAvailability))
                            .font(.body.weight(.medium))
                    }
                }
                .accessibilityElement(children: .combine)

                LabeledContent("Runtime") {
                    VStack(alignment: .trailing, spacing: Spacing.xxs) {
                        Text(appState.localAIAvailability.runtimeName ?? "None configured")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        if let cause = LocalAIAvailabilityPresentation.causeLabel(for: appState.localAIAvailability) {
                            Text(cause)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(localAIAvailabilityTint)
                                .lineLimit(1)
                        }
                    }
                }

                localAIRemediationControls

                Text(appState.localAIAvailability.detail)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)

                if let probeErrorText = appState.localAIAvailability.probeErrorText, !probeErrorText.isEmpty {
                    Button(isShowingLocalAIProbeDetails ? "Hide Probe Error" : "View Probe Error") {
                        isShowingLocalAIProbeDetails.toggle()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Show the exact Ollama probe error captured during the local availability check.")

                    if isShowingLocalAIProbeDetails {
                        Text(probeErrorText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text(
                    "VaultPeek does not send transaction data to cloud AI services. Local insight summaries are derived from local accounts, transactions, and recurring detections; raw Plaid transaction categories remain unchanged."
                )
                .detailText()
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Local data") {
                LabeledContent("Storage path") {
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        Text(appState.activeStorageDirectoryDisplayText)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)

                        Text(storageDetailText)
                            .detailText()
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }

                LocalTrustReceiptView(receipt: localTrustReceipt)

                HStack(alignment: .center, spacing: Spacing.sm) {
                    Button {
                        revealStorageDirectory()
                    } label: {
                        Label("Open Folder", systemImage: "folder")
                    }
                    .controlSize(.small)

                    Button {
                        copyStoragePath()
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)

                    Button {
                        isShowingResetConfirmation = true
                    } label: {
                        Label("Reset Local Data", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .alert("Reset Local Data?", isPresented: $isShowingResetConfirmation) {
            Button("Reset Local Data", role: .destructive) {
                Task { await resetLocalData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Deletes the SQLite database, account and transaction caches, stored Plaid access tokens, sync cursors, and loaded account data under \(appState.activeStorageDirectoryDisplayText). Keeps server.conf, app/server auth, Plaid dashboard Items, shell credentials, and app preferences. Restart the VaultPeek companion server after resetting."
            )
        }
        .alert("Local Data Reset", isPresented: Binding(
            get: { resetResultMessage != nil },
            set: { if !$0 { resetResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resetResultMessage ?? "")
        }
        .alert("Reset Failed", isPresented: Binding(
            get: { resetErrorMessage != nil },
            set: { if !$0 { resetErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resetErrorMessage ?? "")
        }
    }

    private func revealStorageDirectory() {
        let url = appState.activeStorageDirectoryURL
        try? LocalDataStore.prepareStorageDirectory(at: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyStoragePath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.activeStorageDirectoryURL.path, forType: .string)
    }

    private func resetLocalData() async {
        do {
            let result = try await appState.resetLocalData()
            resetResultMessage = LocalDataResetPresentation.successMessage(for: result)
        } catch {
            resetErrorMessage = error.localizedDescription
        }
    }

    private var storageDetailText: String {
        LocalDataResetPresentation.storageDetail(
            serverStoragePath: appState.serverStoragePath,
            defaultResolvedDisplayPath: appState.localStorageResolvedDisplayPathText
        )
    }

    private var localTrustReceipt: LocalTrustReceipt {
        LocalTrustReceipt.settingsReceipt(storagePath: appState.activeStorageDirectoryDisplayText)
    }

    private var localAIAvailabilityTint: Color {
        color(for: LocalAIAvailabilityPresentation.tone(for: appState.localAIAvailability.state))
    }

    @ViewBuilder
    private var localAIRemediationControls: some View {
        switch LocalAIAvailabilityPresentation.remediationCategory(for: appState.localAIAvailability) {
        case .none:
            EmptyView()
        case .checking:
            Button {
                Task { await appState.checkLocalAIAvailability() }
            } label: {
                Label(appState.isCheckingLocalAIAvailability ? "Checking…" : "Check Ollama", systemImage: appState.isCheckingLocalAIAvailability ? "hourglass" : "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.isCheckingLocalAIAvailability)
        case .disabled:
            Button {
                LocalAIRemediationActions.openInstallPage()
            } label: {
                Label("Install or Open Ollama", systemImage: "arrow.down.app")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open the Ollama download page in your browser.")
        case .noInstalledModel:
            HStack(spacing: Spacing.sm) {
                Button {
                    LocalAIRemediationActions.copyPullCommand(modelName: appState.localAIModelName)
                } label: {
                    Label("Copy Model Command", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .help("Copies: \(LocalAIRemediationActions.pullCommand(modelName: appState.localAIModelName))")

                retryLocalAIButton

                installOllamaButton
            }
            .controlSize(.small)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Local AI remediation actions")
        case .runtimeUnavailable:
            HStack(spacing: Spacing.sm) {
                retryLocalAIButton
                    .buttonStyle(.borderedProminent)

                installOllamaButton

                Button {
                    LocalAIRemediationActions.copyStartCommand()
                } label: {
                    Label("Copy ollama serve", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
                .help("Copies: \(LocalAIRemediationActions.startCommand)")
            }
            .controlSize(.small)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Local AI remediation actions")
        case .unsupportedConfiguration:
            HStack(spacing: Spacing.sm) {
                installOllamaButton

                Button {
                    LocalAIRemediationActions.copyStartCommand()
                } label: {
                    Label("Copy ollama serve", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
                .help("Copies: \(LocalAIRemediationActions.startCommand)")
            }
            .controlSize(.small)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Local AI remediation actions")
        case .modelError:
            HStack(spacing: Spacing.sm) {
                retryLocalAIButton
                    .buttonStyle(.borderedProminent)

                installOllamaButton

                Button {
                    LocalAIRemediationActions.copyStartCommand()
                } label: {
                    Label("Copy ollama serve", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
                .help("Copies: \(LocalAIRemediationActions.startCommand)")
            }
            .controlSize(.small)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Local AI remediation actions")
        }
    }

    private var retryLocalAIButton: some View {
        Button {
            Task { await appState.checkLocalAIAvailability() }
        } label: {
            Label(
                appState.isCheckingLocalAIAvailability ? "Checking…" : "Retry",
                systemImage: "arrow.clockwise"
            )
        }
        .disabled(!appState.localAIEnabled || appState.isCheckingLocalAIAvailability)
        .help("Probe the local Ollama runtime again without sending Plaid credentials, account IDs, or transaction IDs.")
    }

    private var installOllamaButton: some View {
        Button {
            LocalAIRemediationActions.openInstallPage()
        } label: {
            Label("Install or Open Ollama", systemImage: "arrow.down.app")
        }
        .buttonStyle(.bordered)
        .help("Open the Ollama download page in your browser.")
    }

    private func color(for tone: SettingsStatusTone) -> Color {
        switch tone {
        case .positive: SemanticColors.positive
        case .warning: SemanticColors.warning
        case .secondary: .secondary
        }
    }
}

private struct LocalTrustReceiptView: View {
    let receipt: LocalTrustReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(receipt.title)
                    .font(.headline)

                Text(receipt.subtitle)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(receipt.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Image(systemName: row.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(row.title)
                                .font(.caption.weight(.semibold))
                            Text(row.detail)
                                .detailText()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.title). \(row.detail)")
                }
            }

            Text(receipt.footer)
                .detailText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AccountSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var isShowingAccountSetup = false
    @State private var pendingRemoval: PendingAccountRemoval?

    private var emptyPresentation: SecondaryContentUnavailableState {
        SecondaryContentUnavailableState.accounts(
            isDemoMode: appState.isDemoMode,
            isInitialLoad: appState.loadState(for: .accounts).isInitialLoad,
            serverConnected: appState.serverConnected,
            linkedItemCount: appState.statusItemCount
        )
    }

    var body: some View {
        Group {
            if appState.accounts.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    AttentionQueueView(
                        title: "Attention",
                        showsHealthyRow: false,
                        onAddAccount: handleAddAccount
                    )
                    .environment(appState)
                    .padding([.horizontal, .top], Spacing.md)

                    SecondaryUnavailableView(presentation: emptyPresentation) {
                        performEmptyAction(emptyPresentation.action)
                    }
                }
            } else {
                Form {
                    AttentionQueueView(
                        title: "Attention",
                        showsHealthyRow: false,
                        onAddAccount: handleAddAccount
                    )
                    .environment(appState)

                    ForEach(accountGroups) { group in
                        Section {
                            groupHeaderRow(for: group)

                            ForEach(group.accounts) { account in
                                accountRow(for: account)
                            }
                        }
                    }

                    Section {
                        HStack {
                            Spacer()
                            Button("Add Account") {
                                handleAddAccount()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .sheet(isPresented: $isShowingAccountSetup) {
            SetupView {
                isShowingAccountSetup = false
            }
            .environment(appState)
        }
        .onChange(of: appState.isSetupComplete) { _, isComplete in
            if isComplete {
                isShowingAccountSetup = false
            }
        }
        .alert(item: $pendingRemoval) { removal in
            Alert(
                title: Text("Remove \(removal.institutionName)?"),
                message: Text(
                    "This removes \(removal.accountCount) linked account\(removal.accountCount == 1 ? "" : "s") from VaultPeek and clears matching cached transactions from this Mac. It does not delete the institution from Plaid's dashboard."
                ),
                primaryButton: .destructive(Text("Remove")) {
                    Task { await appState.removeAccount(itemId: removal.itemId) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func groupHeaderRow(for group: AccountItemGroup) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(group.institutionName)
                    .font(.headline)

                HStack(spacing: Spacing.xs) {
                    Image(systemName: group.connection.iconName)
                        .foregroundStyle(color(for: group.connection.level))
                    Text(group.connection.signalLabel)
                        .foregroundStyle(color(for: group.connection.level))
                    Text("\u{00B7}")
                        .foregroundStyle(.tertiary)
                    Text("\(group.accounts.count) account\(group.accounts.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    if let itemSyncLabel = group.connection.itemSyncLabel {
                        Text("\u{00B7}")
                            .foregroundStyle(.tertiary)
                        Text(itemSyncLabel)
                            .foregroundStyle(.secondary)
                    }
                }
                .detailText()

                if let recoveryDetailLabel = group.connection.recoveryDetailLabel {
                    Text(recoveryDetailLabel)
                        .detailText()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(groupAccessibilityLabel(for: group))

            Spacer()

            if group.connection.showsRecoveryActions,
               let recoveryActionTitle = group.connection.recoveryActionTitle
            {
                Button {
                    performRecoveryAction(for: group)
                } label: {
                    Label(
                        recoveryActionTitle,
                        systemImage: group.connection.level == .stale ? "arrow.clockwise" : "link.badge.plus"
                    )
                }
                .buttonStyle(.bordered)
            }

            Button(role: .destructive) {
                pendingRemoval = PendingAccountRemoval(
                    itemId: group.id,
                    institutionName: group.institutionName,
                    accountCount: group.accounts.count
                )
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Remove \(group.institutionName)")
        }
        .padding(.vertical, Spacing.xs)
    }

    private func accountRow(for account: AccountDTO) -> some View {
        HStack {
            Image(systemName: AccountPresentation.iconName(for: account))
                .foregroundStyle(accountIconTint(for: account))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(account.name)
                Text(account.type.rawValue.capitalized)
                    .detailText()
            }

            Spacer()

            Text(balanceText(for: account))
                .monospacedDigit()
                .foregroundStyle(balanceTint(for: account))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accountAccessibilityLabel(for: account))
    }

    private func handleAddAccount() {
        isShowingAccountSetup = true
    }

    private func performEmptyAction(_ action: SecondaryContentUnavailableAction) {
        switch action {
        case .checkServer:
            Task { await appState.checkServerConnection() }
        case .addAccount:
            handleAddAccount()
        case .refreshAccounts:
            Task { await appState.refreshAccounts() }
        case .syncTransactions:
            Task { await appState.syncTransactions() }
        case .refresh:
            Task { await appState.refreshDashboard() }
        case .clearFilters, .showWiderPeriod:
            break
        }
    }

    private var accountGroups: [AccountItemGroup] {
        Dictionary(grouping: appState.accounts, by: \.itemId)
            .map { itemId, accounts in
                let status = appState.itemStatuses.first(where: { $0.id == itemId })
                let institutionName = accounts.compactMap(\.institutionName).first
                    ?? status?.institutionName
                    ?? "Plaid item"
                return AccountItemGroup(
                    id: itemId,
                    institutionName: institutionName,
                    connection: AccountConnectionPresentation.evaluate(
                        isDemoMode: appState.usesDemoConnectionPresentation,
                        serverConnected: appState.serverConnected,
                        isSyncStale: appState.isSyncStale,
                        statusSyncText: appState.statusSyncText,
                        itemStatus: status?.status ?? .connected,
                        institutionName: institutionName,
                        itemLastSyncRelative: status?.lastSync.map(Formatters.relativeDate)
                    ),
                    accounts: accounts.sorted { $0.name < $1.name }
                )
            }
            .sorted { $0.institutionName < $1.institutionName }
    }

    private func performRecoveryAction(for group: AccountItemGroup) {
        switch group.connection.level {
        case .stale:
            Task { await appState.refreshDashboard() }
        case .loginRequired, .error:
            Task { await appState.reconnectItem(itemId: group.id) }
        case .demo, .offline, .healthy, .unknown:
            break
        }
    }

    private func color(for level: AccountConnectionLevel) -> Color {
        switch level {
        case .healthy, .demo:
            SemanticColors.positive
        case .stale, .loginRequired, .unknown:
            SemanticColors.warning
        case .error, .offline:
            SemanticColors.negative
        }
    }

    private func accountIconTint(for account: AccountDTO) -> Color {
        switch account.type {
        case .credit, .loan:
            SemanticColors.creditDebt
        case .investment:
            SemanticColors.sparkline
        case .depository:
            SemanticColors.available
        case .other:
            .secondary
        }
    }

    private func balanceText(for account: AccountDTO) -> String {
        Formatters.currency(AccountPresentation.displayBalance(for: account), format: .compact)
    }

    private func balanceTint(for account: AccountDTO) -> Color {
        AccountPresentation.isDebt(account) ? SemanticColors.creditDebt : .secondary
    }

    private func groupAccessibilityLabel(for group: AccountItemGroup) -> String {
        var parts = [
            group.institutionName,
            group.connection.signalLabel,
            "\(group.accounts.count) account\(group.accounts.count == 1 ? "" : "s")",
        ]
        if let itemSyncLabel = group.connection.itemSyncLabel {
            parts.append(itemSyncLabel)
        }
        if let recoveryDetailLabel = group.connection.recoveryDetailLabel {
            parts.append(recoveryDetailLabel)
        }
        return parts.joined(separator: ", ")
    }

    private func accountAccessibilityLabel(for account: AccountDTO) -> String {
        "\(account.name), \(account.type.rawValue.capitalized), \(balanceText(for: account))"
    }
}

private struct AccountItemGroup: Identifiable {
    let id: String
    let institutionName: String
    let connection: AccountConnectionPresentation
    let accounts: [AccountDTO]
}

private struct PendingAccountRemoval: Identifiable {
    let itemId: String
    let institutionName: String
    let accountCount: Int

    var id: String {
        itemId
    }
}

struct NotificationSettingsView: View {
    @Environment(AppState.self) private var appState

    private var permissionPresentation: NotificationPermissionPresentation {
        appState.notificationPermissionPresentation
    }

    private var areNotificationControlsDisabled: Bool {
        !appState.notificationsEnabled || permissionPresentation.shouldDisableNotifications
    }

    var body: some View {
        @Bindable var state = appState

        Form {
            Section {
                permissionStatusRow

                Toggle("Enable notifications", isOn: $state.notificationsEnabled)
                    .onChange(of: appState.notificationsEnabled) { _, enabled in
                        if enabled {
                            Task {
                                let granted = await appState.requestNotificationPermission()
                                await refreshPermissionStatus()
                                guard granted else {
                                    return
                                }
                            }
                        } else {
                            Task { await refreshPermissionStatus() }
                        }
                    }
                    .disabled(permissionPresentation.isNotificationToggleDisabled)

                Text("Alerts are evaluated from local cached VaultPeek data. Lock-screen copy avoids account names, merchants, exact balances, and transaction amounts.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Transaction alerts") {
                Toggle("Large transactions", isOn: $state.notifyLargeTransaction)
                    .disabled(areNotificationControlsDisabled)

                LabeledContent("Large transaction threshold") {
                    HStack(spacing: Spacing.xs) {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField(
                            "Large transaction threshold",
                            value: $state.largeTransactionThreshold,
                            format: .number.precision(.fractionLength(0))
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Large transaction threshold in dollars")
                    }
                }
                .disabled(areNotificationControlsDisabled || !appState.notifyLargeTransaction)

                if !areNotificationControlsDisabled,
                   appState.notifyLargeTransaction,
                   appState.largeTransactionThreshold <= 0
                {
                    InlineSettingsNotice(
                        text: "A $0 threshold sends an alert for every outgoing transaction.",
                        icon: "bell.badge",
                        tint: SemanticColors.warning
                    )
                }

                Toggle("Low balance warning", isOn: $state.notifyLowBalance)
                    .disabled(areNotificationControlsDisabled)

                LabeledContent("Low balance threshold") {
                    HStack(spacing: Spacing.xs) {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField(
                            "Low balance threshold",
                            value: $state.lowBalanceThreshold,
                            format: .number.precision(.fractionLength(0))
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Low balance threshold in dollars")
                    }
                }
                .disabled(areNotificationControlsDisabled || !appState.notifyLowBalance)
            }

            Section("Credit alerts") {
                Toggle("High utilization", isOn: $state.notifyHighUtilization)
                    .disabled(areNotificationControlsDisabled)

                Text(
                    "Uses credit warning threshold (\(Formatters.percent(appState.creditUtilizationThreshold, decimals: 0)))"
                )
                .detailText()
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Recurring alerts") {
                Toggle("New recurring charge detected", isOn: $state.notifyRecurringChargeDetected)
                    .disabled(areNotificationControlsDisabled)

                Toggle("Recurring charge changed", isOn: $state.notifyRecurringChargeChanged)
                    .disabled(areNotificationControlsDisabled)

                Toggle("Recurring charge due soon", isOn: $state.notifyRecurringChargeDueSoon)
                    .disabled(areNotificationControlsDisabled)

                Text("Due-soon alerts use inferred recurring patterns from synced transaction history and the default 3-day window.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Connection alerts") {
                Toggle("Broken connection or stale sync", isOn: $state.notifyBrokenConnection)
                    .disabled(areNotificationControlsDisabled)

                Text("Alerts point you back to VaultPeek when a linked institution needs login, reports a sync error, or local data has gone stale.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .task {
            await refreshPermissionStatus()
        }
    }

    private var permissionStatusRow: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: permissionIcon)
                .foregroundStyle(permissionTint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack {
                    Text("macOS permission")
                    Spacer()
                    Text(permissionLabel)
                        .foregroundStyle(permissionTint)
                        .font(.callout.weight(.semibold))
                }

                Text(permissionDetail)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)

                if let action = permissionPresentation.recoveryAction {
                    permissionRecoveryAction(action)
                        .padding(.top, Spacing.xs)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("macOS notification permission: \(permissionLabel)")
        .accessibilityHint(permissionDetail)
    }

    private func refreshPermissionStatus() async {
        _ = await appState.notificationPermissionStatus()
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }

    private var permissionLabel: String {
        permissionPresentation.label
    }

    private var permissionDetail: String {
        permissionPresentation.detail
    }

    private var permissionIcon: String {
        permissionPresentation.iconName
    }

    private var permissionTint: Color {
        switch permissionPresentation.tone {
        case .positive:
            SemanticColors.positive
        case .warning:
            SemanticColors.warning
        case .secondary:
            .secondary
        }
    }

    @ViewBuilder
    private func permissionRecoveryAction(_ action: NotificationPermissionRecoveryAction) -> some View {
        if permissionPresentation.isRecoveryActionInteractive {
            Button {
                performPermissionRecoveryAction(action)
            } label: {
                Label(
                    permissionPresentation.recoveryActionTitle ?? "Recover Notifications",
                    systemImage: permissionPresentation.recoveryActionIconName ?? "bell.badge"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint(permissionActionAccessibilityHint(for: action))
        } else {
            Label(
                permissionPresentation.recoveryActionTitle ?? "Recover Notifications",
                systemImage: permissionPresentation.recoveryActionIconName ?? "bell.badge"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(permissionTint)
            .accessibilityLabel(permissionPresentation.recoveryActionTitle ?? "Recover Notifications")
            .accessibilityHint(permissionPresentation.detail)
        }
    }

    private func performPermissionRecoveryAction(_ action: NotificationPermissionRecoveryAction) {
        switch action {
        case .requestPermission:
            Task {
                let granted = await appState.requestNotificationPermission()
                appState.notificationsEnabled = granted
                await refreshPermissionStatus()
            }
        case .openSystemSettings:
            openNotificationSettings()
        case .checkAgain:
            Task { await refreshPermissionStatus() }
        case .runBundledApp:
            break
        }
    }

    private func permissionActionAccessibilityHint(for action: NotificationPermissionRecoveryAction) -> Text {
        switch action {
        case .requestPermission:
            Text("Requests macOS notification permission for VaultPeek.")
        case .openSystemSettings:
            Text("Opens macOS Notification settings for VaultPeek.")
        case .checkAgain:
            Text("Checks the current macOS notification permission again.")
        case .runBundledApp:
            Text(permissionPresentation.detail)
        }
    }
}

private struct InlineSettingsNotice: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)

            Text(text)
                .detailText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AboutView: View {
    let updater: SPUUpdater

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: Spacing.md) {
                    Image(nsImage: appIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(PlaidBarConstants.appName)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Version \(PlaidBarConstants.appVersion)")
                            .foregroundStyle(.secondary)

                        Text("Your bank accounts, credit cards, and spending -- always one click away.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
                .padding(.vertical, Spacing.xs)
            }

            Section("Support") {
                supportLink(
                    "Troubleshooting",
                    systemImage: "wrench.and.screwdriver",
                    url: "https://github.com/ftchvs/PlaidBar/blob/main/docs/troubleshooting.md",
                    detail: "Setup, server, Plaid Link, notifications, and screenshot fixes."
                )

                supportLink(
                    "Privacy",
                    systemImage: "lock.shield",
                    url: "https://github.com/ftchvs/PlaidBar/blob/main/docs/privacy.md",
                    detail: "What stays local, what calls Plaid, and what not to share."
                )

                supportLink(
                    "Security",
                    systemImage: "exclamationmark.shield",
                    url: "https://github.com/ftchvs/PlaidBar/blob/main/SECURITY.md",
                    detail: "Private reporting path for token, credential, or data exposure."
                )
            }

            Section("Project") {
                supportLink(
                    "GitHub Repository",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    url: "https://github.com/ftchvs/PlaidBar",
                    detail: "Source, issues, and releases (private repository)."
                )

                supportLink(
                    "1.0 Roadmap",
                    systemImage: "map",
                    url: "https://github.com/ftchvs/PlaidBar/blob/main/docs/v1.0-roadmap.md",
                    detail: "Product, design, system, security, and release plan."
                )

                supportLink(
                    "Release Notes",
                    systemImage: "doc.text",
                    url: "https://github.com/ftchvs/PlaidBar/blob/main/docs/release-notes.md",
                    detail: "Curated release summary for current and upcoming versions."
                )
            }

            Section {
                HStack {
                    Button {
                        updater.checkForUpdates()
                    } label: {
                        Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Spacer()

                    Text("© 2026 Felipe Tavares Chaves · Proprietary")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @MainActor
    private var appIconImage: NSImage {
        NSImage(named: NSImage.applicationIconName) ?? NSApp.applicationIconImage
    }

    @ViewBuilder
    private func supportLink(
        _ title: String,
        systemImage: String,
        url: String,
        detail: String
    ) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: systemImage)
                        .foregroundStyle(SemanticColors.brand)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(title)
                            .foregroundStyle(.primary)
                        Text(detail)
                            .detailText()
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
