import Foundation

/// The island's rules: when it shows, peeks, opens and folds, from the pointer, clicks, the app and the clock.
/// Pure: no AppKit, no timers. Every input takes the time (`now`, seconds on the shell's clock) and returns when the
/// rules next need the clock (nil: not before another input). The shell sets one timer for that and calls
/// `advance(to:)`, so the rules run the same on a stopped clock (TomoIslandSelfTest). Transitions the rules make
/// (`collapse` included) fire `onTransition`; the app's own openings (`openedExternally`, `peekedExternally`) only
/// bring them in step.
@MainActor
final class IslandStateMachine {

    enum State: Equatable {
        case hidden   // island invisible (notch size)
        case petit    // compact island (notch + ears)
        case peek     // a visit offered, before its card opens
        case home     // expanded: Tomo's card
    }

    private(set) var state: State = .hidden

    /// Fired on every transition the rules make: (from, to)
    var onTransition: ((State, State) -> Void)?

    /// home or peek → petit, once the pointer has been away this long (seconds). Override for debug.
    var homeToPetitDelay: TimeInterval = 15
    /// petit → hidden, once the pointer has been away this long (seconds). Override for debug.
    var petitToHiddenDelay: TimeInterval = 60
    /// peek → home: the pointer resting on a peek this long opens its card (seconds).
    var peekHoverToOpen: TimeInterval = 0.45

    /// Whether the pointer is in the island.
    private(set) var pointerInside = false
    /// When the pointer came into the island as it is now. Nil while the pointer is away, and once the island changes
    /// under it (a close, a peek arriving): only a pointer that comes in hovers, so after a close, hovering doesn't
    /// reopen anything until the pointer has left the island once.
    private var hoverSince: TimeInterval?
    /// When the island folds a step (home or peek → petit → hidden) because the pointer stayed away. Nil while the
    /// pointer is in it, and after the app opened it: a visit keeps its own time (TomoGame).
    private var foldAt: TimeInterval?

    /// Whether the pointer is hovering the island (it came in, and the island hasn't changed under it since).
    var hovering: Bool { hoverSince != nil }

    /// When the rules next need the clock: a fold, or a hover opening a peek. Nil: not before another input.
    var nextCheck: TimeInterval? {
        let opens = state == .peek ? hoverSince.map { $0 + peekHoverToOpen } : nil
        return [foldAt, opens].compactMap { $0 }.min()
    }

    // MARK: – Inputs (each returns `nextCheck`)

    /// Mouse entered the island notch area
    func mouseEntered(at now: TimeInterval) -> TimeInterval? {
        settle(now)
        pointerInside = true
        foldAt = nil
        if state == .hidden { transition(to: .petit, at: now) }
        hoverSince = now
        return nextCheck
    }

    /// Mouse left the island notch area
    func mouseLeft(at now: TimeInterval) -> TimeInterval? {
        settle(now)
        pointerInside = false
        hoverSince = nil
        foldAt = foldDelay.map { now + $0 }
        return nextCheck
    }

    /// The island clicked: the card opens.
    /// Also accepts `.hidden`: the island can be on screen while the FSM never saw the
    /// mouse enter (it was already there), and the click must still open it.
    func click(at now: TimeInterval) -> TimeInterval? {
        settle(now)
        transition(to: .home, at: now)
        return nextCheck
    }

    /// The app showed a peek itself (a visit offered). Like `openedExternally`, it brings the rules in step without
    /// `onTransition`, and nothing folds it until the pointer has come and gone. An open card stays open.
    func peekedExternally(at now: TimeInterval) -> TimeInterval? {
        settle(now)
        if state != .home { bringInStep(.peek) }
        return nextCheck
    }

    /// The app expanded the island itself (Tomo's visit, the menu's Open).
    /// Stop any fold and sync state to `.home` without firing `onTransition`, so the
    /// next hover/mouseLeft behave correctly instead of collapsing the island.
    func openedExternally(at now: TimeInterval) -> TimeInterval? {
        settle(now)
        bringInStep(.home)
        return nextCheck
    }

    /// The app folded the island itself (Esc, Settings, Tomo's goodbye, an ignored visit).
    /// Move to `.petit` right away so hover and click keep working; waiting for the
    /// home fold left the island compact on screen while the FSM still said `.home`.
    func collapse(at now: TimeInterval) -> TimeInterval? {
        settle(now)
        if state == .home || state == .peek { transition(to: .petit, at: now) }
        return nextCheck
    }

    /// The clock: makes every transition that came due by `now`, in order.
    func advance(to now: TimeInterval) -> TimeInterval? {
        settle(now)
        return nextCheck
    }

    // MARK: – Rules

    /// How long the pointer may stay away before the island folds a step from here.
    private var foldDelay: TimeInterval? {
        switch state {
        case .hidden: nil
        case .petit: petitToHiddenDelay
        case .peek, .home: homeToPetitDelay
        }
    }

    /// Makes each transition that came due by `now`, at the time it came due.
    private func settle(_ now: TimeInterval) {
        while let due = nextCheck, due <= now {
            if due == foldAt {
                switch state {
                case .home, .peek: transition(to: .petit, at: due)
                case .petit: transition(to: .hidden, at: due)
                case .hidden: foldAt = nil
                }
            } else {
                transition(to: .home, at: due)   // the pointer rested on the peek
            }
        }
    }

    private func transition(to new: State, at time: TimeInterval) {
        guard new != state else { return }
        let old = state
        state = new
        hoverSince = nil   // the island changed under the pointer: no hover until it comes in again
        foldAt = pointerInside ? nil : foldDelay.map { time + $0 }   // the pointer is away: folds on from here
        onTransition?(old, new)
    }

    /// The app changed the island itself: no `onTransition`, and no fold until the pointer has come and gone.
    private func bringInStep(_ new: State) {
        foldAt = nil
        guard new != state else { return }
        state = new
        hoverSince = nil
    }

}
