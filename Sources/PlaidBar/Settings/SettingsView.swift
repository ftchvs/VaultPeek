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

            PrivacySecuritySettingsView()
                .environment(appState)
                .tabItem {
                    Label("Privacy", systemImage: "lock.shield")
                }
                .tag(SettingsTab.privacy.rawValue)

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
    case privacy
    case about
}

struct AppearanceSettingsView: View {
    @AppStorage(PopoverTransparencySetting.storageKey) private var popoverTransparency = PopoverTransparencySetting.defaultValue
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceModeRaw = AppAppearanceMode.defaultValue.rawValue
    @AppStorage(AppContrastPreference.storageKey) private var contrastRaw = AppContrastPreference.defaultValue.rawValue
    @AppStorage(DecorativeEffectsPreference.storageKey) private var decorativeRaw = DecorativeEffectsPreference.defaultValue.rawValue
    @AppStorage(AppDensityPreference.storageKey) private var densityRaw = AppDensityPreference.defaultValue.rawValue
    @AppStorage(TextSizePreference.storageKey) private var textSizeRaw = TextSizePreference.defaultValue.rawValue
    @AppStorage(HapticFeedbackPreference.storageKey) private var hapticRaw = HapticFeedbackPreference.defaultValue.rawValue
    @Environment(\.colorSchemeContrast) private var systemContrast

    private var transparencySetting: PopoverTransparencySetting {
        PopoverTransparencySetting(value: popoverTransparency)
    }

    private var appearanceMode: AppAppearanceMode { AppAppearanceMode(rawValue: appearanceModeRaw) ?? .followSystem }
    private var contrastPreference: AppContrastPreference { AppContrastPreference(rawValue: contrastRaw) ?? .followSystem }
    private var decorativePreference: DecorativeEffectsPreference { DecorativeEffectsPreference(rawValue: decorativeRaw) ?? .followSystem }
    private var density: AppDensityPreference { AppDensityPreference(rawValue: densityRaw) ?? .comfortable }
    private var textSize: TextSizePreference { TextSizePreference(rawValue: textSizeRaw) ?? .default }
    private var hapticPreference: HapticFeedbackPreference { HapticFeedbackPreference(rawValue: hapticRaw) ?? .on }

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

