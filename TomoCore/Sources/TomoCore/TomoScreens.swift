import SwiftUI

// MARK: - The app's screens, the same on the Mac and the iPhone (issue #90)
//
// Tomo (how it's growing), Words (every level and word), Settings and About. Each is a SwiftUI view here in TomoCore
// (TomoGrowthScreen, TomoWordsScreen, TomoSettingsScreen, TomoAboutScreen), so both shells show the same screen: the
// Mac in the Tomodachi window with a sidebar (TomoAppWindow), the iPhone as tabs around the play screen
// (TomoPhoneHome). Platform touches are `#if os(…)` inside the views; what only one device has (open at login on the
// Mac, reminders on the iPhone) comes in through a slot in Settings. All text comes from ui.<id>.json.

public enum TomoScreen: String, CaseIterable, Identifiable, Sendable {
    case tomo, words, settings, about
    /// The AI provider and key: hidden for now (TomoFeatures), the code kept for later.
    case ai
    /// The Mac's testing tools (another age, skip ahead a day), after ⌥-clicking the menu bar icon.
    case testing

    public var id: String { rawValue }
    public var titleKey: String { "screen.\(rawValue)" }

    public var icon: String {
        switch self {
        case .tomo:     "face.smiling.inverse"
        case .words:    "character.book.closed.fill"
        case .settings: "gearshape.fill"
        case .about:    "info.circle.fill"
        case .ai:       "sparkles"
        case .testing:  "flask.fill"
        }
    }

    public var color: Color {
        switch self {
        case .tomo:     .orange
        case .words:    .teal
        case .settings: .gray
        case .about:    .blue
        case .ai:       .purple
        case .testing:  .pink
        }
    }
}

/// Which screen shows, on either device: the Mac window's sidebar selection, the iPhone's tab.
@MainActor
public final class TomoScreenNav: ObservableObject {
    public static let shared = TomoScreenNav()

    @Published public var screen: TomoScreen
    /// Settings asks "Start Tomo over?" (the Mac's menu bar item asks through here). Starting over is always confirmed.
    @Published public var confirmingStartOver: Bool

    /// TOMO_OPEN_WINDOW=<screen> (tomo, words, settings, about, ai, testing): a test run opens at that screen
    /// (docs/verification.md). `startOver` opens Settings with the confirmation up; `tour` (the Mac) shows every
    /// screen in turn. TOMO_OPEN_SETTINGS is the older name (`general` was Settings).
    nonisolated public static let requested: String? = {
        let env = ProcessInfo.processInfo.environment
        return env["TOMO_OPEN_WINDOW"] ?? env["TOMO_OPEN_SETTINGS"].map { $0 == "general" ? "settings" : $0 }
    }()

    private init() {
        let asked = Self.requested
        screen = asked.flatMap(TomoScreen.init(rawValue:)) ?? (asked == "startOver" ? .settings : .tomo)
        confirmingStartOver = asked == "startOver"
    }
}

/// What this version offers. The MVP is Japanese only and offline (decisions.md): the AI page and the "I'm learning"
/// picker stay in the code, and show only with the testing tools.
@MainActor
public final class TomoFeatures: ObservableObject {
    public static let shared = TomoFeatures()

    /// The language every learner learns for now.
    public static let target = "ja"

    /// The testing tools are on: on the Mac, ⌥-click the menu bar icon (TomoTestingTools), or
    /// `defaults write com.zenbujapanese.tomo tomoTestingTools -bool true`.
    @Published public var testingTools: Bool

    private init() {
        testingTools = UserDefaults.standard.bool(forKey: "tomoTestingTools")
            || ["testing", "ai"].contains(TomoScreenNav.requested)
    }

    /// The AI page: the provider for word cards and explanations. Never in a Release build (`TomoAI.isAvailable`).
    public var ai: Bool { testingTools && TomoAI.isAvailable }

    /// The "I'm learning" picker: with the testing tools, or for a learner already on another language, so they can
    /// come back to Japanese.
    public func targetPicker(current: String) -> Bool { testingTools || current != Self.target }
}

/// A small live Tomo for the screens. Tomo is never a still image: it breathes, blinks and fidgets here too, and follows
/// Reduce Motion (`TomoMotion`).
/// `look` nil is the learner's own Tomo at its age; `.mascot` is the app's mascot (About).
public struct TomoLiveAvatar: View {
    let size: CGFloat
    let fixedGrowth: CGFloat?
    @ObservedObject var game = TomoGame.shared
    @State private var blob: TomoBlob

    public init(size: CGFloat, look: TomoLook? = nil, growth: CGFloat? = nil) {
        self.size = size
        self.fixedGrowth = growth
        _blob = State(initialValue: TomoBlob(look: look, motion: .shared))
    }

    private var step: CGFloat { fixedGrowth ?? game.growthStep }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { ctx, sz in
                blob.frameDate = timeline.date
                blob.step()
                blob.draw(ctx, size: sz)
            }
        }
        .frame(width: size, height: size)
        .onAppear { blob.setGrowth(step) }
        .onChange(of: game.stage) { _, _ in if fixedGrowth == nil { blob.grow(to: step) } }
        .accessibilityHidden(true)
    }
}
