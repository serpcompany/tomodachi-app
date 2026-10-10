import AppKit
import SwiftUI
import TomoCore

// MARK: - Tomodachi's menus: the main menu and the menu bar icon's menu, from one list of commands
//
// Tomodachi is a regular app with a Dock icon (decisions.md), so its main menu shows while it's active and its
// shortcuts work then: the Tomodachi menu (About, Settings… ⌘,, Quit), a Tomo menu (Drop in now ⌘D, Tomo's
// words ⌘W, Start Tomo over…) and, while the testing tools are on (TomoTestingTools), a Testing menu (Skip to
// talking ⌘3, Grow one step ⌘G, Finish this level ⌘L, Grow to the next birthday ⌘B, Show the first run, Back to my
// Tomo). The menu bar icon's menu stays for quick access, with the same commands. All titles come from ui.<id>.json.

/// One command: its title, its shortcut (⌘ + `key`, or none) and what it does.
struct TomoCommand {
    let title: String
    let key: String
    let run: @MainActor () -> Void
}

@MainActor
enum TomoMenus {
    /// Set by AppDelegate: the island opens on purpose (free play) and takes the keyboard, so Esc closes it.
    static var openIsland: () -> Void = {}
    /// Set by AppDelegate: the island takes the keyboard (Drop in now was asked for, so Esc closes it).
    static var takeKeyboard: () -> Void = {}

    private static var ui: LearnerPack { TomoLanguages.shared.learner }

    /// The Tomo menu.
    static var tomo: [TomoCommand] {
        // A visit that peeks first (Settings) stays a peek, which never takes the keyboard; the card does.
        [TomoCommand(title: ui("menu.dropIn"), key: "d") {
            TomoGame.shared.dropIn(force: true)
            if !TomoGame.shared.offered { takeKeyboard() }
        },
         TomoCommand(title: ui("menu.words"), key: "w") { TomoAppWindow.open(.words) },
         TomoCommand(title: ui("menu.restart"), key: "") { TomoAppWindow.open(confirmStartOver: true) }]   // asks first
    }

    /// The Testing menu, while the testing tools are on. Growing opens the card to show it.
    static var testing: [TomoCommand] {
        let game = TomoGame.shared
        var items = [
            TomoCommand(title: ui("menu.talk", ["age": TomoLanguages.shared.target.ageLabel(TomoGame.chatStage)]),
                        key: "3") { game.jumpToChat() },
            TomoCommand(title: ui("menu.growStep"), key: "g") { openIsland(); game.testGrow(.step) },
            TomoCommand(title: ui("menu.growLevel"), key: "l") { openIsland(); game.testGrow(.level) },
            TomoCommand(title: ui("menu.growBirthday"), key: "b") { openIsland(); game.testGrow(.birthday) },
            // The first run as a new learner sees it, on a copy of this Tomo: nothing saved (TomoOnboardingWindow).
            TomoCommand(title: ui("menu.previewFirstRun"), key: "") { TomoOnboardingWindow.preview() },
        ]
        if game.isScratch { items.append(TomoCommand(title: ui("settings.backToTomo"), key: "") { game.reload() }) }
        return items
    }

    // MARK: The menu bar icon's menu

    /// Filled each time it opens, so it follows the interface language and the testing tools.
    static func fill(_ menu: NSMenu) {
        menu.removeAllItems()
        add(TomoCommand(title: ui("menu.open"), key: "o") { TomoAppWindow.open() }, to: menu)
        menu.addItem(.separator())
        add(TomoCommand(title: ui("menu.play"), key: "") { openIsland() }, to: menu)
        tomo.forEach { add($0, to: menu) }
        if TomoTestingTools.shown {
            menu.addItem(.separator())
            testing.forEach { add($0, to: menu) }
        }
        menu.addItem(.separator())
        add(TomoCommand(title: ui("menu.settings"), key: ",") { TomoAppWindow.open(.settings) }, to: menu)
        menu.addItem(.separator())
        menu.addItem(withTitle: ui("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    // MARK: Test runs: TOMO_DUMP_MENU=<file> writes both menus, with their shortcuts, 2 s after launch

    static func dumpIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["TOMO_DUMP_MENU"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let bar = NSMenu()
            fill(bar)
            let text = "MAIN MENU\n" + describe(NSApp.mainMenu, depth: 0) + "\nMENU BAR ICON\n" + describe(bar, depth: 1)
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private static func describe(_ menu: NSMenu?, depth: Int) -> String {
        (menu?.items ?? []).map { item in
            let pad = String(repeating: "  ", count: depth)
            if item.isSeparatorItem { return pad + "—\n" }
            let m = item.keyEquivalentModifierMask
            let mods = (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "") + (m.contains(.shift) ? "⇧" : "")
                + (m.contains(.command) ? "⌘" : "") + (m.contains(.function) ? "fn " : "")
            let key = item.keyEquivalent.isEmpty ? "" : "  " + mods + item.keyEquivalent.uppercased()
            return pad + item.title + key + "\n" + describe(item.submenu, depth: depth + 1)
        }.joined()
    }

    private static func add(_ command: TomoCommand, to menu: NSMenu) {
        let target = Target(command.run)
        let item = NSMenuItem(title: command.title, action: #selector(Target.fire), keyEquivalent: command.key)
        item.target = target
        item.representedObject = target   // the item keeps its target alive
        menu.addItem(item)
    }

    @MainActor private final class Target: NSObject {
        let run: @MainActor () -> Void
        init(_ run: @escaping @MainActor () -> Void) { self.run = run }
        @objc func fire() { run() }
    }
}

// MARK: - The main menu (SwiftUI commands), shown while Tomodachi is the active app

struct TomoCommands: Commands {
    @ObservedObject var lang = TomoLanguages.shared
    @ObservedObject var features = TomoFeatures.shared
    @ObservedObject var game = TomoGame.shared   // Back to my Tomo shows while testing runs on a copy

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(lang.learner("menu.about")) { TomoAppWindow.open(.about) }
        }
        CommandGroup(replacing: .appSettings) {
            Button(lang.learner("menu.settings")) { TomoAppWindow.open(.settings) }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button(lang.learner("menu.quit")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        CommandGroup(replacing: .newItem) {}
        CommandMenu(lang.learner("menu.tomo")) { buttons(TomoMenus.tomo) }
        if features.testingTools {
            CommandMenu(lang.learner("menu.testing")) { buttons(TomoMenus.testing) }
        }
        CommandGroup(replacing: .help) {}
    }

    @ViewBuilder private func buttons(_ commands: [TomoCommand]) -> some View {
        ForEach(Array(commands.enumerated()), id: \.offset) { _, c in
            if let key = c.key.first {
                Button(c.title) { c.run() }.keyboardShortcut(KeyEquivalent(key))
            } else {
                Button(c.title) { c.run() }
            }
        }
    }
}
