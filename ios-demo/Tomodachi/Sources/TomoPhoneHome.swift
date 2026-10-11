import SwiftUI
import TomoCore

// MARK: - The iPhone's home (issue #90): tabs around the play screen
//
// Play (TomoPhoneView, as it is) · Tomo · Words · Together · Settings: the same screens as the Mac's Tomodachi window,
// from TomoCore. About is the last row of Settings, as on the iPhone's own Settings. The tab bar is the iPhone's
// version of the Mac window's sidebar (decisions.md). TOMO_OPEN_WINDOW=<screen> opens a test run at that screen.

enum PhoneTab: Hashable {
    case play, tomo, words, together, settings

    /// The tab a test run asked for (TOMO_OPEN_WINDOW), else Play.
    static var requested: PhoneTab {
        switch TomoScreenNav.requested {
        case "tomo": .tomo
        case "words": .words
        case "together": .together
        case "settings", "about", "startOver": .settings
        default: .play
        }
    }
}

struct TomoPhoneHome: View {
    @ObservedObject var shell: TomoPhoneShell
    @ObservedObject var lang = TomoLanguages.shared
    @State private var tab = PhoneTab.requested
    @State private var settingsPath: [TomoScreen] = TomoScreenNav.requested == "about" ? [.about] : []

    var body: some View {
        TabView(selection: $tab) {
            Tab(lang.learner("screen.play"), systemImage: "play.fill", value: .play) {
                TomoPhoneView(shell: shell)
            }
            Tab(lang.learner("screen.tomo"), systemImage: TomoScreen.tomo.icon, value: .tomo) {
                NavigationStack {
                    TomoGrowthScreen(play: { tab = .play }, together: { tab = .together })
                        .navigationTitle(lang.learner("screen.tomo"))
                        .tomoBar()
                }
            }
            Tab(lang.learner("screen.words"), systemImage: TomoScreen.words.icon, value: .words) {
                NavigationStack {
                    TomoWordsScreen()
                        .navigationTitle(lang.learner("screen.words"))
                        .navigationBarTitleDisplayMode(.inline)
                        .tomoBar()
                }
            }
            Tab(lang.learner("screen.together"), systemImage: TomoScreen.together.icon, value: .together) {
                NavigationStack {
                    TomoTogetherTab()
                        .navigationTitle(lang.learner("screen.together"))
                        .navigationBarTitleDisplayMode(.inline)   // the postcard and its buttons fit above the tabs
                        .tomoBar()
                }
            }
            Tab(lang.learner("screen.settings"), systemImage: TomoScreen.settings.icon, value: .settings) {
                NavigationStack(path: $settingsPath) {
                    settings
                        .navigationTitle(lang.learner("screen.settings"))
                        .tomoBar()
                        .navigationDestination(for: TomoScreen.self) { _ in
                            TomoAboutScreen().navigationTitle(lang.learner("screen.about")).tomoBar()
                        }
                }
            }
        }
        .tint(Color(hex: "#34D399"))
    }

    private var settings: some View {
        TomoSettingsScreen(afterStartOver: { tab = .play }) {
            // The iPhone's own: reminders (on, how often, quiet hours) and Tomo's Lock Screen card (#88).
            TomoReminderSettingsView.Sections()
        } more: {
            Section {
                NavigationLink(value: TomoScreen.about) {
                    Label(lang.learner("screen.about"), systemImage: TomoScreen.about.icon)
                }
            }
        }
    }
}

private extension View {
    /// The tabs' navigation bar takes the screen's background once something scrolls under it, so nothing shows
    /// through behind the status bar or the title (#193). Without a style, iOS 26 leaves the bar clear over a soft
    /// blur; its hard scroll edge still shows the content, dimmed; and a bar forced visible hides the large titles.
    func tomoBar() -> some View {
        toolbarBackground(.background, for: .navigationBar)
    }
}

/// Together, for the learner's own Tomo: its progress, look and material are passed in (TomoCore's screen takes the
/// Tomo it shows).
private struct TomoTogetherTab: View {
    @ObservedObject var game = TomoGame.shared

    var body: some View {
        TomoTogetherScreen(progress: game.progress, look: TomoLook.current, material: .own,
                           version: game.progressVersion) { UIPasteboard.general.string = $0 }
    }
}