            Section("Text Size") {
                // macOS does not honor the system Dynamic Type setting for
                // third-party apps, so this control is the only way to enlarge
                // VaultPeek's text. The picker writes the persisted preference;
                // the scene roots read it and set `.dynamicTypeSize` app-wide so
                // every surface scales together (AND-570).
                Picker("Text Size", selection: Binding(
                    get: { textSize },
                    set: { textSizeRaw = $0.rawValue }
                )) {
                    ForEach(TextSizePreference.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityValue(textSize.title)
                .accessibilityHint("Sets the text size for all of VaultPeek")

                // Live preview: synthetic text scaled to the selected size, so the
                // effect is visible the instant the picker changes — privacy-safe
                // (no real account data). `.dynamicTypeSize` here mirrors what the
                // scene roots apply app-wide.
                TextSizePreviewRow()
                    .dynamicTypeSize(DynamicTypeSize(textSize.forcedDynamicTypeSize))
                    .padding(.vertical, Spacing.xxs)

                Text(textSize.detail)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)

                Text("macOS ignores the system Dynamic Type setting for apps, so use this to make VaultPeek's text larger everywhere. The largest steps reflow some layouts to keep numbers legible.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Feedback") {
                // Direct-manipulation haptics (AND-576). On by default; a no-op on
                // Macs without a Force Touch haptic engine, so this only affects
                // hardware that can play feedback. Committed direct manipulations —
                // resolving/ignoring a review row, the quick Privacy Mask toggle —
                // get a small tactile confirmation. It is intentionally limited to
                // those committed gestures, never every minor state change.
                Toggle("Haptic feedback", isOn: Binding(
                    get: { hapticPreference.isEnabled },
                    set: { hapticRaw = ($0 ? HapticFeedbackPreference.on : .off).rawValue }
                ))
                .accessibilityHint("Plays a small trackpad click when you approve, ignore, or toggle directly.")

                Text("Plays a subtle Force Touch trackpad click when you directly approve, ignore, or toggle. No effect on Macs without a haptic trackpad.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func presetButton(_ preset: PopoverTransparencySetting.Preset) -> some View {
        // The active preset is filled (prominent glass) and inactive ones are
        // plain glass, so the current quick-pick reads as selected without
        // relying on tint alone; VoiceOver also gets the selected trait. The
        // transparency presets adjust the glass surface, so glass-styled buttons
        // keep the control consistent with what they tune (AND-511).
        if transparencySetting.matchingPreset == preset {
            Button(preset.title) { popoverTransparency = preset.value }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(preset.title) { popoverTransparency = preset.value }
                .buttonStyle(.glass)
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

/// Privacy-safe live preview of the in-app text size (AND-570). Synthetic labels
/// scaled by the caller's `.dynamicTypeSize` — never real account data — so the
/// user sees the effect of the Text Size picker the instant it changes. Uses a
/// semantic text style and the hero-balance modifier so the preview tracks the
/// same scaling path as the real dashboard surfaces.
private struct TextSizePreviewRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Net Worth")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("$12,345.67")
                .heroBalance()
            Text("Preview only — sample data")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Radius.control))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live preview of the selected text size, with sample data only.")
    }
}

struct PrivacySecuritySettingsView: View {
    @Environment(AppState.self) private var appState
    /// Snapshot of the live authentication capability, refreshed on appear and
    /// after any App Lock change so the toggle can disable + explain itself when
    /// biometrics / device authentication are unavailable.
    @State private var capability: AppLockCapability = .available(biometry: .none)

    private var control: AppLockSettingsControl {
        AppLockSettingsControl.resolve(
            capability: capability,
            isEnabled: appState.appLockPreferences.appLockEnabled
        )
    }

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Privacy Mask") {
                Toggle("Hide balances and amounts", isOn: $state.appLockPreferences.privacyMaskEnabled)

                Text("Masks balances, amounts, and the menu bar value behind dots without requiring authentication. Use it for quick over-the-shoulder privacy; flip it off to reveal again.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("App Lock") {
                Toggle("Require authentication", isOn: Binding(
                    get: { appState.appLockPreferences.appLockEnabled },
                    set: { newValue in
                        appState.setAppLockEnabled(newValue)
                        capability = appState.appLockAuthenticationCapability()
                    }
                ))
                .disabled(!control.isToggleEnabled)

                Text(control.explanation)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Lock on launch", isOn: $state.appLockPreferences.lockOnLaunch)
                    .disabled(!appState.appLockPreferences.appLockEnabled)

                Toggle("Lock when it loses focus", isOn: $state.appLockPreferences.lockWhenBackgrounded)
                    .disabled(!appState.appLockPreferences.appLockEnabled)

                Text("Re-lock automatically — on launch, and whenever VaultPeek loses focus (you click away or the popover closes). Turn either off to stay unlocked across those transitions.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Pause refresh while locked", isOn: $state.appLockPreferences.pauseRefreshWhileLocked)
                    .disabled(!appState.appLockPreferences.appLockEnabled)

                Text("When locked, VaultPeek stops fetching new balances and transactions until you authenticate. Leave off to keep cached data current behind the lock.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Notifications while private") {
                // VaultPeek's notification bodies are always generic (no merchant,
                // account, or amount), so the only honest choice is whether alerts
                // are suppressed while locked. The binding maps to the underlying
                // `notificationPrivacyMode` so every persisted raw value stays
                // decodable.
                Toggle("Suppress alerts while locked", isOn: $state.appLockPreferences.notificationPrivacyMode.suppressesNotificationsWhileLocked)
                    .disabled(!appState.appLockPreferences.appLockEnabled)

                Text(appState.appLockPreferences.notificationPrivacyMode.detail)
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            capability = appState.appLockAuthenticationCapability()
        }
    }
}

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(DetachedDashboardPreferences.keepOnTopStorageKey) private var keepDashboardOnTop = false
    @State private var isShowingResetConfirmation = false
    @State private var isShowingLocalAIProbeDetails = false
    @State private var resetResultMessage: String?
    @State private var resetErrorMessage: String?
    @State private var exportErrorMessage: String?

    var body: some View {
        @Bindable var state = appState
        // The detached-dashboard intent moved onto the per-window navigation model
        // (AND-600); bind directly off it since `appState.navigationModel` is a
        // `let` (a `$state.navigationModel.…` chain can't form a writable binding
        // through a `let`).
        @Bindable var nav = appState.navigationModel

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
                        // The Vault style has no SF Symbol; show its code-drawn
                        // template glyph so the picker row matches the menu bar.
                        if style.usesCustomGlyph {
                            Label {
                                Text(style.displayName)
                            } icon: {
                                Image(nsImage: VaultMenuBarGlyph.image)
                            }
                            .tag(style)
                        } else {
                            Label(style.displayName, systemImage: style.healthySymbolName).tag(style)
                        }
                    }
                }
                .disabled(appState.menuBarShowSignalMeter)

