import AppKit
import TomoCore

/// The testing tools (the Testing menu and the menu bar icon's testing items, the window's Testing and AI pages) stay
/// out of a learner's way.
/// They show after a deliberate step (docs/verification.md):
/// - ⌥-click the menu bar icon: they show for the rest of that run;
/// - `defaults write com.zenbujapanese.tomo tomoTestingTools -bool true`: they always show.
/// Not `#if DEBUG`: the owner tests with Developer ID builds. Testing never touches the saved Tomo
/// (`TomoGame.jump(toAge:)` and `skipAhead` run on a copy in memory). The switch itself is
/// `TomoFeatures.testingTools` in TomoCore, which the shared screens read.
@MainActor
enum TomoTestingTools {
    static var shown: Bool { TomoFeatures.shared.testingTools }

    /// The menu is opening: ⌥ held shows the tools.
    static func menuOpening() {
        if NSEvent.modifierFlags.contains(.option) { TomoFeatures.shared.testingTools = true }
    }
}
