import AppKit
import SwiftUI
import TomoCore

// MARK: - Which screen Tomo lives on (#130 batch 3; a Mac-only Setting)
//
// The notch screen (the default: the one with a notch, else the main display), the main display (the one with the menu
// bar), a display by its name, or the screen the pointer is on, moving only while the island is closed. The rule is a
// pure function (`TomoScreenChoice.pick`), checked by TomoIslandSelfTest; IslandWindowController applies it when
// displays change, when the setting changes, and, following the pointer, as the pointer crosses to another screen while
// Tomo rests. Kept on this Mac only (UserDefaults), like the other visit settings.

/// What the rule needs to know about each connected screen, in `NSScreen.screens` order (the main display first).
struct TomoScreenInfo: Equatable {
    var hasNotch: Bool
    var name: String
    var frame: CGRect
}

enum TomoScreenChoice: Equatable, Hashable {
    /// The screen with the notch, else the main display (today's rule, and the default).
    case notch
    /// The main display: the one with the menu bar (`NSScreen.screens[0]`).
    case main
    /// A display by its name (`NSScreen.localizedName`); while it isn't connected, the notch rule.
    case named(String)
    /// The screen the pointer is on, moving there only while the island is closed (resting or hidden).
    case followMouse

    static let key = "tomoIslandScreen"
    /// The setting changed (IslandWindowController moves the island at once).
    static let changed = Notification.Name("TomoScreenChoiceChanged")

    /// Saved as a short string: "notch", "main", "mouse" or "display:<name>". Anything else reads as the default.
    var raw: String {
        switch self {
        case .notch: "notch"
        case .main: "main"
        case .followMouse: "mouse"
        case .named(let n): "display:" + n
        }
    }

    init(raw: String?) {
        switch raw {
        case "main": self = .main
        case "mouse": self = .followMouse
        case let r? where r.hasPrefix("display:") && r.count > "display:".count:
            self = .named(String(r.dropFirst("display:".count)))
        default: self = .notch
        }
    }

    /// The learner's choice. TOMO_SCREEN=<notch|main|mouse|display:name> overrides it for test runs, without saving.
    static var current: TomoScreenChoice {
        if let forced = ProcessInfo.processInfo.environment["TOMO_SCREEN"] { return TomoScreenChoice(raw: forced) }
        return TomoScreenChoice(raw: UserDefaults.standard.string(forKey: key))
    }

    static func set(_ choice: TomoScreenChoice) {
        UserDefaults.standard.set(choice.raw, forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// Which of `screens` Tomo lives on. `pointer` is where the pointer is (screen coordinates); `current` the screen
    /// the island is on now (nil if that screen is gone); `closed` whether the island is closed (not open, peeking or
    /// folding), which following the pointer needs before it moves. Nil only without a screen.
    static func pick(_ screens: [TomoScreenInfo], choice: TomoScreenChoice, pointer: CGPoint? = nil,
                     current: Int? = nil, closed: Bool = true) -> Int? {
        guard !screens.isEmpty else { return nil }
        let notchRule = screens.firstIndex { $0.hasNotch } ?? 0
        switch choice {
        case .notch: return notchRule
        case .main: return 0
        case .named(let n): return screens.firstIndex { $0.name == n } ?? notchRule
        case .followMouse:
            let here = current.flatMap { screens.indices.contains($0) ? $0 : nil }
            if !closed, let here { return here }   // open: it stays put until it closes
            let under = pointer.flatMap { p in screens.firstIndex { NSMouseInRect(p, $0.frame, false) } }
            return under ?? here ?? notchRule
        }
    }

    /// The choices Settings offers: the notch screen, the main one, each connected display by name, and following the
    /// pointer. A saved display that isn't connected stays in the list (marked away), so the choice still shows.
    static func options(connected: [String], saved: TomoScreenChoice) -> [(choice: TomoScreenChoice, away: Bool)] {
        var names: [String] = []
        for n in connected where !names.contains(n) { names.append(n) }
        var displays = names.map { (choice: TomoScreenChoice.named($0), away: false) }
        if case .named(let n) = saved, !names.contains(n) { displays.append((.named(n), true)) }
        return [(.notch, false), (.main, false)] + displays + [(.followMouse, false)]
    }
}

extension TomoScreenInfo {
    /// The connected screens, as the rule sees them.
    @MainActor static var connected: [TomoScreenInfo] {
        NSScreen.screens.map { TomoScreenInfo(hasNotch: $0.safeAreaInsets.top > 0, name: $0.localizedName, frame: $0.frame) }
    }
}

/// Settings' row for it, in the Mac's `device` slot: a picker of `TomoScreenChoice.options`, refreshed when displays
/// change.
struct TomoScreenSection: View {
    @ObservedObject var lang = TomoLanguages.shared
    @State private var choice = TomoScreenChoice.current
    @State private var connected = TomoScreenInfo.connected.map(\.name)

    var body: some View {
        Section {
            Picker(lang.learner("settings.screen"), selection: Binding(
                get: { choice },
                set: { choice = $0; TomoScreenChoice.set($0) })) {
                ForEach(TomoScreenChoice.options(connected: connected, saved: choice), id: \.choice) { option in
                    Text(label(option.choice, away: option.away)).tag(option.choice)
                }
            }
        } footer: {
            Text(lang.learner("settings.screenNote")).font(.caption).foregroundStyle(.secondary)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            connected = TomoScreenInfo.connected.map(\.name)
        }
    }

    private func label(_ c: TomoScreenChoice, away: Bool) -> String {
        switch c {
        case .notch: lang.learner("settings.screen.notch")
        case .main: lang.learner("settings.screen.main")
        case .followMouse: lang.learner("settings.screen.mouse")
        case .named(let n): away ? lang.learner("settings.screen.away", ["name": n]) : n
        }
    }
}