                // AND-485: replace the healthy glyph with a live signal meter
                // (highest credit-card utilization). Only the healthy state is
                // affected; error/login/offline states keep their distinct glyph,
                // so a problem is never hidden behind a meter.
                Toggle("Show live signal meter", isOn: $state.menuBarShowSignalMeter)
                Text("Replaces the menu bar icon with a small meter of your highest credit-card utilization. Warning and error states still show their own icon.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Balance format", selection: $state.balanceFormat) {
                    Text("$12,450.32").tag(CurrencyFormat.full)
                    Text("$12.4K").tag(CurrencyFormat.abbreviated)
                    Text("$12,450").tag(CurrencyFormat.compact)
                }
                .disabled(
                    appState.menuBarSummaryMode == .creditUtilization
                        || appState.menuBarSummaryMode == .highestUtilization
                        || appState.menuBarSummaryMode == .iconOnly
                )

                Picker("Refresh", selection: $state.automaticRefreshPolicy) {
                    ForEach(AutomaticRefreshPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .accessibilityHint("How often VaultPeek refreshes from Plaid automatically")

                Text("VaultPeek refreshes from Plaid automatically at most twice a day, showing cached data instantly the rest of the time. Choose Manual only to refresh solely with the refresh button. The refresh button updates on demand anytime.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)

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

                // AND-487: a global hotkey that summons VaultPeek from any app.
                // The chord is fixed for v1; only the on/off switch is exposed.
                Toggle("Summon with \(SummonHotkeyConfiguration.summonDefault.displayString)", isOn: $state.summonHotkeyEnabled)
                Text("Press \(SummonHotkeyConfiguration.summonDefault.displayString) from any app to bring VaultPeek to the front.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)

                // AND-384: pop the dashboard out of the menu bar into a
                // floating desktop window the user can drag anywhere and that
                // survives app-switches. Bound to the per-window navigation model
                // (AND-600; persisted to the dashboard.detached key), so toggling
                // here opens/closes the floating window and stays in sync with
                // the in-dashboard pin/dock control.
                Toggle("Keep dashboard in a floating window", isOn: $nav.isDashboardDetached)
                Text("Detaches the dashboard from the menu bar into a movable desktop window that stays open when you switch apps. Click the menu bar item to bring it back to the front; dock it again from the window or this toggle.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)

                // AND-384 glance mode: when on, the floating window floats above
                // other apps on every Space and does not steal focus — the
                // original "monitor at a glance while you work" behavior — as an
                // explicit opt-in rather than the default.
                Toggle("Keep the floating window on top", isOn: $keepDashboardOnTop)
                    .disabled(!state.navigationModel.isDashboardDetached)
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

                LabeledContent("Preferred tier") {
                    VStack(alignment: .trailing, spacing: Spacing.xxs) {
                        Text(appState.localAIPreferredTier.displayName)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        if let cause = appState.foundationModelsAvailability.causeLabel {
                            Text(cause)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .help("Highest-preference on-device AI tier. Apple Intelligence (Foundation Models) is used when available; otherwise VaultPeek uses the existing local tiers.")

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

            Section("Export & Backup") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Export a portable copy of your accounts, transactions, and balance history. VaultPeek never uploads these files — they are written only to the folder you choose. Pick a local folder to keep them on this Mac; a synced location (iCloud Drive, Dropbox, a network share) will copy them off-device.")
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .center, spacing: Spacing.sm) {
                        Menu {
                            Button("Export CSV…") { exportCSV() }
                            Button("Export JSON…") { exportJSON() }
                        } label: {
                            Label("Export…", systemImage: "square.and.arrow.up")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .disabled(isExportDisabled)
                    }

                    if appState.shouldMaskFinancialValues {
                        Label(
                            appState.isContentLocked
                                ? "Export is disabled while App Lock is locked, so real balances, accounts, and transactions are never written to disk. Unlock VaultPeek to export."
                                : "Export is disabled while Privacy Mask is on, so real balances are never written to disk. Turn off Privacy Mask to export.",
                            systemImage: appState.isContentLocked ? "lock" : "eye.slash"
                        )
                        .detailText()
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    LabeledContent("Backup file") {
                        Text(documentedBackupPathText)
                            .font(.system(.caption, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Where your data lives") {
                LocalTrustReceiptView(receipt: whereYourDataLivesReceipt)
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
        .alert("Export Failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    private func revealStorageDirectory() {
        let url = appState.activeStorageDirectoryURL
        try? LocalDataStore.prepareStorageDirectory(at: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Export & Backup (AND-492)

    private var isExportDisabled: Bool {
        // Gate on the effective mask state, not just the manual Privacy Mask
        // toggle: `shouldMaskFinancialValues` is also true while App Lock is
        // active. Settings is a separate scene reachable from the status-item
        // menu while the dashboard is locked, so without this a locked session
        // (Privacy Mask off) could still write the full accounts/transactions/
        // balances export to disk, bypassing App Lock (Codex P1).
        appState.shouldMaskFinancialValues
    }

    /// Documented backup file path, e.g. `~/.vaultpeek/plaidbar-sandbox.sqlite`.
    /// The SQLite store is per-environment; fall back to the generic filename
    /// when no environment is connected (demo mode).
    private var documentedBackupPathText: String {
        let directory = appState.activeStorageDirectoryDisplayText
        let filename: String
        if let environment = appState.serverEnvironment {
            filename = LocalDataStore.sqliteFilename(for: environment)
        } else {
            filename = "plaidbar.sqlite"
        }
        let trimmed = directory.hasSuffix("/") ? directory : directory + "/"
        return trimmed + filename
    }

    private func exportCSV() {
        guard !isExportDisabled else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose a folder for the exported CSV files."
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        let documents: [(name: String, contents: String)] = [
            ("accounts.csv", DataExportBuilder.accountsCSV(appState.accounts)),
            ("transactions.csv", DataExportBuilder.transactionsCSV(appState.transactions)),
            ("balance-history.csv", DataExportBuilder.balanceHistoryCSV(appState.balanceHistory)),
        ]
        // Surface write failures (unwritable/unavailable folder, full disk)
        // instead of dropping them with `try?` and leaving the user believing a
        // backup exists when one or more files were never written (Codex P2).
        do {
            for document in documents {
                let url = directory.appendingPathComponent(document.name)
                try Data(document.contents.utf8).write(to: url, options: [.atomic])
            }
        } catch {
            exportErrorMessage = "Could not write the CSV export to \(directory.path): \(error.localizedDescription)"
        }
    }

    private func exportJSON() {
        guard !isExportDisabled else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "vaultpeek-export.json"
        panel.prompt = "Export"
        panel.message = "Choose where to save the combined JSON backup."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Surface encode/write failures instead of silently dropping them, so a
        // failed JSON backup is never mistaken for a successful one (Codex P2).
        do {
            let data = try DataExportBuilder.combinedJSON(
                accounts: appState.accounts,
                transactions: appState.transactions,
                balanceHistory: appState.balanceHistory,
                exportedAt: Date(),
                environment: appState.serverEnvironment?.rawValue
            )
            try data.write(to: url, options: [.atomic])
        } catch {
            exportErrorMessage = "Could not write the JSON export to \(url.path): \(error.localizedDescription)"
        }
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

    private var whereYourDataLivesReceipt: LocalTrustReceipt {
        LocalTrustReceipt.whereYourDataLives(storagePath: appState.activeStorageDirectoryDisplayText)
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

            if let deepLink = receipt.deepLink, let url = URL(string: deepLink.urlString) {
                Link(destination: url) {
                    Label(deepLink.title, systemImage: deepLink.systemImage)
                        .font(.caption.weight(.semibold))
                }
                .controlSize(.small)
                .accessibilityLabel(deepLink.title)
            }
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

    private func performEmptyAction(_ action: RecoveryAction) {
        // Already inside Settings, so `openSettings` is a no-op; "add account"
        // opens the account-setup sheet on this surface.
        RecoveryActionDispatcher(
            appState: appState,
            openSettings: {},
            onAddAccount: handleAddAccount
        )
        .perform(action)
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

    // Draft fields for adding a new watchlist target (AND-501).
    @State private var newWatchKind: WatchlistTarget.Kind = .merchant
    @State private var newWatchMerchant: String = ""
    @State private var newWatchCategory: SpendingCategory = .shopping
    @State private var newWatchThreshold: Double = 100

    /// Categories a category-watch can actually fire on. Watchlist evaluation
    /// sums `SpendingSummary.expenseTransactions`, which excludes income and
    /// own-account transfers — so offering Income / Transfer In / Transfer Out
    /// here would let the user save a watch that can never fire (Codex P2). Keep
    /// this exclusion set in sync with `SpendingSummary.expenseTransactions`.
    private var watchableCategories: [SpendingCategory] {
        SpendingCategory.allCases.filter {
            $0 != .income && $0 != .transfer && $0 != .transferOut
        }
    }

    private var canAddWatchTarget: Bool {
        guard newWatchThreshold > 0 else { return false }
        if newWatchKind == .merchant {
            return !newWatchMerchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private func addWatchTarget() {
        let target: WatchlistTarget
        switch newWatchKind {
        case .merchant:
            target = .merchant(newWatchMerchant, threshold: newWatchThreshold)
        case .category:
            target = .category(newWatchCategory, threshold: newWatchThreshold)
        }
        appState.addWatchlistTarget(target)
        newWatchMerchant = ""
        newWatchThreshold = 100
    }

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

            watchlistsSection(state: state)

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

    // Watchlists: per-merchant / per-category month-to-date spend nudges (AND-501).
    @ViewBuilder
    private func watchlistsSection(state: AppState) -> some View {
        Section("Watchlists") {
            Toggle("Spend nudges", isOn: Binding(
                get: { appState.notifyWatchlist },
                set: { appState.notifyWatchlist = $0 }
            ))
            .disabled(areNotificationControlsDisabled)

            ForEach(appState.watchlistTargets) { target in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: watchIcon(for: target))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(target.label)
                            .lineLimit(1)
                        Text("\(target.kind.displayName) · over \(Formatters.currency(target.monthlyThreshold, format: .compact)) this month")
                            .detailText()
                            .lineLimit(1)
                    }
                    Spacer(minLength: Spacing.sm)
                    Button {
                        appState.removeWatchlistTarget(id: target.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove watchlist nudge")
                    .accessibilityLabel("Remove \(target.label) watchlist nudge")
                }
            }

            if appState.watchlistTargets.isEmpty {
                Text("Add a merchant or category and a monthly amount to get a nudge when your month-to-date spend crosses it.")
                    .detailText()
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Add row.
            Picker("Watch", selection: $newWatchKind) {
                ForEach(WatchlistTarget.Kind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .disabled(areNotificationControlsDisabled)

            if newWatchKind == .merchant {
                LabeledContent("Merchant") {
                    TextField("Merchant name", text: $newWatchMerchant)
                        .labelsHidden()
                        .frame(width: 160)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Merchant name to watch")
                }
            } else {
                LabeledContent("Category") {
                    Picker("Category", selection: $newWatchCategory) {
                        ForEach(watchableCategories, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    .accessibilityLabel("Category to watch")
                }
            }

            LabeledContent("Monthly threshold") {
                HStack(spacing: Spacing.xs) {
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField(
                        "Monthly threshold",
                        value: $newWatchThreshold,
                        format: .number.precision(.fractionLength(0))
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Monthly threshold in dollars")
                }
            }

            Button {
                addWatchTarget()
            } label: {
                Label("Add watch", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(areNotificationControlsDisabled || !canAddWatchTarget)

            Text("You've spent $X at a merchant — or in a category — this month. Glance-only nudges, not budgets.")
                .detailText()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func watchIcon(for target: WatchlistTarget) -> String {
        switch target.kind {
        case .merchant: "bell.badge"
        case .category: target.category?.iconName ?? "tag"
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
                    url: PlaidBarConstants.repositoryFileURL("docs/troubleshooting.md"),
                    detail: "Setup, server, Plaid Link, notifications, and screenshot fixes."
                )

                supportLink(
                    "Privacy",
                    systemImage: "lock.shield",
                    url: PlaidBarConstants.repositoryFileURL("docs/privacy.md"),
                    detail: "What stays local, what calls Plaid, and what not to share."
                )

                supportLink(
                    "Security",
                    systemImage: "exclamationmark.shield",
                    url: PlaidBarConstants.repositoryFileURL("SECURITY.md"),
                    detail: "Private reporting path for token, credential, or data exposure."
                )
            }

            Section("Project") {
                supportLink(
                    "GitHub Repository",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    url: PlaidBarConstants.repositoryURL,
                    detail: "Source, issues, and releases."
                )

                supportLink(
                    "Release Notes",
                    systemImage: "doc.text",
                    url: PlaidBarConstants.repositoryFileURL("docs/release-notes.md"),
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
