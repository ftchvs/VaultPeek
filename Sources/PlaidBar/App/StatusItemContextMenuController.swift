import AppKit

struct StatusItemContextMenuActions {
    let showDashboard: @MainActor () -> Void
    let refreshDashboard: @MainActor () -> Void
    let openSettings: @MainActor () -> Void
    let checkForUpdates: @MainActor () -> Void
    let showAbout: @MainActor () -> Void
    let dismissPopover: @MainActor () -> Void
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

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            let didHandleEvent = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handleRightMouseDown(event)
            }
            return didHandleEvent ? nil : event
        }
    }

    private func handleRightMouseDown(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button, event.isInside(button: button) else {
            return false
        }

        actions?.dismissPopover()
        showMenu(from: button, with: event)
        return true
    }

    private func showMenu(from button: NSStatusBarButton, with event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        menu.addActionItem("Open VaultPeek", action: #selector(showDashboard), target: self)
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
