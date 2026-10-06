import ActivityKit
import AppIntents
import Foundation
import TomoCore

// MARK: - Tomo on the Lock Screen (Live Activity), shared by the app and the widget extension
//
// An invitation, with a quick round on request. When something is waiting, Tomo calls you over ("A new word
// is ready to learn") with a Play button; when nothing is, Tomo sleeps beside a live countdown to the next
// words. The activity's stale date is that moment, so the card turns to "ready" by itself even if the app
// never runs. Play (TomoPlayIntent) opens one round on the card: Tomo's word and its choices, answered by
// TomoAnswerIntent. Both run in the app's process (LiveActivityIntent), which plays them in TomoGame.
// All text arrives already in the learner's language; the widget extension has no language packs.

struct TomoVisitAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var glance: TomoGlance
        /// The round open on the card, if you tapped Play.
        var round: CardRound?
    }

    struct CardRound: Codable, Hashable {
        struct Choice: Codable, Hashable {
            var id: String
            var emoji: String?
            var label: String?
        }
        var say: String               // what Tomo says (target language)
        var choices: [Choice]
        var picked: String?           // the choice just answered, to color it
        var right: Bool?              // nil while asking
        var result: String?           // "Win +1", "Miss", …
        var note: String?             // after a right answer: the reading and meaning
    }
}

/// Play on the card: opens one round. Runs in the app; the app sets `TomoVisitHook`.
struct TomoPlayIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Tomo"     // not shown anywhere: the character's name
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await TomoVisitHook.play?()
        return .result()
    }
}

/// A choice tapped on the card.
struct TomoAnswerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Tomo"
    static let isDiscoverable = false

    @Parameter(title: "id") var choice: String

    init() {}
    init(choice: String) { self.choice = choice }

    @MainActor
    func perform() async throws -> some IntentResult {
        await TomoVisitHook.answer?(choice)
        return .result()
    }
}

/// Set by the app at launch; nil in the widget extension, where the intents never run.
@MainActor
enum TomoVisitHook {
    static var play: (@MainActor () async -> Void)?
    static var answer: (@MainActor (String) async -> Void)?
}
