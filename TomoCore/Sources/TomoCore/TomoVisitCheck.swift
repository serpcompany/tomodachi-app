import Foundation

// MARK: - A visit offered as a peek, checked on the real game (TOMO_SELFTEST, run by the Mac's TomoIslandSelfTest)

extension TomoGame {
    /// A visit that peeks first, run on the game itself with a stand-in shell and a testing Tomo in memory (nothing is
    /// saved, nothing said): the peek shows the round's word without asking it, counts as open, and runs the visit's
    /// countdown; opening the card asks the round; ignored, the visit leaves as an ignored card does, never asking; and
    /// a shell without a peek (the iPhone) opens the card as before. Waits on the game's own timers, about 3 s.
    public static func offerSelfTest(_ check: (Bool, String) -> Void) {
        let g = TomoGame.shared
        let shell = (g.openIsland, g.closeIsland, g.peeksFirst, g.peekIsland, g.isIslandOpen, g.isPointerInside,
                     g.onBotState)
        var open = false, peeks = 0, opens = 0, closes = 0, asks = 0
        g.silent = true
        g.peeksFirst = { true }
        g.peekIsland = { open = true; peeks += 1 }
        g.openIsland = { open = true; opens += 1 }
        g.closeIsland = { open = false; closes += 1 }
        g.isIslandOpen = { open }
        g.isPointerInside = { false }
        g.onBotState = { if $0 == .question { asks += 1 } }
        defer {
            (g.openIsland, g.closeIsland, g.peeksFirst, g.peekIsland, g.isIslandOpen, g.isPointerInside,
             g.onBotState) = shell
            g.silent = false
        }
        func wait(_ s: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }   // the game's timers

        g.jump(toAge: 1, open: false)   // a testing Tomo in memory: the saved one isn't touched
        g.dropIn(force: true)
        wait(0.2)
        check(g.offered && peeks >= 1 && opens == 0 && !g.round.say.isEmpty && asks == 0,
              "a visit that peeks first shows its word (\(g.round.say)) in the peek, not asked or said yet")
        check(g.visitCountdown != nil, "the visit's countdown runs on the peek")
        check(g.visitNow?.opened == .peek && g.visitNow?.cardAt == nil,
              "the visit log: a visit that peeks first starts as a peek, its card not opened yet")
        g.tick(at: Date().addingTimeInterval(5))
        check(g.offered && g.visitCountdown != nil && closes == 0,
              "the peek counts as open: 5 s in, the visit isn't ended as closed mid-visit")
        g.acceptOffer()
        wait(0.5)
        check(!g.offered && asks == 1 && opens == 0 && g.phase == .asking,
              "opening the card from the peek asks the round it offered")
        check(g.visitNow?.cardAt != nil, "the visit log notes when the peek opened into the card")
        g.dismiss()
        check(g.visitNow == nil && g.lastVisit?.opened == .peek && g.lastVisit?.ended == .closed,
              "the visit log: closing it ends the visit as closed")

        g.dropIn(force: true)
        wait(0.2)
        let offeredAgain = g.offered
        g.tick(at: Date().addingTimeInterval(DropIn.ignoreAfter + 2))
        let left = !g.offered && g.visitCountdown == nil
        wait(2)
        check(offeredAgain && left && closes == 2 && asks == 1 && g.pending == g.somethingCounts,
              "an ignored peek leaves like an ignored card: it tucks back in, never asking, and waits beside the notch")
        check(g.lastVisit?.opened == .peek && g.lastVisit?.cardAt == nil && g.lastVisit?.ended == .ignored,
              "the visit log: an ignored peek is a visit ignored, its card never opened")

        g.peekIsland = nil
        g.dropIn(force: true)
        check(!g.offered && opens == 1, "a shell with no peek (the iPhone) opens the card, as before")
        check(g.visitNow?.opened == .card && g.visitNow?.cardAt == g.visitNow?.started,
              "the visit log: a visit that opens the card starts with its card open")
        g.dismiss()
        g.peekIsland = { open = true; peeks += 1 }
        g.openIsland?()
        g.dropIn(force: true)
        check(!g.offered, "a visit while the card is already open asks in the card")
        g.dismiss()
        wait(0.2)

        // The learner opening Tomo themselves is a time together too (free play), ended when it closes; one that spans
        // the app being suspended (the iPhone app left, the Mac asleep) ends then, and coming back starts another.
        open = true
        g.tick()
        let opened = g.visitNow
        g.tick(at: Date().addingTimeInterval(120))
        let split = g.lastVisit?.started == opened?.started && g.lastVisit?.ended == .closed
            && g.visitNow?.opened == .learner && g.visitNow?.started != opened?.started
        open = false
        g.tick(at: Date().addingTimeInterval(121))
        check(opened?.opened == .learner && opened?.cardAt != nil && split && g.visitNow == nil
              && g.lastVisit?.opened == .learner && g.lastVisit?.ended == .closed,
              "the visit log: the learner opening Tomo is logged as theirs, split when the app was suspended, and ends as it closes")
        wait(0.2)
    }
}
