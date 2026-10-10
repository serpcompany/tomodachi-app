import AppKit
import TomoCore

/// The island shell's rules that a headless run can't show by hand (which screen, where, Esc, the resting right side),
/// checked by TOMO_SELFTEST with TomoCore's (docs/verification.md).
@MainActor
enum TomoIslandSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ c: Bool, _ what: String) {
            print((c ? "ok    " : "FAIL  ") + what)
            if !c { ok = false }
        }
        typealias C = IslandWindowController

        check(C.pickScreen([false, true]) == 1, "Tomo lives on the screen with the notch, wherever it is in the list")
        check(C.pickScreen([false, false]) == 0, "no notch (lid closed, only external displays): the main display")
        check(C.pickScreen([]) == nil, "no screen: nowhere to go")
        let external = NSRect(x: -1920, y: 200, width: 1920, height: 1080)
        let frame = C.panelFrame(on: external)
        check(frame.maxY == external.maxY && frame.midX == external.midX,
              "on a display left of and above the main one, the island sits at its top centre")
        let notch = IslandScreenGeometry(screenWidth: 1512, safeAreaTop: 32, auxiliaryLeftWidth: 664,
                                         auxiliaryRightWidth: 664, menuBarHeight: 32)
        check(notch.hasNotch && notch.width == 184 && notch.height == 32, "on a notch screen the island fits the notch")
        let flat = IslandScreenGeometry(screenWidth: 1920, safeAreaTop: 0, auxiliaryLeftWidth: nil,
                                        auxiliaryRightWidth: nil, menuBarHeight: 25)
        check(!flat.hasNotch && flat.width == 80 && flat.height == 24, "without a notch it's a small bar under the menu bar")

        // The resting island's right side (TomoRestingSide): in the right ear, never under the notch, never a count.
        for (screen, name) in [(notch, "a notch"), (flat, "no notch")] {
            let (w, h) = islandSize(mode: .compact, view: .overview, nw: screen.width, nh: screen.height)
            let side = IslandRestingLayout(width: w, height: h).rightSide
            check(side.minX >= (w + screen.width) / 2 && side.maxX <= w && side.minY >= 0 && side.maxY <= h,
                  "with \(name), the resting island's right side fits right of the notch: \(side) in \(w) × \(h)")
        }
        let lang = TomoLanguages.shared
        let invite = TomoRestingSide.label(counts: true, next: nil, lang)
        check(invite?.text == (lang.target.lines.invite ?? lang.target.lines.practice) && invite?.dimmed == false
              && invite?.text.contains(where: \.isNumber) == false,
              "something counts: the right side says the pack's invite, with no number")
        let soon = TomoClock.now.addingTimeInterval(20 * 3600), later = TomoClock.now.addingTimeInterval(3 * 86400)
        let timeOnly = DateFormatter()
        timeOnly.locale = Locale(identifier: lang.learner.id)
        timeOnly.timeStyle = .short
        let back = TomoRestingSide.label(counts: false, next: soon, lang)
        check(back?.text == timeOnly.string(from: wallClock(soon)) && back?.dimmed == true,
              "nothing counts: when words are back, dimmed, the time alone within a day (\(back?.text ?? "none"))")
        let far = tomoNextTime(later, lang)
        check(!far.contains(timeOnly.string(from: wallClock(later))), "further off, the day without the time (\(far))")
        check(TomoRestingSide.label(counts: false, next: nil, lang) == nil, "no time known: only the level ring")

        // The countdown line (TomoCountdownLine): drawn from the deadline, so it never jumps.
        let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
        let run = TomoCountdown(from: t0, until: at(DropIn.ignoreAfter))
        let samples = stride(from: -2.0, through: DropIn.ignoreAfter + 2, by: 0.05).map(at)
        check(samples.allSatisfy { (0...1).contains(run.fraction(at: $0)) } && run.fraction(at: t0) == 1
              && run.fraction(at: at(DropIn.ignoreAfter)) == 0 && run.fraction(at: at(5)) == 0.5,
              "the countdown line is full when set, half at 5 s of 10, empty at the deadline, never outside 0…1")
        check(zip(samples, samples.dropFirst()).allSatisfy { run.fraction(at: $1) <= run.fraction(at: $0) },
              "between resets the line only shrinks")
        let reset = run.reset(at: at(4), until: at(4 + DropIn.ignoreAfter))
        let after = samples.map { $0.addingTimeInterval(4) }.filter { $0 >= at(4) }
        check(abs(reset.fraction(at: at(4)) - run.fraction(at: at(4))) < 1e-9
              && reset.fraction(at: at(4 + TomoCountdown.refill / 2)) > run.fraction(at: at(4))
              && abs(reset.fraction(at: at(4 + TomoCountdown.refill))
                     - (DropIn.ignoreAfter - TomoCountdown.refill) / DropIn.ignoreAfter) < 1e-6,
              "a reset (an answer) grows the line back from where it was, never a jump, then runs again")
        check(after.allSatisfy { (0...1).contains(reset.fraction(at: $0)) }
              && zip(after, after.dropFirst()).filter { $0.0 >= at(4 + TomoCountdown.refill) }
                .allSatisfy { reset.fraction(at: $0.1) <= reset.fraction(at: $0.0) },
              "after the refill, the reset line only shrinks, within 0…1")
        typealias G = TomoGame
        check(G.countdownShows(visit: true, open: true, paused: false, phase: .asking)
              && G.countdownShows(visit: true, open: true, paused: false, phase: .resting)
              && G.countdownShows(visit: true, open: true, paused: false, phase: .wrong("x")),
              "the line shows while a visit asks (a wrong pick's shake too) or rests, the phases its deadline ends")
        check(!G.countdownShows(visit: true, open: true, paused: true, phase: .asking),
              "paused (the pointer in the island, listening, help open): no line")
        check(!G.countdownShows(visit: false, open: true, paused: false, phase: .asking)
              && !G.countdownShows(visit: true, open: false, paused: false, phase: .asking)
              && !G.countdownShows(visit: true, open: true, paused: false, phase: .right),
              "free play, a closed island, or a phase the deadline doesn't end: no line")

        check(C.escCloses(keyCode: 53, inIsland: true, open: true), "Esc in the open island closes it")
        check(!C.escCloses(keyCode: 53, inIsland: false, open: true), "Esc in another window (Settings) is left alone")
        check(!C.escCloses(keyCode: 53, inIsland: true, open: false), "Esc with the island closed is left alone")
        check(!C.escCloses(keyCode: 36, inIsland: true, open: true), "other keys pass on")
        return ok
    }
}
