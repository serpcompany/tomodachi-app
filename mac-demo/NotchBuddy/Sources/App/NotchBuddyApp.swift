import SwiftUI
import AppKit
import TomoCore

@main
struct NotchBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        // Who sees the first run, decided before anything opens the store (#88): the main menu below reads TomoGame,
        // which hatches a Tomo when there's none, and then a new learner's first run would never show.
        TomoOnboarding.checkAtLaunch()
    }

    var body: some Scene {
        // Tomodachi's window is TomoAppWindow, opened by AppDelegate. This scene carries the main menu (TomoCommands):
        // its Settings… and About go to the window's pages.
        Settings { EmptyView() }
            .commands { TomoCommands() }
    }
}
