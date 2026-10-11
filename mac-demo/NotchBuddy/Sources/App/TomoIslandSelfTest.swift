import AppKit
import Carbon.HIToolbox
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

        whichScreen(check)
        shortcut(check)
        let external = NSRect(x: -1920, y: 200, width: 1920, height: 1080)
        let frame = C.panelFrame(on: external)
        check(frame.maxY == external.maxY && frame.midX == external.midX,
              "on a display left of and above the main one, the island sits at its top centre")
        let notch = IslandScreenGeometry(screenWidth: 1512, safeAreaTop: 32, auxiliaryLeftWidth: 664,
                                         auxiliaryRightWidth: 664)
        check(notch.hasNotch && notch.width == 184 && notch.height == 32, "on a notch screen the island fits the notch")
        let flat = IslandScreenGeometry(screenWidth: 1920, safeAreaTop: 0, auxiliaryLeftWidth: nil,
                                        auxiliaryRightWidth: nil)
        capsule(check, notch: notch, flat: flat)

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
        timeOnly.locale = tomoClockLocale(lang.learner.id)
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
        let bar = island(.compact, notch: flatNotch, hasNotch: false)
        check(takes(CGPoint(x: bar.midX, y: bar.midY), .compact, hasNotch: false, notch: flatNotch)
              && !takes(CGPoint(x: bar.midX, y: bar.minY - 3), .compact, hasNotch: false, notch: flatNotch),
              "no notch: the resting bar takes clicks on itself, not 3 pt below it")

        peek(check, notch: notch, flat: flat, island: island, takes: takes)
        motion(check, notch: notch, flat: flat)
        light(check)
        levelBar(check)
        music(check)
        macDictionary(check)
        rules(check)
        TomoGame.offerSelfTest(check)
        TomoPicture.selfTest(check)   // a dark picture gets a light disc on the card (#195)
        TomoStagePill.selfTest(check)   // each stage's colour reads at 5:1 or more on a light and a dark card (#195, #207)
        TomoLanding.selfTest(check)   // Words lands on Tomo's level until the learner scrolls or it holds still (#193)
        return ok
    }

    /// The word card's Mac dictionary (#198): only a dictionary in the learner's language, chosen from Dictionary's
    /// active ones by the languages their identifiers name, whichever this Mac has; without the list, the system's pick
    /// for a learner of their own language and no section for anyone else.
    private static func macDictionary(_ check: (Bool, String) -> Void) {
        typealias D = TomoMacDictionaries
        let wisdom = D.languages("com.apple.dictionary.ja-en.WISDOM"), daijirin = D.languages("com.apple.dictionary.ja.Daijirin")
        check(wisdom == ["ja", "en"] && daijirin == ["ja"] && D.languages("com.apple.dictionary.zh_CN-en.OCD") == ["zh", "en"]
              && D.languages("com.apple.dictionary.NOAD") == nil && D.languages("com.example.dictionary.ja-en") == nil,
              "a dictionary's languages come from Apple's identifier (ja-en, ja, zh_CN-en); none named or not Apple's: none")
        // Dictionary's own order on the owner's Mac: Super Daijirin (ja) ahead of Wisdom (ja-en).
        let mac = ["com.apple.dictionary.NOAD", "com.apple.dictionary.OAWT", "com.apple.dictionary.ja.Daijirin",
                   "com.apple.dictionary.ja-en.WISDOM", "com.apple.dictionary.AppleDictionary"]
        let japaneseOnly = Array(mac.prefix(3))
        check(D.choice(mac, target: "ja", learner: "en") == .dictionary(3)
              && D.choice(japaneseOnly, target: "ja", learner: "en") == .hidden
              && D.choice(nil, target: "ja", learner: "en") == .hidden,
              "an English speaker gets the Japanese-English dictionary even after Daijirin; with only Japanese ones, or "
              + "without the list, no section")
        check(D.choice(mac, target: "ja", learner: "ja") == .dictionary(2)
              && D.choice(["com.apple.dictionary.NOAD"], target: "ja", learner: "ja") == .system
              && D.choice(nil, target: "ja", learner: "ja") == .system,
              "a Japanese speaker gets Daijirin; with no Japanese one, or without the list, the system's pick")
        check(D.choice(mac, target: "es", learner: "en") == .hidden && D.choice(nil, target: "es", learner: "en") == .hidden,
              "a pair no dictionary fits (Spanish for an English speaker): no section")
        // A macOS that changes the unpublished calls: no list, and nothing that isn't a dictionary reaches them.
        var asked = 0
        let notAList = D.active("com.apple.dictionary.ja-en.WISDOM" as CFString) { _ in asked += 1; return nil }
        let strings = D.active(NSArray(array: mac)) { _ in asked += 1; return nil }
        let numbers = D.active(NSArray(array: [1, 2])) { _ in asked += 1; return NSNumber(value: 3) }
        let named = D.active(NSArray(array: [1])) { _ in "com.apple.dictionary.ja-en.WISDOM" as CFString }
        check(D.active(nil) { _ in nil } == nil && notAList == nil && strings == nil && numbers?.isEmpty == true
              && asked == 2 && named?.map(\.identifier) == ["com.apple.dictionary.ja-en.WISDOM"],
              "the unpublished calls returning something else: not an array of objects, no list; an identifier that "
              + "isn't a string, that dictionary left out")
    }

    /// Dancing to music (#130): the players' state from their notifications, when Tomo dances, and that a distributed
    /// notification reaches Tomodachi at once with its userInfo while AppKit holds an inactive app's (`TomoDistributed`;
    /// posted under a test name of ours, never a player's).
    private static func music(_ check: (Bool, String) -> Void) {
        typealias T = TomoCharacterView
        var m = TomoMusicState()
        let music = "com.apple.Music.playerInfo", spotify = "com.spotify.client.PlaybackStateChanged"
        m.heard(name: music, playerState: "Playing")
        let one = m.playing
        m.heard(name: spotify, playerState: "Paused")
        let otherPaused = m.playing
        m.heard(name: spotify, playerState: "Playing"); m.heard(name: music, playerState: "Stopped")
        let spotifyOn = m.playing
        m.heard(name: spotify, playerState: nil)
        let unknownState = m.playing
        m.heard(name: music, playerState: "Playing"); m.quit(bundle: "com.apple.Music")
        let quit = m.playing
        m.heard(name: "com.example.other.playerInfo", playerState: "Playing")
        check(one && otherPaused && spotifyOn && !unknownState && !quit && !m.playing,
              "music plays while Music or Spotify says \"Playing\"; paused, stopped, no state, quitting or another app: not")
        check(T.dance(playing: true, mode: .compact, quiet: false, today: .bounce) == .bounce
              && T.dance(playing: true, mode: .compact, quiet: false, today: .bonOdori) == .bonOdori
              && [IslandMode.expanded, .peek, .hidden].allSatisfy { T.dance(playing: true, mode: $0, quiet: false, today: .bounce) == nil }
              && T.dance(playing: true, mode: .compact, quiet: true, today: .bounce) == nil
              && T.dance(playing: false, mode: .compact, quiet: false, today: .bounce) == nil,
              "Tomo dances while music plays and it rests by the notch; visits (the card, the peek) and quiet hours win")

        let center = DistributedNotificationCenter.default(), wasSuspended = center.suspended
        let name = "co.serp.tomo.selftest.music", listener = TomoDistributed([name])
        var got: [AnyHashable: Any]?
        let sub = listener.publisher.sink { got = $0.userInfo }
        center.suspended = true                         // as AppKit holds them for an app that isn't active
        center.postNotificationName(Notification.Name(name), object: nil, userInfo: ["Player State": "Playing"],
                                    deliverImmediately: false)
        let until = Date().addingTimeInterval(2)
        while got == nil, Date() < until { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
        center.suspended = wasSuspended
        sub.cancel()
        check(got?["Player State"] as? String == "Playing",
              "a player's notification reaches Tomodachi at once, with its state, even while AppKit holds an inactive app's")
    }

    /// The shortcut to play (#130, Settings: TomoShortcut): what can be recorded, what's macOS's or every app's, how
    /// it's saved, and what a press does in each island state. A headless run can't press keys, or register a hot key.
    private static func shortcut(_ check: (Bool, String) -> Void) {
        typealias K = TomoShortcut
        let t = UInt32(kVK_ANSI_T), space = UInt32(kVK_Space)
        let ctrlOptT = K(keyCode: t, character: "T", carbonModifiers: K.control | K.option)
        check(K.record(keyCode: t, modifiers: K.control | K.option, character: "t") == .set(ctrlOptT)
              && K.record(keyCode: t, modifiers: K.option | K.command, character: "t")
                == .set(K(keyCode: t, character: "T", carbonModifiers: K.option | K.command)),
              "recording ⌃⌥T or ⌥⌘T sets it, named by its key")
        check(K.record(keyCode: t, modifiers: 0, character: "t") == .rejected(.needsModifier)
              && K.record(keyCode: t, modifiers: K.shift, character: "t") == .rejected(.needsModifier)
              && K.record(keyCode: UInt32(kVK_Option), modifiers: K.option, character: "") == .rejected(.needsModifier),
              "a key alone, with ⇧ alone, or a modifier key by itself is typing, not a shortcut")
        check(K.record(keyCode: t, modifiers: K.command, character: "t") == .rejected(.common)
              && K.record(keyCode: t, modifiers: K.command | K.shift, character: "t") == .rejected(.common)
              && K.record(keyCode: UInt32(kVK_ANSI_D), modifiers: K.command, character: "d") == .rejected(.common),
              "⌘ or ⌘⇧ with one key is every app's (and Tomodachi's own ⌘D, ⌘W), so it isn't offered")
        let system: [(UInt32, UInt32)] = [(space, K.command), (space, K.control), (space, K.control | K.option),
                                          (space, K.control | K.command), (UInt32(kVK_ANSI_Q), K.control | K.command),
                                          (UInt32(kVK_UpArrow), K.control), (UInt32(kVK_Escape), K.option | K.command)]
        check(system.allSatisfy {
                  let r = K.record(keyCode: $0.0, modifiers: $0.1, character: " ")
                  return r == .rejected(.system) || r == .rejected(.common)
              },
              "macOS's own are refused: Spotlight, switching input sources, emoji, the lock screen, Spaces, Force Quit")
        check(K.record(keyCode: UInt32(kVK_Escape), modifiers: 0, character: "") == .cancel
              && K.record(keyCode: UInt32(kVK_Delete), modifiers: 0, character: "") == .clear,
              "while recording, Esc keeps the old shortcut and Delete removes it")
        check(K(saved: ctrlOptT.saved) == ctrlOptT && K(saved: nil) == nil && K(saved: "") == nil
              && K(saved: "{\"keyCode\":17}") == nil
              && K(saved: K(keyCode: t, character: "T", carbonModifiers: K.shift).saved) == nil,
              "it's saved and read back; nothing saved, anything broken, or one without ⌘, ⌃ or ⌥ is no shortcut")
        let lang = TomoLanguages.shared
        let spaced = K(keyCode: space, character: " ", carbonModifiers: K.control | K.option | K.shift | K.command)
        check(ctrlOptT.label(lang) == "⌃⌥T" && spaced.label(lang) == "⌃⌥⇧⌘" + lang.learner("shortcut.space")
              && K(keyCode: UInt32(kVK_F5), character: "", carbonModifiers: K.control).label(lang) == "⌃F5",
              "it's shown as macOS shows shortcuts: ⌃⌥⇧⌘ then the key (\(ctrlOptT.label(lang)))")
        check(K.press(mode: .compact, leaving: false, hasKeyboard: false) == .open
              && K.press(mode: .hidden, leaving: false, hasKeyboard: false) == .open,
              "pressed while Tomo rests: it opens to play and takes the keyboard, as a click does")
        check(K.press(mode: .peek, leaving: false, hasKeyboard: false) == .open,
              "pressed while a visit peeks: the peek opens into its card, as a click on it does")
        check(K.press(mode: .expanded, leaving: false, hasKeyboard: false) == .takeKeyboard
              && K.press(mode: .expanded, leaving: false, hasKeyboard: true) == .close,
              "pressed while a visit's card is open: it takes the keyboard (Esc then closes); pressed again, it closes")
        check(K.press(mode: .expanded, leaving: true, hasKeyboard: true) == .open,
              "pressed while Tomo is being pulled up: it stays open")
        check(["settings.shortcut", "settings.shortcut.record", "settings.shortcut.recording", "settings.shortcut.clear",
               "settings.shortcut.needsModifier", "settings.shortcut.system", "settings.shortcut.common",
               "settings.shortcut.taken", "settings.shortcutNote", "shortcut.space"].allSatisfy { key in
                lang.learners.allSatisfy { !($0.strings[key] ?? "").isEmpty } },
              "every interface language has the shortcut's labels")
        typealias H = TomoHotKey
        check(H.registers(ctrlOptT, headless: false, paused: false) && !H.registers(ctrlOptT, headless: true, paused: false)
              && !H.registers(ctrlOptT, headless: false, paused: true) && !H.registers(nil, headless: false, paused: false)
              && !H.registers(K(keyCode: t, character: "T", carbonModifiers: K.command), headless: false, paused: false),
              "registered only when set and allowed: never in a headless run (it can't take the owner's), nor while Settings records")
    }

    /// Which screen Tomo lives on (#130, Settings: TomoScreenChoice): the notch screen, the main one, a display by name,
    /// or following the pointer, which moves only while the island is closed. A headless run can't plug in a monitor,
    /// so the rule is checked on made-up screens.
    private static func whichScreen(_ check: (Bool, String) -> Void) {
        typealias P = TomoScreenChoice
        // The main display (an external one, the menu bar's) left, the MacBook's built-in screen with its notch right.
        let external = TomoScreenInfo(hasNotch: false, name: "LG UltraFine", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440))
        let builtIn = TomoScreenInfo(hasNotch: true, name: "Built-in Retina Display",
                                     frame: CGRect(x: 2560, y: 0, width: 1512, height: 982))
        let side = TomoScreenInfo(hasNotch: false, name: "DELL U2723QE", frame: CGRect(x: -1920, y: 200, width: 1920, height: 1080))
        let three = [external, builtIn, side]
        check(P.pick(three, choice: .notch) == 1 && P.pick([external, side], choice: .notch) == 0
              && P.pick([], choice: .notch) == nil,
              "the notch screen (the default): the one with the notch, wherever it is; none (lid closed): the main display; no screen: nowhere")
        check(P.pick(three, choice: .main) == 0 && P.pick([builtIn, external], choice: .main) == 0,
              "the main screen: the one with the menu bar, even when another has the notch")
        check(P.pick(three, choice: .named("DELL U2723QE")) == 2 && P.pick(three, choice: .named("Studio Display")) == 1
              && P.pick([external, side], choice: .named("Studio Display")) == 0,
              "a display by name; while it isn't connected, the notch screen (else the main one)")
        let onSide = CGPoint(x: -500, y: 600), onBuiltIn = CGPoint(x: 3000, y: 500), offAll = CGPoint(x: 99_999, y: 0)
        check(P.pick(three, choice: .followMouse, pointer: onSide, current: 1, closed: true) == 2
              && P.pick(three, choice: .followMouse, pointer: onBuiltIn, current: 2, closed: true) == 1,
              "following the pointer: closed, the island goes to the screen the pointer is on")
        check(P.pick(three, choice: .followMouse, pointer: onSide, current: 1, closed: false) == 1,
              "following the pointer: open (a visit, a peek, folding), it stays where it is until it closes")
        check(P.pick(three, choice: .followMouse, pointer: onSide, current: 7, closed: false) == 2
              && P.pick(three, choice: .followMouse, pointer: offAll, current: 0, closed: true) == 0
              && P.pick(three, choice: .followMouse, pointer: offAll, current: nil, closed: true) == 1,
              "following the pointer: its screen gone, to the pointer's; the pointer on none, it stays, else the notch screen")
        let saved: [P] = [.notch, .main, .followMouse, .named("LG UltraFine")]
        check(saved.allSatisfy { P(raw: $0.raw) == $0 } && P(raw: nil) == .notch && P(raw: "display:") == .notch
              && P(raw: "somewhere") == .notch,
              "the choice is saved and read back; nothing saved, or anything unknown, is the notch screen")
        let options = P.options(connected: ["LG UltraFine", "Built-in Retina Display"], saved: .named("Studio Display"))
        check(options.map(\.choice) == [.notch, .main, .named("LG UltraFine"), .named("Built-in Retina Display"),
                                        .named("Studio Display"), .followMouse]
              && options.filter(\.away).map(\.choice) == [.named("Studio Display")]
              && P.options(connected: ["A", "A"], saved: .notch).count == 4,
              "Settings offers the notch screen, the main one, each display, and following the pointer; a saved display that's away stays, marked")
        let lang = TomoLanguages.shared
        check(["settings.screen", "settings.screen.notch", "settings.screen.main", "settings.screen.mouse",
               "settings.screen.away", "settings.screenNote"].allSatisfy { key in
                lang.learners.allSatisfy { !($0.strings[key] ?? "").isEmpty } }
              && lang.learner("settings.screen.away", ["name": "X"]).contains("X"),
              "every interface language names the choices")
    }

    /// A Mac without a notch (#130): the island is a capsule 4 pt below the top of the screen, rounded all round, with
    /// the same two sides, and it never hides Tomo. Replaces the 80 × 24 strip.
    private static func capsule(_ check: (Bool, String) -> Void, notch: IslandScreenGeometry, flat: IslandScreenGeometry) {
        typealias C = IslandWindowController
        typealias G = IslandScreenGeometry
        let n = CGSize(width: flat.width, height: flat.height)
        let rest = islandSize(mode: .compact, view: .overview, nw: n.width, nh: n.height, hasNotch: false)
        check(!flat.hasNotch && rest == (300, 30) && G.top(hasNotch: false) == 4 && G.top(hasNotch: true) == 0,
              "without a notch the resting island is a 300 × 30 capsule, 4 pt below the top of the screen (a notch's is glued to it)")
        let frame = C.islandFrame(panel: C.panelSize, mode: .compact, view: .overview, notch: n, help: 0, hasNotch: false)
        let open = C.islandFrame(panel: C.panelSize, mode: .expanded, view: .overview, notch: n, help: 0, hasNotch: false)
        let peek = C.islandFrame(panel: C.panelSize, mode: .peek, view: .overview, notch: n, help: 0, hasNotch: false)
        check([frame, open, peek].allSatisfy { $0.maxY == C.panelSize.height - 4 && $0.midX == C.panelSize.width / 2 },
              "resting, peeking or open, it hangs 4 pt below the top, centred, and its click area with it")
        let grownH = rest.1 + IslandRestingLayout.hoverGrowth.height
        check(G.corners(mode: .compact, height: 30, hasNotch: false) == (15, 15)
              && G.corners(mode: .compact, height: grownH, hasNotch: false) == (grownH / 2, grownH / 2),
              "resting, it's fully rounded, under the pointer too")
        check([IslandMode.peek, .expanded].allSatisfy { G.corners(mode: $0, height: 200, hasNotch: false) == (22, 22) },
              "peeking or open, all four corners are rounded, 22 pt")
        check(G.corners(mode: .compact, height: 32, hasNotch: true) == (0, 14)
              && G.corners(mode: .expanded, height: 208, hasNotch: true) == (0, 22),
              "under a notch nothing changes: square on top, 14 pt below resting, 22 pt open")
        check(C.shownMode(.hidden, hasNotch: false) == .compact && C.shownMode(.hidden, hasNotch: true) == .hidden
              && [IslandMode.compact, .peek, .expanded].allSatisfy { C.shownMode($0, hasNotch: false) == $0 },
              "it never hides Tomo: without a notch, hiding rests as the capsule instead; under a notch it hides as before")
        let (bx, by, d, alpha) = botPosition(mode: .compact, view: .overview, islandW: rest.0, islandH: rest.1,
                                             hasNotch: false)
        let side = IslandRestingLayout(width: rest.0, height: rest.1).rightSide
        let r = rest.1 / 2   // the rounded ends
        check(alpha == 1 && bx - d / 2 >= r / 2 && by - d / 2 >= 0 && by + d / 2 <= rest.1
              && side.maxX <= rest.0 - r / 2 && side.minX >= bx + d / 2,
              "small Tomo sits on its left and the right side on its right, clear of the rounded ends")
        let hidden = botPosition(mode: .hidden, view: .overview, islandW: rest.0, islandH: rest.1, hasNotch: false)
        check(hidden.0 == bx && hidden.1 == by && hidden.3 == 1, "even if asked to hide, Tomo stays where it rests")
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
                let slot = TomoWordFlight.cardWordSlot(panelWidth: C.panelSize.width, hasNotch: screen.hasNotch)
                let top = IslandScreenGeometry.top(hasNotch: screen.hasNotch)
                let card = CGRect(x: (C.panelSize.width - IslandConst.expandedWidth) / 2, y: top,
                                  width: IslandConst.expandedWidth, height: IslandConst.layout(.overview).height)
                let barInPanel = bar.offsetBy(dx: (C.panelSize.width - w) / 2, dy: top)
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

    /// The coloured light that tells the moment (#137, effect 3): TomoCore's rules, which moment each island shows,
    /// how it comes and goes, and that the card's light and the island's come from the same Tomo.
    private static func light(_ check: (Bool, String) -> Void) {
        TomoMoment.selfTest(check)
        TomoGlance.selfTest(check)
        typealias L = TomoIslandLight
        let win = TomoMoment.card(phase: .right, outcome: .win(counted: true))
        check(L.moment(mode: .compact, view: .overview, card: nil, somethingCounts: true) == .waiting
              && L.moment(mode: .compact, view: .overview, card: nil, somethingCounts: false) == nil
              && L.moment(mode: .hidden, view: .overview, card: win, somethingCounts: true) == nil,
              "resting, the island glows amber around small Tomo while something counts, and is dark when nothing does")
        check(L.moment(mode: .peek, view: .overview, card: nil, somethingCounts: true) == .waiting,
              "a peek's bar glows amber: a visit offered, Tomo waiting to play")
        check(L.moment(mode: .expanded, view: .overview, card: win, somethingCounts: true) == .win
              && L.moment(mode: .expanded, view: .overview, card: nil, somethingCounts: true) == nil
              && L.moment(mode: .expanded, view: .confused, card: win, somethingCounts: true) == nil,
              "open, the island shows the card's moment around it (none while asking or on the dizzy card)")
        typealias M = TomoMomentLight
        check(M.fade(on: true, reduceMotion: false) < M.fade(on: false, reduceMotion: false)
              && M.fade(on: false, reduceMotion: false) <= 1
              && M.fade(on: true, reduceMotion: true) <= 0.15 && M.fade(on: false, reduceMotion: true) <= 0.15,
              "the light comes quickly and goes more slowly; under Reduce Motion both take 0.15 s or less")
        check(M.ripples(from: nil, to: .win, reduceMotion: false) && M.ripples(from: .win, to: .grown, reduceMotion: false)
              && !M.ripples(from: nil, to: .waiting, reduceMotion: false) && !M.ripples(from: .win, to: .win, reduceMotion: false)
              && !M.ripples(from: .win, to: nil, reduceMotion: false) && !M.ripples(from: nil, to: .win, reduceMotion: true)
              && M.rippleDuration <= 2,
              "a win, practice or level-up ripples out from Tomo once (under 2 s); waiting, an end and Reduce Motion don't")
        let (bx, by, _, _) = botPosition(mode: .expanded, view: .overview, islandW: IslandConst.expandedWidth,
                                         islandH: IslandConst.layout(.overview).height)
        let cardOrigin = CGPoint(x: 10, y: 8 + 34 + TomoGrid.levelBar + TomoGrid.levelBarGap)   // IslandContentView, TomoView
        check(bx - cardOrigin.x == TomoGrid.tomoCenter.x && by - cardOrigin.y == TomoGrid.tomoCenter.y,
              "the card's light and the island's around it come from where Tomo sits, so their ripples travel as one")
    }

    /// The level bar coming alive (#137, effect 7): what a change to the bar does, the +1's way into it, and where
    /// the fill ends.
    private static func levelBar(_ check: (Bool, String) -> Void) {
        typealias B = TomoBarMotion
        check(B.move(from: 0.2, to: 0.3, counted: true, reduceMotion: false) == .fly
              && B.move(from: 0.2, to: 0.3, counted: true, reduceMotion: true) == .glow,
              "a counted answer that moves the bar sends a +1 flying into it; under Reduce Motion, a glow only")
        check(B.move(from: 0.2, to: 0.2, counted: true, reduceMotion: false) == .plain
              && B.move(from: 0.2, to: 0.3, counted: false, reduceMotion: false) == .plain
              && B.move(from: 1, to: 0, counted: true, reduceMotion: false) == .plain,
              "no +1 when the bar doesn't move, for anything but a counted answer, or when a level is done and it empties")
        check(B.lands <= 1 && B.glow(reduceMotion: false) <= 2 && B.glow(reduceMotion: true) < B.glow(reduceMotion: false)
              && B.sheen <= 2 && B.birthdayFill(reduceMotion: false) <= 2 && B.birthdayFill(reduceMotion: true) <= 0.15,
              "the bar's moments are short (the +1 lands in \(B.lands) s, a glow lasts \(B.glow(reduceMotion: false)) s); "
              + "under Reduce Motion the glow is briefer and a birthday's colour fades in within 0.15 s")
        let w = TomoGrid.content.width - 28
        let track = TomoGrowthBar.trackWidth(w)
        check(TomoGrowthBar.filledWidth(w, progress: 0) == 0
              && abs(TomoGrowthBar.filledWidth(w, progress: (1 - TomoProgress.goalShare) / 2) - track / 2) < 0.001
              && TomoGrowthBar.filledWidth(w, progress: 0.99) == track && TomoGrowthBar.filledWidth(w, progress: 1) == w,
              "the +1 aims where the fill ends: along the track, the track's end before the goal, the whole bar once done")
        // A +1 from the picture card's result row into a half-full bar, in TomoView's coordinates.
        let from = CGPoint(x: 230, y: 12 + 72), to = CGPoint(x: 14 + TomoGrowthBar.filledWidth(w, progress: 0.45), y: 2.5)
        let f = TomoPlusOne(from: from, to: to)
        let path = stride(from: 0.0, through: B.flight, by: B.flight / 60).map(f.point(at:))
        let island = CGRect(x: -10, y: -42, width: IslandConst.expandedWidth, height: IslandConst.layout(.overview).height)
        check(f.point(at: 0) == from && abs(f.point(at: B.flight).x - to.x) < 0.001 && abs(f.point(at: B.flight).y - to.y) < 0.001
              && path.allSatisfy { island.contains($0) } && (path.map(\.y).min() ?? 0) < to.y,
              "the +1 leaves the result, stays in the island, and comes down into the bar's fill end from above")
        check(f.opacity(at: 0) == 1 && f.opacity(at: B.flight) == 0 && f.scale(at: B.flight) < f.scale(at: 0),
              "it shrinks as it goes and melts into the bar as it lands")
    }

    /// Tomo travelling between the island's states (#137, effect 1: TomoTravel): which move a change is, and each move's
    /// path, squash and timing, sampled at 240 Hz.
    private static func travel(_ check: (Bool, String) -> Void) {
        typealias V = TomoTravel
        check(V.style(modeChanged: true, closing: false, arrived: false, firstDrawn: true, reduceMotion: false) == .open
              && V.style(modeChanged: true, closing: true, arrived: false, firstDrawn: true, reduceMotion: false) == .close
              && V.style(modeChanged: false, closing: false, arrived: false, firstDrawn: true, reduceMotion: false) == .settle,
              "a click opening the card, or a peek opening into it, travels in; tucking in travels back; a small change settles")
        check(V.style(modeChanged: true, closing: false, arrived: true, firstDrawn: true, reduceMotion: false) == nil
              && V.style(modeChanged: true, closing: false, arrived: false, firstDrawn: false, reduceMotion: false) == nil,
              "a visit arriving from the notch doesn't travel (it drips in, #142), and nor does Tomo's first frame")
        check(V.style(modeChanged: true, closing: false, arrived: false, firstDrawn: true, reduceMotion: true) == .fade
              && V.style(modeChanged: true, closing: true, arrived: false, firstDrawn: true, reduceMotion: true) == .fade
              && V.style(modeChanged: false, closing: false, arrived: false, firstDrawn: true, reduceMotion: true) == nil,
              "under Reduce Motion there's no travel: a quick fade out and in, and nothing at all for a small change")
        let rest = TomoSpot(center: CGPoint(x: 40, y: 16), diameter: 20, opacity: 1)
        let peek = TomoSpot(center: CGPoint(x: TomoPeekLayout.tomoCenterX, y: 44), diameter: 56, opacity: 1)
        let card = TomoSpot(center: CGPoint(x: 66, y: 126), diameter: 72, opacity: 1)
        func samples(_ v: V) -> [TomoPose] { stride(from: 0.0, through: v.duration + 0.05, by: 1.0 / 240).map(v.pose(at:)) }
        func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        for (from, name) in [(rest, "beside the notch"), (peek, "the peek")] {
            let v = V(from: from, to: card, style: .open), path = samples(v)
            let span = dist(from.center, card.center)
            let over = path.map { dist($0.spot.center, from.center) - span }.max() ?? 0
            let steps = zip(path, path.dropFirst()).map { dist($0.spot.center, $1.spot.center) }.max() ?? 0
            check(path.first?.spot == from && v.pose(at: v.duration) == TomoPose(spot: card) && over > 0 && over < span * 0.08
                  && steps < span * 0.05,
                  "from \(name) into the card: one Tomo on a spring, overshooting \(Int(over / span * 100))%, never jumping, landing exactly")
            let sy = path.map(\.sy)
            check((sy.max() ?? 1) > 1.1 && (sy.min() ?? 1) < 0.95 && abs(v.pose(at: v.duration - 0.01).sy - 1) < 0.02,
                  "from \(name), it stretches as it goes and wobbles as it lands, still by the end (\(V.openDuration) s)")
        }
        let back = V(from: card, to: rest, style: .close), path = samples(back)
        let foldAt = back.pose(at: V.fold)
        // The island folds on the same curve (IslandContainer's close): Tomo's bottom stays inside it all the way.
        let inside = stride(from: 0.0, through: V.fold, by: 1.0 / 240).allSatisfy { t in
            let f = V.foldCurve(t / V.fold), p = back.pose(at: t).spot
            return p.center.y + p.diameter / 2 <= 208 + (32 - 208) * f + 0.5 && p.center.x <= 640 + (345 - 640) * f
        }
        check(foldAt.spot.center == rest.center && path.allSatisfy { (0.85...1.2).contains($0.sy) } && inside
              && back.pose(at: back.duration) == TomoPose(spot: rest),
              "tucking in, it's back beside the notch when the island has folded (\(V.fold) s), inside it all the way, with a small wobble")
        let fade = V(from: card, to: rest, style: .fade)
        check(fade.pose(at: 0).spot == card && fade.pose(at: V.fadeHalf - 0.001).spot.opacity < 0.02
              && fade.pose(at: V.fadeHalf + 0.001).spot.center == rest.center && fade.pose(at: fade.duration) == TomoPose(spot: rest)
              && samples(fade).allSatisfy { $0.sx == 1 && $0.sy == 1 } && fade.duration <= 0.25,
              "under Reduce Motion: out where it was, in where it goes, in \(fade.duration) s, never moving or squashing")
        let hover = V(from: rest, to: TomoSpot(center: CGPoint(x: 40, y: 18), diameter: 20, opacity: 1), style: .settle)
        check(samples(hover).allSatisfy { $0.sx == 1 && $0.sy == 1 }, "a small move within a state settles without squashing")
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
        check(T.move(from: .expanded, to: .compact, arriving: false) == .none
              && T.move(from: .peek, to: .compact, arriving: false) == .none
              && !C.foldWaits(from: .expanded, to: .compact, reduceMotion: false)
              && !C.foldWaits(from: .peek, to: .compact, reduceMotion: false),
              "the card or the peek tucking in: Tomo travels back beside the notch as the island folds, so nothing waits")
        check(T.move(from: .expanded, to: .hidden, arriving: false) == .pullUp
              && C.foldWaits(from: .expanded, to: .hidden, reduceMotion: false)
              && !C.foldWaits(from: .expanded, to: .hidden, reduceMotion: true)
              && T.backAfter(pulledUp: true) >= 0.34 && T.backAfter(pulledUp: false) >= C.pullUpTime,
              "folding away with nowhere to rest (hidden), Tomo is pulled up into the notch first (not under Reduce Motion)")
        travel(check)
        check(T.saysHello(greeted: false, waking: false, mode: .compact) && T.saysHello(greeted: false, waking: false, mode: .expanded)
              && T.saysHello(greeted: false, waking: false, mode: .peek) && !T.saysHello(greeted: false, waking: false, mode: .hidden)
              && !T.saysHello(greeted: true, waking: false, mode: .compact) && T.saysHello(greeted: true, waking: true, mode: .compact)
              && !T.saysHello(greeted: true, waking: true, mode: .hidden),
              "Tomo says hello the first time it shows (resting, the launch visit's card or peek) and when the Mac wakes, never hidden")
        check(T.wearsBadges(.compact) && !T.wearsBadges(.peek) && !T.wearsBadges(.expanded) && !T.wearsBadges(.hidden),
              "small Tomo wears its badges resting beside the notch, not in the peek or the card")
        check(T.weather(mode: .expanded, view: .overview, today: .snow) == .snow
              && [IslandMode.compact, .peek, .hidden].allSatisfy { T.weather(mode: $0, view: .overview, today: .snow) == nil }
              && T.weather(mode: .expanded, view: .confused, today: .petals) == nil
              && T.weather(mode: .expanded, view: .overview, today: nil) == nil,
              "the season's weather falls only in Tomo's card: never resting by the notch, in the peek or the dizzy card")
        // Its badge stays in the left ear, left of the notch and below the screen's top edge, at every age, in the room
        // the canvas leaves right of its frame (BotPlacement's canvas: the diameter / 0.6, 72 pt of room above). Its call
        // glow fits the canvas's room on every side, so no edge of the canvas cuts it.
        var fits: [String] = [], glowCut: [String] = []
        for (screen, name) in [(notch, "a notch"), (flat, "no notch")] {
            let (w, h) = islandSize(mode: .compact, view: .overview, nw: screen.width, nh: screen.height)
            let (cx, cy, d, _) = botPosition(mode: .compact, view: .overview, islandW: w, islandH: h, hasNotch: screen.hasNotch)
            let side = d / 0.6, overhang: CGFloat = 72
            let origin = CGPoint(x: cx - side / 2, y: cy - overhang / 2 - (side + overhang) / 2)   // the canvas, in the island
            for look in [TomoLook.mascot] + (0..<12).map({ TomoLook(seed: "badge-\($0)") }) {
                for age in 0..<TomoLook.ages {
                    let blob = TomoBlob(look: look, material: .own)
                    blob.particleOverhang = overhang
                    blob.setGrowth(CGFloat(age))
                    let f = blob.badgeFrame(size: CGSize(width: side, height: side + overhang))
                    let inIsland = f.offsetBy(dx: origin.x, dy: origin.y)
                    let room = T.canvasRoom(width: side)
                    if f.maxX > side + room.right || inIsland.maxX > (w - screen.width) / 2 - IslandRestingLayout.notchClearance
                        || inIsland.minY < 0 || inIsland.minX < cx {
                        fits.append("\(name) age \(age): \(inIsland)")
                    }
                    // The glow: 1.8 R round Tomo's middle (TomoBlob.drawCallGlow), R = 0.27 of the frame's width.
                    let R = side * 0.27, r = 1.8 * R * look.form(age).scale
                    let mid = CGPoint(x: side / 2, y: (side + overhang) / 2 + overhang / 2 + R * 0.1)
                    if mid.x - r < -room.left || mid.x + r > side + room.right || mid.y + r > side + overhang + room.bottom {
                        glowCut.append("\(name) age \(age)")
                    }
                }
            }
        }
        check(fits.isEmpty, "small Tomo's badge fits the left ear beside it at every age, with a notch and without"
              + (fits.isEmpty ? "" : " (\(fits.prefix(3).joined(separator: "; ")))"))
        check(glowCut.isEmpty, "small Tomo's call glow fits its canvas on every side at every age, so no edge cuts it"
              + (glowCut.isEmpty ? "" : " (cut: \(glowCut.prefix(3).joined(separator: "; ")))"))
        check(C.foldWaits(from: .expanded, to: .hidden, reduceMotion: false)
              && C.foldWaits(from: .peek, to: .hidden, reduceMotion: false)
              && !C.foldWaits(from: .expanded, to: .hidden, reduceMotion: true)
              && !C.foldWaits(from: .peek, to: .expanded, reduceMotion: false)
              && !C.foldWaits(from: .compact, to: .hidden, reduceMotion: false) && C.pullUpTime == 0.45,
              "folding away (hidden), the card or the peek waits 0.45 s while Tomo is pulled up out of it (under Reduce Motion it folds at once)")
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
