import Foundation

// MARK: - Which Lock Screen card the iPhone keeps (its Live Activity, TomoLiveVisit)
//
// iOS keeps an app's Live Activities across launches, each with a state. Tomo has one card: the app updates the one
// still on the Lock Screen, a stale one too (its words came due while the app wasn't running, so its stale date
// passed), and ends any others, so a launch never stacks a second card under an old one. Only with no card left does
// it start one. The rule is pure, so the self-test checks it; ActivityKit stays in the iPhone shell.

public enum TomoLockCard {
    /// A card's state, as ActivityKit reports it.
    public enum State: Sendable, Equatable {
        /// On the Lock Screen, up to date.
        case active
        /// On the Lock Screen past its stale date: an update makes it current again.
        case stale
        /// Ended, dismissed, or not started yet (pending; Tomo never schedules one): not on the Lock Screen.
        case gone
    }

    /// For the app's cards, in ActivityKit's order: the one to update (nil: start one), and the ones to end. An up-to-date
    /// card wins over a stale one, then the first.
    public static func plan(_ states: [State]) -> (keep: Int?, end: [Int]) {
        let shown = states.indices.filter { states[$0] != .gone }
        let keep = shown.first { states[$0] == .active } ?? shown.first
        return (keep, shown.filter { $0 != keep })
    }

    /// The rule, checked with the reminders (TomoReminders.selfTest: `swift test` and TOMO_SELFTEST).
    public static func selfTest(_ check: (Bool, String) -> Void) {
        check(plan([]) == (nil, []) && plan([.gone, .gone]) == (nil, []),
              "the Lock Screen card: none on the Lock Screen, so the app starts one")
        check(plan([.active]) == (0, []) && plan([.stale]) == (0, []),
              "a card on the Lock Screen is updated, a stale one too (its words came due while the app wasn't running)")
        check(plan([.stale, .active]) == (1, [0]) && plan([.active, .stale, .active]) == (0, [1, 2])
              && plan([.gone, .stale, .stale]) == (1, [2]),
              "with more than one card, the app keeps one (an up-to-date one first) and ends the rest")
    }
}
