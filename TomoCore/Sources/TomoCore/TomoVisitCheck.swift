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
        g.tick(at: Date().addingTimeInterval(5))
        check(g.offered && g.visitCountdown != nil && closes == 0,
              "the peek counts as open: 5 s in, the visit isn't ended as closed mid-visit")
        g.acceptOffer()
        wait(0.5)
        check(!g.offered && asks == 1 && opens == 0 && g.phase == .asking,
              "opening the card from the peek asks the round it offered")
        g.dismiss()

        g.dropIn(force: true)
        wait(0.2)
        let offeredAgain = g.offered
        g.tick(at: Date().addingTimeInterval(DropIn.ignoreAfter + 2))
        let left = !g.offered && g.visitCountdown == nil
        wait(2)
        check(offeredAgain && left && closes == 2 && asks == 1 && g.pending == g.somethingCounts,
              "an ignored peek leaves like an ignored card: it tucks back in, never asking, and waits beside the notch")

        g.peekIsland = nil
        g.dropIn(force: true)
        check(!g.offered && opens == 1, "a shell with no peek (the iPhone) opens the card, as before")
        g.dismiss()
        g.peekIsland = { open = true; peeks += 1 }
        g.openIsland?()
        g.dropIn(force: true)
        check(!g.offered, "a visit while the card is already open asks in the card")
        g.dismiss()
        wait(0.2)
    }
}
