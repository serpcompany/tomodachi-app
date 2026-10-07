import SwiftUI
import AppKit
import TomoCore

@main
struct NotchBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Tomodachi's window is TomoAppWindow, opened by AppDelegate. This scene carries the main menu (TomoCommands):
        // its Settings… and About go to the window's pages.
        Settings { EmptyView() }
            .commands { TomoCommands() }
    }
}
