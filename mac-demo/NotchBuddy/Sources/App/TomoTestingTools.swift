import AppKit

/// The testing tools (the menu's "Skip to talking", Settings → Testing) stay out of a learner's way. They show
/// after a deliberate step (docs/verification.md):
/// - ⌥-click the menu bar icon: they show for the rest of that run;
/// - `defaults write com.zenbujapanese.tomodachi tomoTestingTools -bool true`: they always show.
/// Not `#if DEBUG`: the owner tests with Developer ID builds. Testing never touches the saved Tomo
/// (`TomoGame.jump(toAge:)` and `skipAhead` run on a copy in memory).
@MainActor
final class TomoTestingTools: ObservableObject {
    static let shared = TomoTestingTools()

    @Published private(set) var shown = UserDefaults.standard.bool(forKey: "tomoTestingTools")
        || ProcessInfo.processInfo.environment["TOMO_OPEN_SETTINGS"] == "testing"

    /// The menu is opening: ⌥ held shows the tools.
    func menuOpening() {
        if NSEvent.modifierFlags.contains(.option) { shown = true }
    }
}
