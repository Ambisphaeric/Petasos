import SwiftUI

@main
struct PetasosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The menu bar status item and popover are owned by AppDelegate.
        // We declare an empty Settings scene so @main has a valid Scene; the
        // actual settings window is presented programmatically as an NSWindow
        // so we can size and position it independently of the menu bar.
        Settings {
            EmptyView()
        }
    }
}
