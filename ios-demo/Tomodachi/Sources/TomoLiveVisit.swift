import ActivityKit
import Foundation
import TomoCore

// MARK: - Keeps Tomo's Lock Screen card (TomoVisitAttributes) in step with progress, and plays its rounds
//
// The shell calls `show(_:)` with every new TomoGlance. The card exists only once the learner said yes to it (the
// first run's Lock Screen step, or Settings: TomoReminderSettings.lockScreen, `TomoPhoneShell.cardAllowed`); saying
// no ends it. iOS only lets an app start a Live Activity from the foreground, so the card starts while you play and
// is updated after; its stale date (`nextDue`) flips it
// to "ready" on its own when new words come due. Play and the choices on the card come back through
// TomoPlayIntent / TomoAnswerIntent (`play()`, `answer(_:)`), which run TomoGame with the card as Tomo's
// screen: `isPlaying` keeps the game "open" while a round is on the card.

@MainActor
final class TomoLiveVisit {
    static let shared = TomoLiveVisit()

    /// A round is open on the card: the game treats Tomo as open (TomoPhoneShell.isIslandOpen).
    private(set) var isPlaying = false
    private var activity: Activity<TomoVisitAttributes>? = Activity<TomoVisitAttributes>.activities.first
    private var glance: TomoGlance?
    private var round: TomoVisitAttributes.CardRound?
    private var closing: Task<Void, Never>?

    private var game: TomoGame { .shared }

    /// At launch, also when iOS launches the app in the background for a tap on the card.
    func install() {
        TomoVisitHook.play = { [weak self] in await self?.play() }
        TomoVisitHook.answer = { [weak self] id in await self?.answer(id) }
    }

    func show(_ glance: TomoGlance) {
        self.glance = glance
        Task { await push() }
    }

    /// The learner turned the card on or off: start it (in the foreground) or end it.
    func refresh() {
        glance = glance ?? TomoPhoneShell.shared.currentGlance()
        Task { await push() }
    }

    /// The app came to the front: the round moves into the app, the card goes back to inviting.
    func endRound() {
        guard round != nil || isPlaying else { return }
        closing?.cancel()
        round = nil
        isPlaying = false
        Task { await push() }
    }

    // MARK: Taps on the card

    func play() async {
        TomoPhoneShell.shared.start()
        closing?.cancel()
        isPlaying = true
        if game.phase == .resting { game.startPractice() }   // Play is a choice: practice if nothing counts
        // The game picks its next word on its own clock (TomoGame.tick, every 0.5 s).
        guard await wait(until: { self.game.phase == .asking && !self.game.round.choices.isEmpty && !self.game.isChat },
                         seconds: 3) else {
            isPlaying = false
            return
        }
        round = asked()
        glance = TomoPhoneShell.shared.currentGlance()
        await push()
    }

    func answer(_ id: String) async {
        guard round != nil else { return }
        if case .wrong = game.phase { _ = await wait(until: { self.game.phase == .asking }, seconds: 1.5) }
        guard game.phase == .asking, let choice = game.round.choices.first(where: { $0.id == id }) else { return }
        let r = game.round
        game.pick(choice)
        let ui = TomoLanguages.shared.learner
        var shown = asked(r)
        shown.picked = id
        shown.right = id == r.answer
        switch game.outcome {
        case .win(true): shown.result = ui("outcome.win")
        case .win(false): shown.result = ui("outcome.practice")
        case .loss: shown.result = ui("outcome.loss")
        default: break
        }
        if id == r.answer {
            shown.note = [r.romanization, r.meaning].compactMap { $0 }.joined(separator: " · ")
        }
        round = shown
        glance = TomoPhoneShell.shared.currentGlance()
        await push()
        guard id == r.answer else { return }          // a miss: the round stays open for another try
        // Tomo's reaction stays a moment, then the card invites again. If iOS suspends the app first, the
        // card's stale date (pushed above) does the same.
        closing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            self.round = nil
            self.isPlaying = false
            self.glance = TomoPhoneShell.shared.currentGlance()
            await self.push()
        }
    }

    // MARK: Updating the card

    private func asked(_ r: TomoRound? = nil) -> TomoVisitAttributes.CardRound {
        let r = r ?? game.round
        return .init(say: r.say, choices: r.choices.map { .init(id: $0.id, emoji: $0.emoji, label: $0.label) })
    }

    private func push() async {
        guard TomoPhoneShell.shared.cardAllowed else { await end(); return }
        guard let glance else { return }
        let stale: Date? = if round?.right == true { Date().addingTimeInterval(3) }      // back to inviting
            else if round != nil { Date().addingTimeInterval(10 * 60) }                     // an abandoned round
            else if glance.waiting { nil }
            else { glance.nextDue }                                                         // words come due
        let content = ActivityContent(state: TomoVisitAttributes.ContentState(glance: glance, round: round),
                                      staleDate: stale)
        if let activity, activity.activityState == .active {
            nonisolated(unsafe) let running = activity   // ActivityKit's Activity isn't marked Sendable
            await running.update(content)
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                activity = try Activity.request(attributes: TomoVisitAttributes(), content: content)
                NSLog("Tomo: the Lock Screen card started")
            }
            catch { NSLog("Tomo: couldn't start the Lock Screen card: \(error)") }
        }
    }

    /// No card: the learner hasn't said yes, or said no.
    private func end() async {
        round = nil
        isPlaying = false
        activity = nil
        for running in Activity<TomoVisitAttributes>.activities {
            nonisolated(unsafe) let card = running   // ActivityKit's Activity isn't marked Sendable
            await card.end(nil, dismissalPolicy: .immediate)
            NSLog("Tomo: the Lock Screen card ended")
        }
    }

    private func wait(until done: @escaping () -> Bool, seconds: Double) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !done() {
            guard Date() < end else { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return true
    }
}
