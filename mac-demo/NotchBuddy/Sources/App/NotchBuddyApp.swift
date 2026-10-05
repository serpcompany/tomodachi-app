import SwiftUI
import AppKit
import TomoCore

@main
struct NotchBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            TomoSettingsView()
        }
    }
}
