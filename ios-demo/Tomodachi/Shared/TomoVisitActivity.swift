import ActivityKit
import Foundation
import TomoCore

// MARK: - Tomo on the Lock Screen (Live Activity), shared by the app and the widget extension
//
// Not a quiz: an invitation. When something is waiting, Tomo calls you over ("あそぼ！ · 3 words waiting");
// tapping opens the app. When nothing is, Tomo sleeps beside a live countdown to the next words. The
// activity's stale date is that moment, so the card turns to "ready" by itself even if the app never runs.
// All text arrives in the TomoGlance, already in the learner's language.

struct TomoVisitAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var glance: TomoGlance
    }
}
