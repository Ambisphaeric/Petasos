import AppKit
import SwiftUI
import PetasosCore
import PetasosHermes
import PetasosUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only — no dock icon, no App Switcher entry.
        NSApp.setActivationPolicy(.accessory)

        // Surface the macOS local network prompt at launch rather than mid
        // onboarding, where it would otherwise interrupt the health probe
        // and leave it stuck on "unhealthy" until the user clicks allow.
        Permissions.primeLocalNetworkAccess()

        let environment = AppEnvironment.bootstrap()
        self.environment = environment

        self.menuBarController = MenuBarController(environment: environment)

        // Hand-off: when there is no saved profile, walk the user through onboarding.
        if environment.profileStore.profile == nil {
            environment.openOnboarding()
        } else {
            // Re-verify in the background so the popover reflects current health.
            Task { await environment.recheck() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Re-opening (e.g. from Finder) reveals the popover instead of doing nothing silently.
        menuBarController?.togglePopover()
        return true
    }
}
