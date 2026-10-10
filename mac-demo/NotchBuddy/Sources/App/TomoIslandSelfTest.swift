import AppKit
import TomoCore

/// The island shell's rules that a headless run can't show by hand (which screen, where, Esc, the resting right
/// side, click-through, opening and closing), checked by TOMO_SELFTEST with TomoCore's (docs/verification.md).
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

        // Click-through follows the pointer's moves and the island's changes, with no clock between them.
        let panel = C.panelSize
        let notchSize = CGSize(width: notch.width, height: notch.height)
        func island(_ mode: IslandMode, help: CGFloat = 0, notch: CGSize = notchSize, hasNotch: Bool = true) -> CGRect {
            C.islandFrame(panel: panel, mode: mode, view: .overview, notch: notch, help: help, hasNotch: hasNotch)
        }
        func takes(_ p: CGPoint, _ mode: IslandMode, help: CGFloat = 0, hasNotch: Bool = true,
                   notch: CGSize = notchSize) -> Bool {
            C.pointerInIsland(p, island: island(mode, help: help, notch: notch, hasNotch: hasNotch), hasNotch: hasNotch,
                              open: mode == .expanded)
        }
        // Small Tomo in the resting island, in panel coordinates (botPosition counts down from the island's top).
        let rest = island(.compact)
        let (bx, by, _, _) = botPosition(mode: .compact, view: .overview, islandW: rest.width, islandH: rest.height)
        let smallTomo = CGPoint(x: rest.minX + bx, y: rest.maxY - by)
        // A fast flick from the far corner of the screen below: about 1,000 pt in 50 ms, six moves at 120 Hz.
        let start = CGPoint(x: smallTomo.x + 700, y: smallTomo.y - 700)
        let flick = (1...6).map { i -> CGPoint in
            let t = CGFloat(i) / 6
            return CGPoint(x: start.x + (smallTomo.x - start.x) * t, y: start.y + (smallTomo.y - start.y) * t)
        }
        let onTheWay = flick.dropLast().map { takes($0, .compact) }
        check(!onTheWay.contains(true) && !onTheWay.contains { C.needsPointerClock(inIsland: $0, appActive: false) },
              "a flick toward small Tomo: on the way there the panel lets clicks through, with no clock running")
        let landed = takes(flick.last!, .compact)
        check(landed && C.needsPointerClock(inIsland: landed, appActive: false),
              "the flick's last move lands on small Tomo: the panel takes clicks before the click that follows it")
        check(C.needsPointerClock(inIsland: false, appActive: true),
              "while Tomodachi is the active app, the clock runs")
        // A still pointer, the island changing around it.
        let inCard = CGPoint(x: panel.width / 2, y: panel.height - 120)
        check(!takes(inCard, .compact) && takes(inCard, .expanded),
              "a still pointer: the card opening over it takes it in, the resting island leaves it to the app below")
        let underCard = CGPoint(x: panel.width / 2, y: island(.expanded).minY - 40)
        check(!takes(underCard, .expanded) && takes(underCard, .expanded, help: TomoGrid.helpHeight),
              "a still pointer just under the card: the help panel growing under it takes it in")
        check(!takes(underCard, .compact, help: TomoGrid.helpHeight),
              "the card closing lets a still pointer go")
        // No notch: the resting bar never reaches below itself, so the window under the menu bar keeps its clicks.
        let flatNotch = CGSize(width: flat.width, height: flat.height)
        let bar = island(.compact, notch: flatNotch)
        check(takes(CGPoint(x: bar.midX, y: bar.midY), .compact, hasNotch: false, notch: flatNotch)
              && !takes(CGPoint(x: bar.midX, y: bar.minY - 3), .compact, hasNotch: false, notch: flatNotch),
              "no notch: the resting bar takes clicks on itself, not 3 pt below it")

        peek(check, notch: notch, flat: flat, island: island, takes: takes)
        motion(check, notch: notch, flat: flat)
        rules(check)
        TomoGame.offerSelfTest(check)
        return ok
    }

    /// A visit offered as a peek (TomoPeek.swift): the bar's fixed slots, its clicks, and the word's way into the card.
    private static func peek(_ check: (Bool, String) -> Void, notch: IslandScreenGeometry, flat: IslandScreenGeometry,
                             island: (IslandMode, CGFloat, CGSize, Bool) -> CGRect,
                             takes: (CGPoint, IslandMode, CGFloat, Bool, CGSize) -> Bool) {
        typealias C = IslandWindowController
        // Words from the pack: a short one, and two of its longest lines together, twice as long as any it asks.
        let target = TomoLanguages.shared.target
        let short = target.lines.bye
        let lines = (target.levels.flatMap { $0.rounds ?? [] }.map(\.say) + target.allStarters.map(\.say))
            .sorted { $0.count > $1.count }
        let long = lines.prefix(2).joined(separator: " ")
        for (screen, name) in [(notch, "a notch"), (flat, "no notch")] {
            let l = TomoPeekLayout(hasNotch: screen.hasNotch, notchHeight: screen.height)
            let (w, h) = islandSize(mode: .peek, view: .overview, nw: screen.width, nh: screen.height, hasNotch: screen.hasNotch)
            let bar = CGRect(x: 0, y: 0, width: w, height: h)
            let lineTop = h - TomoCountdownLine.bottom - TomoCountdownLine.height
            check(w == 520 && h == (screen.hasNotch ? 88 : 64) && l.size == CGSize(width: w, height: h),
                  "with \(name), a peek widens the island to \(Int(w)) × \(Int(h))")
            check(l.tomo.width == 72 && l.tomo.height == h && l.tomo.maxX <= (w - screen.width) / 2,
                  "with \(name), Tomo sits at the left in 72 × \(Int(h)), clear of the notch")
            check([l.invite, l.word].allSatisfy { bar.contains($0) && $0.minX >= l.tomo.maxX && $0.maxY <= lineTop }
                  && l.invite.minY >= (screen.hasNotch ? screen.height : 0) && l.invite.maxY <= l.word.minY,
                  "with \(name), the invite and the word sit right of Tomo, below the notch, above the countdown line")
            let size = l.wordSize(long)
            let fitted = (long as NSString).size(withAttributes: [.font: TomoWords.lineFont(size)]).width
            check(l.wordSize(short) == 24 && size < 24 && fitted <= l.wordWidth && l.wordWidth > 200,
                  "with \(name), the word is 24 pt, smaller only to fit one line beside the speaker (\(size) pt)")
            let peekBar = island(.peek, 0, CGSize(width: screen.width, height: screen.height), screen.hasNotch)
            let below = CGPoint(x: peekBar.midX, y: peekBar.minY - (screen.hasNotch ? 7 : 3))
            check(takes(CGPoint(x: peekBar.midX, y: peekBar.midY), .peek, 0, screen.hasNotch,
                        CGSize(width: screen.width, height: screen.height))
                  && !takes(below, .peek, 0, screen.hasNotch, CGSize(width: screen.width, height: screen.height)),
                  "with \(name), the peek takes clicks on itself and lets through the ones just below it")
            if let f = TomoWordFlight(word: short, script: target.script, peek: l, panelWidth: C.panelSize.width) {
                let slot = TomoWordFlight.cardWordSlot(panelWidth: C.panelSize.width)
                let card = CGRect(x: (C.panelSize.width - IslandConst.expandedWidth) / 2, y: 0,
                                  width: IslandConst.expandedWidth, height: IslandConst.layout(.overview).height)
                let barInPanel = bar.offsetBy(dx: (C.panelSize.width - w) / 2, dy: 0)
                check(barInPanel.contains(f.from) && f.fromSize == l.wordSize(short) && card.contains(slot)
                      && f.to.x == slot.minX + TomoWords.wordPadding && f.to.y == slot.midY && f.toSize <= 30,
                      "with \(name), opening the peek slides the word from the bar into the card's word slot")
            } else {
                check(false, "with \(name), opening the peek slides the word from the bar into the card's word slot")
            }
        }
        check(C.countsAsOpen(.peek) && C.countsAsOpen(.expanded) && !C.countsAsOpen(.compact) && !C.countsAsOpen(.hidden),
              "a peek counts as open for the game, like the card, so a visit offered in one isn't closed mid-visit")
        check(TomoWordFlight(word: "", script: target.script, peek: TomoPeekLayout(hasNotch: true, notchHeight: 32),
                             panelWidth: C.panelSize.width) == nil, "nothing to say: no word slides")
        let path = stride(from: 0.0, through: 1.0, by: 0.01).map(TomoWordFlight.progress(at:))
        let peak = path.max() ?? 0
        let settledAt = path.indices.first { i in path[i...].allSatisfy { abs($0 - 1) < 0.01 } }
        check(path.first == 0 && peak > 1.02 && peak < 1.08 && (settledAt.map { Double($0) / 100 } ?? 9) <= 0.5
              && TomoWordFlight.progress(at: TomoWordFlight.duration) == 1,
              "the word slides in about 0.5 s with a small overshoot (\(Int((peak - 1) * 100))%), and sits still where the card's takes over")
    }

    /// Arrivals and motion (#130): what Tomo does as the island changes, and the resting island growing under the
    /// pointer, with the click area growing with it (both take the size from `islandSize`).
    private static func motion(_ check: (Bool, String) -> Void, notch: IslandScreenGeometry, flat: IslandScreenGeometry) {
        typealias C = IslandWindowController
        typealias T = TomoCharacterView
        check(T.move(from: .compact, to: .expanded, arriving: true) == .dripIn
              && T.move(from: .hidden, to: .peek, arriving: true) == .dripIn
              && T.move(from: .compact, to: .peek, arriving: true) == .dripIn,
              "a visit drips Tomo in from the notch, as its card or its peek")
        check(T.move(from: .compact, to: .expanded, arriving: false) == .appear
              && T.move(from: .peek, to: .expanded, arriving: false) == .none
              && T.move(from: .expanded, to: .expanded, arriving: true) == .none,
              "a click opens the card without a drip, and a peek opening into its card is the same visit")
        check(T.move(from: .expanded, to: .compact, arriving: false) == .pullUp
              && T.move(from: .peek, to: .compact, arriving: false) == .pullUp
              && T.move(from: .expanded, to: .hidden, arriving: false) == .pullUp
              && T.backAfter(pulledUp: true) >= 0.34 && T.backAfter(pulledUp: false) >= C.pullUpTime,
              "the card or the peek closing pulls Tomo up into the notch, and it's back beside it once that's done")
        check(C.foldWaits(from: .expanded, to: .compact, reduceMotion: false)
              && C.foldWaits(from: .peek, to: .compact, reduceMotion: false)
              && !C.foldWaits(from: .expanded, to: .compact, reduceMotion: true)
              && !C.foldWaits(from: .peek, to: .expanded, reduceMotion: false)
              && !C.foldWaits(from: .compact, to: .hidden, reduceMotion: false) && C.pullUpTime == 0.45,
              "the card or the peek waits 0.45 s to fold while Tomo is pulled up out of it (under Reduce Motion it folds at once)")
        let key = TomoView.cardKey
        let asked = key(.asking, false, "ja:wanwan")
        check(asked == key(.wrong("x"), false, "ja:wanwan") && asked == key(.right, false, "ja:wanwan")
              && asked != key(.asking, false, "ja:mama") && asked != key(.resting, false, "ja:wanwan")
              && key(.leveledUp, false, "ja:wanwan") != key(.grew, false, "ja:wanwan")
              && key(.asking, true, "ja:wanwan") != asked,
              "the card's contents blur across when it becomes another card (a new word, resting, a level-up), not for an answer")
        let grows = C.restingGrows(mode: .compact, hovering: true, reduceMotion: false)
        let not = [C.restingGrows(mode: .compact, hovering: false, reduceMotion: false),
                   C.restingGrows(mode: .compact, hovering: true, reduceMotion: true),
                   C.restingGrows(mode: .peek, hovering: true, reduceMotion: false),
                   C.restingGrows(mode: .expanded, hovering: true, reduceMotion: false),
                   C.restingGrows(mode: .hidden, hovering: true, reduceMotion: false)]
        check(grows && !not.contains(true),
              "only the resting island grows under a pointer that came onto it; never a peek, the card, or under Reduce Motion")
        for (screen, name) in [(notch, "a notch"), (flat, "no notch")] {
            let n = CGSize(width: screen.width, height: screen.height)
            let small = islandSize(mode: .compact, view: .overview, nw: n.width, nh: n.height, hasNotch: screen.hasNotch)
            let big = islandSize(mode: .compact, view: .overview, nw: n.width, nh: n.height, hasNotch: screen.hasNotch,
                                 grown: true)
            let f0 = C.islandFrame(panel: C.panelSize, mode: .compact, view: .overview, notch: n, help: 0,
                                   hasNotch: screen.hasNotch)
            let f1 = C.islandFrame(panel: C.panelSize, mode: .compact, view: .overview, notch: n, help: 0,
                                   hasNotch: screen.hasNotch, grown: true)
            let others = [IslandMode.hidden, .peek, .expanded].allSatisfy {
                islandSize(mode: $0, view: .overview, nw: n.width, nh: n.height, hasNotch: screen.hasNotch, grown: true)
                    == islandSize(mode: $0, view: .overview, nw: n.width, nh: n.height, hasNotch: screen.hasNotch)
            }
            // Just under the grown island's edge (and its slack, with a notch): taken only while it's grown.
            let edge = CGPoint(x: f1.midX, y: f1.minY - (screen.hasNotch ? 6 : 0) + 1)
            let takesGrown = C.pointerInIsland(edge, island: f1, hasNotch: screen.hasNotch, open: false)
            let takesSmall = C.pointerInIsland(edge, island: f0, hasNotch: screen.hasNotch, open: false)
            let side = IslandRestingLayout(width: big.0, height: big.1).rightSide
            check(big.0 == small.0 + 8 && big.1 == small.1 + 4 && others && f1.size == CGSize(width: big.0, height: big.1)
                  && f1.midX == f0.midX && f1.maxY == f0.maxY && takesGrown && !takesSmall
                  && side.minX >= (big.0 + screen.width) / 2 && side.maxX <= big.0,
                  "with \(name), the resting island grows to \(Int(big.0)) × \(Int(big.1)) under the pointer, centred, and takes clicks to its new edge")
        }
    }

    /// The island's rules (IslandStateMachine) on a stopped clock: each input gives the time, and says when the rules
    /// next need the clock; nothing happens between those times.
    private static func rules(_ check: (Bool, String) -> Void) {
        var moves: [String] = []
        func fresh() -> IslandStateMachine {
            let m = IslandStateMachine()
            moves = []
            m.onTransition = { moves.append("\($0)→\($1)") }
            return m
        }
        let probe = IslandStateMachine()
        let fold = probe.homeToPetitDelay, hide = probe.petitToHiddenDelay, dwell = probe.peekHoverToOpen

        // Opening
        var m = fresh()
        var next = m.mouseEntered(at: 0)
        check(m.state == .petit && moves == ["hidden→petit"] && next == nil,
              "the pointer coming onto the hidden island shows the resting island; resting there needs no clock")
        next = m.click(at: 1)
        check(m.state == .home && moves.last == "petit→home" && next == nil,
              "a click on the resting island opens the card, with no fold while the pointer is in it")
        m = fresh()
        next = m.click(at: 0)
        check(m.state == .home && moves == ["hidden→home"] && next == fold,
              "a click opens even an island the rules never saw the pointer come into; the pointer away, it folds later")
        m = fresh()
        next = m.peekedExternally(at: 0)
        check(m.state == .peek && moves.isEmpty && next == nil, "a visit's peek: the app shows it, and nothing is timed")
        next = m.mouseEntered(at: 2)
        check(next == 2 + dwell && m.advance(to: 2 + dwell - 0.01) == 2 + dwell && m.state == .peek,
              "the pointer coming onto a peek: nothing before it has rested \(dwell) s")
        next = m.advance(to: 2 + dwell)
        check(m.state == .home && moves == ["peek→home"] && next == nil, "then the peek opens its card")
        m = fresh()
        _ = m.peekedExternally(at: 0)
        _ = m.mouseEntered(at: 0)
        next = m.mouseLeft(at: 0.3)
        check(next == 0.3 + fold && m.state == .peek,
              "leaving a peek before then doesn't open it; its fold starts instead")
        next = m.mouseEntered(at: 1)
        _ = m.advance(to: 1 + dwell - 0.01)
        let early = m.state
        _ = m.advance(to: 1 + dwell)
        check(next == 1 + dwell && early == .peek && m.state == .home, "coming back starts the rest over")
        m = fresh()
        _ = m.peekedExternally(at: 0)
        _ = m.click(at: 0.1)
        check(m.state == .home && moves == ["peek→home"], "a click on a peek opens it at once")

        // Ignoring
        m = fresh()
        _ = m.mouseEntered(at: 0)
        _ = m.click(at: 0)
        next = m.mouseLeft(at: 10)
        check(next == 10 + fold && m.advance(to: 10 + fold - 0.01) == 10 + fold && m.state == .home,
              "an open card the pointer left stays open until its fold time")
        next = m.advance(to: 10 + fold)
        check(m.state == .petit && moves.last == "home→petit" && next == 10 + fold + hide,
              "then it folds to the resting island, which hides in its own time if the pointer stays away")
        next = m.advance(to: 10 + fold + hide)
        check(m.state == .hidden && moves.last == "petit→hidden" && next == nil, "and then it hides")
        m = fresh()
        _ = m.mouseEntered(at: 0)
        _ = m.click(at: 0)
        _ = m.mouseLeft(at: 10)
        next = m.mouseEntered(at: 20)
        _ = m.advance(to: 1e6)
        check(next == nil && m.state == .home, "the pointer coming back before then keeps the card open")
        m = fresh()
        _ = m.peekedExternally(at: 0)
        _ = m.mouseEntered(at: 0)
        _ = m.mouseLeft(at: 0.2)
        _ = m.advance(to: 0.2 + fold)
        check(m.state == .petit && moves == ["peek→petit"], "a peek the pointer left folds the same way")
        m = fresh()
        _ = m.mouseEntered(at: 0)
        _ = m.click(at: 0)
        _ = m.mouseLeft(at: 0)
        next = m.advance(to: fold + hide + 5)
        check(m.state == .hidden && next == nil && moves == ["hidden→petit", "petit→home", "home→petit", "petit→hidden"],
              "one late check makes every step that came due, in order")
        m = fresh()
        next = m.openedExternally(at: 0)
        _ = m.advance(to: 1e6)
        check(m.state == .home && moves.isEmpty && next == nil,
              "the app opening the card (a visit) leaves its time to the visit: no fold while the pointer stays away")
        m = fresh()
        _ = m.mouseEntered(at: 0)
        _ = m.click(at: 0)
        _ = m.mouseLeft(at: 5)
        next = m.openedExternally(at: 6)
        check(next == nil, "the app opening the card stops a fold that was counting")

        // Closing
        m = fresh()
        _ = m.openedExternally(at: 0)
        next = m.collapse(at: 3)
        check(m.state == .petit && moves == ["home→petit"] && next == 3 + hide,
              "the app closing the card (Esc, ×, goodbye) shows the resting island at once; the pointer away, it hides later")
        m = fresh()
        _ = m.peekedExternally(at: 0)
        _ = m.collapse(at: 11.5)
        check(m.state == .petit && moves == ["peek→petit"], "an ignored peek tucks back in the same way")
        m = fresh()
        _ = m.mouseEntered(at: 0)
        _ = m.collapse(at: 1)
        check(m.state == .petit && moves == ["hidden→petit"], "closing an island that isn't open does nothing")

        // Hovering again after a close
        m = fresh()
        _ = m.mouseEntered(at: 0)
        _ = m.click(at: 0)
        next = m.collapse(at: 5)
        check(m.state == .petit && m.pointerInside && !m.hovering && next == nil,
              "the card closing under the pointer: the pointer is still there, but it isn't hovering")
        next = m.peekedExternally(at: 6)
        _ = m.advance(to: 60)
        check(next == nil && m.state == .peek, "so a peek arriving then doesn't open, however long the pointer rests")
        _ = m.mouseLeft(at: 61)
        next = m.mouseEntered(at: 62)
        _ = m.advance(to: 62 + dwell)
        check(next == 62 + dwell && m.state == .home, "once the pointer has left and come back, resting on it opens it")
        m = fresh()
        _ = m.mouseEntered(at: 0)
        next = m.peekedExternally(at: 5)
        _ = m.advance(to: 30)
        check(m.hovering == false && next == nil && m.state == .peek,
              "a peek arriving under a still pointer isn't hovered either: the island changed under it")
    }
}
