import AppKit
import SwiftUI
import PetasosUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let environment: AppEnvironment
    private var monitor: Any?

    init(environment: AppEnvironment) {
        self.environment = environment
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()
        popover.delegate = self
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Petasos")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "Petasos"
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Petasos menu bar")
        button.setAccessibilityRole(.button)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = !environment.systemFlags.reduceMotion
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(viewModel: environment.popoverVM)
                .environmentObject(environment.systemFlags)
        )
    }

    @objc private func handleClick(_ sender: Any?) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        installGlobalDismissMonitor()
    }

    private func installGlobalDismissMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.popover.performClose(nil) }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Petasos", action: #selector(openPopoverItem), keyEquivalent: "")
            .target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsItem), keyEquivalent: ",")
            .target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Petasos", action: #selector(quitItem), keyEquivalent: "q")
            .target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // remove so left-clicks return to popover behavior
    }

    @objc private func openPopoverItem() { togglePopover() }
    @objc private func openSettingsItem() { environment.openSettings() }
    @objc private func quitItem() { NSApp.terminate(nil) }

    // MenuBarController lives for the lifetime of the app; the global event monitor is
    // implicitly released on process exit, so we deliberately omit a deinit cleanup
    // (which would otherwise violate Swift 6 Sendable rules on non-isolated deinit).
}

extension MenuBarController: NSPopoverDelegate {
    nonisolated func popoverDidShow(_ notification: Notification) {
        Task { @MainActor in self.environment.handlePopoverDidShow() }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in self.environment.handlePopoverDidClose() }
    }
}
