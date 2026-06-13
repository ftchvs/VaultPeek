import AppKit

@MainActor
final class StatusItemContextMenuController: NSObject, NSMenuDelegate {
    private weak var statusItem: NSStatusItem?
    private weak var highlightedButton: NSStatusBarButton?
    private var localEventMonitor: Any?
    private var dismissPopover: (() -> Void)?

    func configure(statusItem: NSStatusItem, dismissPopover: @escaping () -> Void) {
        self.statusItem = statusItem
        self.dismissPopover = dismissPopover
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

        dismissPopover?()
        showMenu(from: button, with: event)
        return true
    }

    private func showMenu(from button: NSStatusBarButton, with event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let quitItem = NSMenuItem(
            title: "Quit VaultPeek",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        highlightedButton = button
        button.isHighlighted = true
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    func menuDidClose(_ menu: NSMenu) {
        highlightedButton?.isHighlighted = false
        highlightedButton = nil
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
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
