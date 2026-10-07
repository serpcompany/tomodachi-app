import SwiftUI
import TomoCore

// MARK: - The iPhone's home (issue #90): tabs around the play screen
//
// Play (TomoPhoneView, as it is) · Tomo · Words · Settings: the same screens as the Mac's Tomodachi window, from
// TomoCore. About is the last row of Settings, as on the iPhone's own Settings. The tab bar is the iPhone's version of
// the Mac window's sidebar (decisions.md). TOMO_OPEN_WINDOW=<screen> opens a test run at that screen.

enum PhoneTab: Hashable {
    case play, tomo, words, settings

    /// The tab a test run asked for (TOMO_OPEN_WINDOW), else Play.
    static var requested: PhoneTab {
        switch TomoScreenNav.requested {
        case "tomo": .tomo
        case "words": .words
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
                    TomoGrowthScreen(play: { tab = .play })
                        .navigationTitle(lang.learner("screen.tomo"))
                }
            }
            Tab(lang.learner("screen.words"), systemImage: TomoScreen.words.icon, value: .words) {
                NavigationStack {
                    TomoWordsScreen()
                        .navigationTitle(lang.learner("screen.words"))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            Tab(lang.learner("screen.settings"), systemImage: TomoScreen.settings.icon, value: .settings) {
                NavigationStack(path: $settingsPath) {
                    settings
                        .navigationTitle(lang.learner("screen.settings"))
                        .navigationDestination(for: TomoScreen.self) { _ in
                            TomoAboutScreen().navigationTitle(lang.learner("screen.about"))
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
