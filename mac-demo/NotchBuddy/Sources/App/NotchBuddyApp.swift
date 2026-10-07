import SwiftUI
import AppKit
import TomoCore

@main
struct NotchBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Tomodachi's window is TomoAppWindow, opened by AppDelegate. This scene only carries the menu bar's commands,
        // shown while that window is open: Settings… and About go to the window's pages.
        Settings { EmptyView() }
            .commands { TomoCommands() }
    }
}

private struct TomoCommands: Commands {
    @ObservedObject var lang = TomoLanguages.shared

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(lang.learner("menu.about")) { TomoAppWindow.open(.about) }
        }
        CommandGroup(replacing: .appSettings) {
            Button(lang.learner("menu.settings")) { TomoAppWindow.open(.settings) }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .help) {}
    }
}
