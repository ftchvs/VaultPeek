import AppKit

struct StatusItemContextMenuActions {
    let showDashboard: @MainActor () -> Void
    let openInWindow: @MainActor () -> Void
    let refreshDashboard: @MainActor () -> Void
    let openSettings: @MainActor () -> Void
    let checkForUpdates: @MainActor () -> Void
    let showAbout: @MainActor () -> Void
    let dismissPopover: @MainActor () -> Void
    /// ⌥-click on the menu-bar icon toggles Privacy Mask instead of opening the
    /// popover — instant over-the-shoulder privacy without a menu.
    let togglePrivacyMask: @MainActor () -> Void
}

@MainActor
final class StatusItemContextMenuController: NSObject, NSMenuDelegate {
    private weak var statusItem: NSStatusItem?
    private weak var highlightedButton: NSStatusBarButton?
    private var localEventMonitor: Any?
    private var actions: StatusItemContextMenuActions?

    func configure(statusItem: NSStatusItem, actions: StatusItemContextMenuActions) {
        self.statusItem = statusItem
        self.actions = actions
        installLocalEventMonitorIfNeeded()
    }

    private func installLocalEventMonitorIfNeeded() {
        guard localEventMonitor == nil else { return }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            let didHandleEvent = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handleStatusItemMouseDown(event)
            }
            // Returning nil swallows the event so the status item never sees it
            // (no context menu flash, no popover toggle); returning the event lets
            // a plain left-click open the popover as usual.
            return didHandleEvent ? nil : event
        }
    }

    private func handleStatusItemMouseDown(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button, event.isInside(button: button) else {
            return false
        }

        switch event.type {
        case .rightMouseDown:
            actions?.dismissPopover()
            showMenu(from: button, with: event)
            return true
        case .leftMouseDown:
            // Only intercept the Option-modified click; a plain click falls
            // through to MenuBarExtra and opens the popover normally.
            guard event.modifierFlags.contains(.option) else { return false }
            actions?.togglePrivacyMask()
            return true
        default:
            return false
        }
    }

    private func showMenu(from button: NSStatusBarButton, with event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        menu.addActionItem("Open VaultPeek", action: #selector(showDashboard), target: self)
        menu.addActionItem("Open in Window", action: #selector(openInWindow), target: self)
        menu.addActionItem("Refresh Dashboard", action: #selector(refreshDashboard), target: self)
        menu.addItem(.separator())
        menu.addActionItem("Settings...", action: #selector(openSettings), target: self)
        menu.addActionItem("Check for Updates...", action: #selector(checkForUpdates), target: self)
        menu.addActionItem("About VaultPeek", action: #selector(showAbout), target: self)
        menu.addItem(.separator())
        menu.addActionItem("Quit VaultPeek", action: #selector(quitApplication), target: self, keyEquivalent: "q")

        highlightedButton = button
        button.isHighlighted = true
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    func menuDidClose(_ menu: NSMenu) {
        highlightedButton?.isHighlighted = false
        highlightedButton = nil
    }

    @objc private func showDashboard() {
        actions?.showDashboard()
    }

    @objc private func openInWindow() {
        actions?.openInWindow()
    }

    @objc private func refreshDashboard() {
        actions?.refreshDashboard()
    }

    @objc private func openSettings() {
        actions?.openSettings()
    }

    @objc private func checkForUpdates() {
        actions?.checkForUpdates()
    }

    @objc private func showAbout() {
        actions?.showAbout()
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}

private extension NSMenu {
    func addActionItem(
        _ title: String,
        action: Selector,
        target: AnyObject,
        keyEquivalent: String = ""
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        addItem(item)
    }
}

private extension NSEvent {
    @MainActor
    func isInside(button: NSStatusBarButton) -> Bool {
        guard window === button.window else { return false }

        let locationInButton = button.convert(locationInWindow, from: nil)
        return button.bounds.contains(locationInButton)
    }
}
