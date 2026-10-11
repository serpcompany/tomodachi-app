import XCTest
import TomoCore

// MARK: - The iPhone's key journeys, without a human (#55)
//
// Each test launches the app on a fresh data folder of its own (TOMO_DATA_DIR, in the test runner's temporary folder,
// never a learner's data), silent (TOMO_HEADLESS), in English, with the first run skipped (TOMO_ONBOARDING=0). Saved
// progress a journey needs is written into that folder through TomoCore's own store before launch (`TomoSeed`). Text is
// read from the interface pack, so a test checks what a learner sees. Run headless: `xcodebuild test` with the Pull
// Request test plan on a simulator of your own (docs/verification.md).

@MainActor
final class TomodachiUITests: XCTestCase {
    private var app: XCUIApplication!
    private var ui: LearnerPack { TomoLanguages.shared.learners.first { $0.id == "en" }! }

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        app?.terminate()
    }

    /// Launches the app on `folder` (a fresh one if nil), at a tab (`play`, `tomo`, `words`, `together` or
    /// `settings`), with any more flags in `env`, and returns once it shows that tab, chosen, with no first run: the
    /// sign that it came up with this test's settings. Launched while the simulator was still installing it, it once
    /// came up without them (the first run, on Play) (#203); then it's launched again, once, and the relaunch is
    /// recorded with what it came up on, so a start that's sometimes wrong shows in every run's log. A second wrong
    /// start fails. XCUITest still sees the tabs under the first run, so the check looks for the first run itself.
    /// `arguments`: the app's launch arguments, such as a text size.
    private func launch(_ folder: URL? = nil, tab: String? = nil, env: [String: String] = [:],
                        arguments: [String] = []) {
        let dir = folder ?? TomoSeed.folder(), want = tab ?? "play"
        for attempt in 1...2 {
            app = XCUIApplication()
            app.launchArguments = arguments
            app.launchEnvironment = ["TOMO_DATA_DIR": dir.path, "TOMO_HEADLESS": "1", "TOMO_LEARNER": "en",
                                     "TOMO_TARGET": "ja", "TOMO_ONBOARDING": "0"].merging(env) { $1 }
            if let tab { app.launchEnvironment["TOMO_OPEN_WINDOW"] = tab }
            app.launch()
            let shown = app.tabBars.buttons[ui("screen.\(want)")]
            let up = app.wait(for: .runningForeground, timeout: 60) && shown.waitForExistence(timeout: 30)
            let firstRun = app.otherElements["firstRun"].exists
            if up, shown.isSelected, !firstRun { return }
            let chosen = app.tabBars.buttons.matching(NSPredicate(format: "selected == true")).firstMatch
            let came = firstRun ? "in the first run" : !up ? "without its tabs"
                : chosen.exists ? "on \(chosen.label)" : "on no tab"
            if attempt == 2 {
                XCTFail("the app opens at \(want) with the test's settings: it came up \(came), twice")
                return
            }
            record("relaunched: came up \(came), not at \(want) with the test's settings", screenshot: app.screenshot())
            app.terminate()
        }
    }

    /// Records what a passing journey would otherwise hide (a relaunch, a second press): an activity in the result
    /// bundle, with a screenshot kept even when the test passes, and a line in the test log.
    private func record(_ what: String, screenshot: XCUIScreenshot? = nil) {
        print("\(name) \(what)")
        XCTContext.runActivity(named: what) { activity in
            guard let screenshot else { return }
            let shot = XCTAttachment(screenshot: screenshot)
            shot.lifetime = .keepAlways
            activity.add(shot)
        }
    }

    private var tomo: XCUIElement { app.descendants(matching: .any)["tomo"] }

    /// The largest text size (AX5), as launch arguments.
    private let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    /// What on the screen is wider than the phone, if anything: a text, button, slider or segmented control past
    /// either edge, scrolled out of sight too, but not in a row that scrolls sideways (Together's earlier postcards).
    private func wider() throws -> String? {
        let window = app.windows.firstMatch.frame
        var wider: [String] = []
        func look(_ e: XCUIElementSnapshot, scrolls: Int) {
            let f = e.frame
            if [.staticText, .button, .slider, .segmentedControl].contains(e.elementType),
               f.minX < window.minX - 0.5 || f.maxX > window.maxX + 0.5 {
                wider.append("'\(e.label)' at x \(Int(f.minX))…\(Int(f.maxX))")
            }
            let inner = scrolls + (e.elementType == .scrollView ? 1 : 0)
            if inner < 2 { e.children.forEach { look($0, scrolls: inner) } }
        }
        look(try app.snapshot(), scrolls: 0)
        return wider.isEmpty ? nil : "\(wider.count) are, " + wider.prefix(6).joined(separator: ", ")
    }

    // MARK: Journeys

    /// Launch: a brand-new Tomo opens on the play screen, alive, at Lv 1, asking its first word.
    func testLaunchShowsTomoAskingItsFirstWord() {
        launch()
        XCTAssertTrue(tomo.waitForExistence(timeout: 20), "Tomo is on the play screen")
        XCTAssertTrue(app.staticTexts[ui("level", ["n": "1"])].waitForExistence(timeout: 5), "Lv 1 in the header")
        XCTAssertTrue(app.buttons["👋"].waitForExistence(timeout: 10), "the first word's picture choices")
    }

    /// A picture round: a wrong picture is a Miss, and the round stays for another try; the right one is a Win +1.
    func testAPictureRoundWrongThenRight() {
        launch()
        let right = app.buttons["👋"], wrong = app.buttons["🚃"]
        XCTAssertTrue(right.waitForExistence(timeout: 20), "the first word (bye-bye) asks for 👋")
        wrong.tap()
        XCTAssertTrue(app.staticTexts[ui("outcome.loss")].waitForExistence(timeout: 5), "a wrong picture is a Miss")
        XCTAssertTrue(right.isHittable, "the round stays, for another try")
        right.tap()
        XCTAssertTrue(app.staticTexts[ui("outcome.win")].waitForExistence(timeout: 5), "the right picture is a Win +1")
    }

    /// The practice offer: when nothing counts, Tomo rests with Practice as a choice; picking it starts practice, which
    /// the header says lasts until something counts.
    func testThePracticeOffer() {
        launch(TomoSeed.levelOneJustLearned())
        let practice = app.buttons[ui("practice.start")]
        XCTAssertTrue(practice.waitForExistence(timeout: 20), "Tomo rests and offers Practice")
        XCTAssertTrue(app.staticTexts[ui("rest.practiceNote")].exists, "it says practice won't move the bar")
        practice.tap()
        let chip = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@",
                                                        ui("practice.chip", ["time": ""]).trimmingCharacters(in: .whitespaces)))
        XCTAssertTrue(chip.firstMatch.waitForExistence(timeout: 10), "the header says Practice until …")
    }

    /// Together: today's line, the word garden, Tomo's week and Tomo's diary, for a Tomo that played today.
    func testTheTogetherScreen() {
        launch(TomoSeed.levelOneJustLearned(), tab: "together")
        XCTAssertTrue(app.staticTexts[ui("garden.title")].waitForExistence(timeout: 20), "the word garden")
        let today = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", ui.counted("today.answers", 10)))
        XCTAssertTrue(today.firstMatch.exists, "today's line counts the 10 answers")
        XCTAssertTrue(app.staticTexts[ui("postcard.title")].exists, "Tomo's week")
        XCTAssertTrue(app.staticTexts[ui("diary.title")].exists, "Tomo's diary")
    }

    /// Together at the largest text (AX5, #216): no text, button or slider on the screen is wider than the phone, the
    /// range picker is a menu and Export is under Copy recap. Before, the row of Copy recap and Export, which didn't
    /// wrap, made the whole screen wider, cutting every line at both edges. Then the menu, on Since we met (the longest
    /// range): it changes the garden, and its label is whole (the stock menu picker wrapped it and cut both lines).
    func testTogetherFitsTheLargestText() throws {
        launch(TomoSeed.levelOneJustLearned(), tab: "together", arguments: largestText)
        XCTAssertTrue(app.staticTexts[ui("garden.title")].waitForExistence(timeout: 20), "the word garden")
        let window = app.windows.firstMatch.frame
        let first = try wider()
        XCTAssertNil(first, "nothing is wider than the phone (0…\(Int(window.maxX))): \(first ?? "")")
        XCTAssertFalse(app.segmentedControls.firstMatch.exists, "the range picker is a menu, not a segmented control")
        let copy = app.buttons[ui("garden.copy")], export = app.buttons[ui("export.button")]
        XCTAssertTrue(copy.exists && export.exists, "Copy recap and Export")
        XCTAssertGreaterThanOrEqual(export.frame.minY, copy.frame.maxY, "Export is under Copy recap")

        // The menu, showing This week, scrolled into reach (half a screen at a time, from the edge, past no plant).
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", ui("garden.title"))).firstMatch
        let shows = { (range: String) in "\(picker.label) \(picker.value as? String ?? "")".contains(range) }
        XCTAssertTrue(picker.exists, "the range picker's menu")
        for _ in 0..<8 where !picker.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.6))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.35)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(picker.isHittable, "the range picker's menu can be tapped")
        XCTAssertTrue(shows(ui("garden.range.week")), "the menu shows This week: '\(picker.label)' '\(picker.value ?? "")'")
        let order = app.staticTexts[ui("garden.order")]
        XCTAssertFalse(order.exists, "This week's garden says what grew, not the order it was planted in")
        picker.tap()
        let all = app.buttons[ui("garden.range.all")].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 5), "the menu offers Since we met")
        all.tap()
        XCTAssertTrue(order.waitForExistence(timeout: 5), "Since we met shows every word, in the order planted")
        XCTAssertTrue(shows(ui("garden.range.all")), "the menu shows Since we met: '\(picker.label)' '\(picker.value ?? "")'")
        // Its label is the whole text, inside the menu's button and the window, not cut above, below or at the side.
        func texts(_ e: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
            (e.elementType == .staticText ? [e] : []) + e.children.flatMap(texts)
        }
        let button = picker.frame, label = texts(try picker.snapshot()).first
        XCTAssertEqual(label?.label, ui("garden.range.all"), "the menu's label")
        if let text = label?.frame {
            XCTAssertTrue(button.insetBy(dx: -0.5, dy: -0.5).contains(text) && window.contains(button),
                          "Since we met is whole: its label at \(text) in the menu at \(button)")
        }
        let after = try wider()
        XCTAssertNil(after, "on Since we met too, nothing is wider than the phone: \(after ?? "")")
    }

    /// Tomo and Words at the largest text (AX5, #213, #233), in one launch: nothing on either screen is wider than the
    /// phone. On Tomo, the age beside or over the level, the lines and the play button with its icon beside it; on
    /// Words at Lv 154, each word at its largest beside its picture, over meanings as long as "congratulations!".
    /// Every word and phrase in every pack is `TomoLargeTextCheck`'s; this is the screens' own layout.
    func testTomoAndWordsFitTheLargestText() throws {
        launch(TomoSeed.atLevel(154), tab: "tomo", arguments: largestText)
        XCTAssertTrue(app.buttons[ui("tomo.play")].waitForExistence(timeout: 20), "Play with Tomo")
        let window = app.windows.firstMatch.frame
        let onTomo = try wider()
        XCTAssertNil(onTomo, "on Tomo, nothing is wider than the phone (0…\(Int(window.maxX))): \(onTomo ?? "")")
        app.tabBars.buttons[ui("screen.words")].tap()
        expectWordsAtLevel(154)
        let onWords = try wider()
        XCTAssertNil(onWords, "on Words at Lv 154, nothing is wider than the phone (0…\(Int(window.maxX))): \(onWords ?? "")")
    }

    /// Words opens at Tomo's level (#193): the level's header and its first word show under the stage chips. The rows
    /// are lazy, so the jump to Lv 14 lands on estimated heights for the 13 levels above it; it once left the header
    /// scrolled away under the chips. Reading the screen lays the list out anew, which once moved it on to Lv 16 (#218).
    func testWordsOpensAtTomosLevel() {
        launch(TomoSeed.atLevel(14), tab: "words")
        expectWordsAtLevel(14)
    }

    /// Words lands on Tomo's level when you switch to it too (#218): the tab is made on its first tap, in a screen
    /// that's already laid out, where SwiftUI can put the list back at Lv 1 after the jump (as on the Mac).
    func testWordsLandsOnTomosLevelFromPlay() {
        launch(TomoSeed.atLevel(14))
        app.tabBars.buttons[ui("screen.words")].tap()
        expectWordsAtLevel(14)
    }

    /// Words keeps your place when you come back to its tab (#218). Back from Play before you've scrolled, it's still
    /// at Tomo's level; then your swipes stay where you leave them, and so does the list when you're back from Play
    /// again. Whether a landing is still waiting at that level is TomoLanding's checks: a swipe ends any landing, so
    /// this journey passes either way. XCUITest can't scroll an iPhone with no scroll phase (keys don't move the
    /// list, and pointer scrolling isn't supported), so VoiceOver's and the keyboard's pages are TomoLanding's checks
    /// too.
    func testWordsKeepsYourPlaceWhenYouComeBack() {
        launch(TomoSeed.atLevel(14), tab: "words")
        expectWordsAtLevel(14)
        let play = app.tabBars.buttons[ui("screen.play")], words = app.tabBars.buttons[ui("screen.words")]
        play.tap()
        words.tap()
        expectWordsAtLevel(14)
        let list = app.scrollViews["words.list"]
        list.swipeUp()
        let first = expectWordsStay(away: 14, "after a swipe")
        list.swipeUp()
        let second = expectWordsStay(away: 14, "after another swipe")
        XCTAssertTrue(second.level > first.level || second.level == first.level && second.y < first.y - 1,
                      "the second swipe moved the list on: \(second), from \(first)")
        play.tap()
        words.tap()
        let back = expectWordsStay(away: 14, "back from Play")
        XCTAssertTrue(back.level == second.level && abs(back.y - second.y) <= 1,
                      "back from Play, the list is where it was: \(back), not \(second)")
    }

    /// Where the list rests: the level at its top (the last header at or above the chips' edge, or the first header
    /// below it), and that header's y. Read once the list has stopped (the same twice, 1 s apart), then three times
    /// over 2 s, and it mustn't change; Lv `level`'s header is never right under the chips, where a landing puts it.
    /// The journey's swipes only go down the list, so Lv `level` stays above the chips unless the list is pulled back.
    private func expectWordsStay(away level: Int, _ when: String) -> (level: Int, y: CGFloat) {
        let chips = app.scrollViews["words.stages"]
        let headers = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'words.level.'"))
        func place() -> (level: Int, y: CGFloat) {
            let edge = chips.frame.maxY
            let all = headers.allElementsBoundByIndex.map {
                (level: Int($0.identifier.dropFirst("words.level.".count)) ?? 0, y: $0.frame.minY - edge)
            }
            return all.filter { $0.y <= 1 }.max { $0.y < $1.y } ?? all.min { $0.y < $1.y } ?? (0, 0)
        }
        func same(_ a: (level: Int, y: CGFloat), _ b: (level: Int, y: CGFloat)) -> Bool {
            a.level == b.level && abs(a.y - b.y) <= 1
        }
        var last = place()
        for _ in 0..<5 {
            sleep(1)
            let now = place()
            if same(now, last) { break }
            last = now
        }
        var seen: [(level: Int, y: CGFloat)] = []
        for i in 0..<3 {
            if i > 0 { sleep(1) }
            let header = app.staticTexts["words.level.\(level)"]
            let gap = header.exists ? header.frame.minY - chips.frame.maxY : -1
            XCTAssertFalse(header.exists && (0...40).contains(gap),
                           "\(when), Lv \(level) isn't pulled back under the chips")
            seen.append(place())
        }
        print("\(name) \(when): the list's top \(seen)")
        XCTAssertNotEqual(seen[0].level, 0, "\(when), a level's header is in the list")
        XCTAssertTrue(seen.allSatisfy { same($0, seen[0]) }, "\(when), the list stays where it is: \(seen)")
        return seen[0]
    }

    /// Lv `level`'s header and its first word show right under the stage chips.
    private func expectWordsAtLevel(_ level: Int) {
        let chips = app.scrollViews["words.stages"]
        let header = app.staticTexts["words.level.\(level)"]
        let first = app.descendants(matching: .any)["words.word.\(TomoSeed.pack.levels[level - 1].itemIDs[0])"]
        XCTAssertTrue(chips.waitForExistence(timeout: 30), "the stage chips")
        let hittable = NSPredicate(format: "hittable == true")
        expectation(for: hittable, evaluatedWith: header)
        expectation(for: hittable, evaluatedWith: first)
        waitForExpectations(timeout: 30)
        XCTAssertGreaterThanOrEqual(header.frame.minY, chips.frame.maxY, "Lv \(level)'s header is below the chips")
        // Landed, the header sits about 16 pt under the chips on the 17 Pro and the SE; short of the level, it sits
        // hundreds of points lower (#218).
        XCTAssertLessThanOrEqual(header.frame.minY - chips.frame.maxY, 40,
                                 "Lv \(level)'s header is right under the chips")
        XCTAssertGreaterThanOrEqual(first.frame.minY, header.frame.maxY, "its first word is below the header")
    }

    /// A long press on Tomo shows its love (#133), which VoiceOver hears as Tomo's value until love may show again
    /// (`TomoLoveCooldown`, 6 s). XCUITest's press returns only after it waits for the app to settle, and Tomo never
    /// stops moving: on CI's simulators a press took 3 to 15 s, and the value was read 3 to 10 s after the touch
    /// (#203). So the test waits on the value. A press that returned within 5 s left at least a second of love to read,
    /// so a miss after it fails. Only after a slower press does it press again (three presses at most), once love may
    /// show again. Which path ran is recorded.
    func testALongPressOnTomoShowsItsLove() {
        launch()
        XCTAssertTrue(tomo.waitForExistence(timeout: 20))
        let loved = NSPredicate(format: "value == %@", ui("a11y.love")), slow = TomoLoveCooldown.seconds - 1
        for press in 1...3 {
            let began = Date()
            tomo.press(forDuration: 1.2)
            let seconds = Date().timeIntervalSince(began), took = String(format: "press %d took %.1f s", press, seconds)
            // Longer than love's cooldown, so a press after this one can show love again.
            let shown = XCTNSPredicateExpectation(predicate: loved, object: tomo)
            if XCTWaiter().wait(for: [shown], timeout: TomoLoveCooldown.seconds + 4) == .completed {
                record("\(took) and showed love")
                return
            }
            if seconds <= slow {
                XCTFail("a long press on Tomo shows its love: \(took), and Tomo's value never became \(ui("a11y.love"))")
                return
            }
            record("\(took), over \(Int(slow)) s, and its love wasn't read: pressing again", screenshot: app.screenshot())
        }
        XCTFail("a long press on Tomo shows its love: three presses were too slow to read it")
    }

    /// A learner's own language is never the one they learn (#199). One who picked the Japanese interface before
    /// (ja:ja) opens in English with the same Tomo, and Settings, scrolled to its end, has no interface language to
    /// pick while Japanese is the only target. `launch` waits for the English tabs, so a Japanese interface fails there.
    func testAJapaneseInterfaceFromBeforeOpensInEnglishWithItsTomo() {
        launch(TomoSeed.atLevel(14, learner: "ja"), env: ["TOMO_LEARNER": "ja"])
        XCTAssertTrue(app.staticTexts[ui("level", ["n": "14"])].waitForExistence(timeout: 20), "its Tomo came along, at Lv 14")
        app.tabBars.buttons[ui("screen.settings")].tap()
        let restart = app.buttons[ui("settings.restart")]
        for _ in 0..<6 where !(restart.exists && restart.isHittable) { app.swipeUp() }
        XCTAssertTrue(restart.exists, "Settings scrolled down to Start over, under where the interface language was")
        let speaks = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", ui("settings.speak")))
        XCTAssertEqual(speaks.count, 0, "no interface language to pick")
        record("Settings at its end, with no interface language", screenshot: app.screenshot())
    }

    /// A Debug build is its own app (#54): the app's own checks (TOMO_SELFTEST, TomoIdentity) pass on the iPhone. Its
    /// ID, name, data folder and keychain service are the Debug app's, and so are its App Group and its widgets'. The
    /// app writes them to the data folder before Tomo shows.
    func testThisBuildIsItsOwnApp() throws {
        let dir = TomoSeed.folder()
        launch(dir, env: ["TOMO_SELFTEST": "1"])
        XCTAssertTrue(tomo.waitForExistence(timeout: 20))
        let report = try String(contentsOf: dir.appendingPathComponent("selftest.txt"), encoding: .utf8)
        let lines = report.split(separator: "\n")
        XCTAssertEqual(lines.count, 5, report)
        XCTAssertTrue(lines.allSatisfy { $0.hasPrefix("ok ") }, report)
        XCTAssertTrue(report.contains("group.com.zenbujapanese.tomo.debug")
                      && report.contains("com.zenbujapanese.tomo.debug.widgets"), report)
    }
}

/// Saved progress for a journey, written with TomoCore's own store into a fresh folder the app is launched on.
@MainActor
enum TomoSeed {
    /// A fresh folder in the test runner's temporary folder.
    static func folder() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tomo-ui-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The pack the journeys learn (TOMO_TARGET=ja).
    static var pack: TargetPack { TomoLanguages.shared.targets.first { $0.id == "ja" }! }

    /// Level 1 just learned (each word heard once, answered right a moment ago): nothing counts for an hour, today's
    /// new words are used up, so Tomo rests. Today's answers are in the log.
    static func levelOneJustLearned() -> URL {
        let dir = folder(), now = Date()
        guard let store = TomoStore(learner: "en", target: "ja", directory: dir) else { return dir }
        store.saveTomo(.init(metAt: now.addingTimeInterval(-5 * 86400), level: 1, age: 1))
        for id in pack.levels[0].itemIDs {
            store.saveItem(.init(id: id, stage: 1, due: now.addingTimeInterval(2 * 3600), introduced: now, answered: now,
                                 right: 1, wrong: 0, peak: 1))
            store.logAnswer(at: now, item: id, level: 1, mode: "picture", result: "right", wrongTries: 0, hint: false,
                            counted: true, before: nil, after: 1)
        }
        return dir
    }

    /// Tomo at `level`, at that level's age: every word of the levels before it known at stages 2 to 6 (due in a day
    /// or more), and its own level's words just met. `learner`: the interface it was saved under (`ja`: a ja:ja setup
    /// from before #199).
    static func atLevel(_ level: Int, learner: String = "en") -> URL {
        let dir = folder(), now = Date()
        guard let store = TomoStore(learner: learner, target: "ja", directory: dir) else { return dir }
        store.saveTomo(.init(metAt: now.addingTimeInterval(-30 * 86400), level: level, age: pack.levels[level - 1].age))
        for (n, words) in pack.levels.prefix(level).map(\.itemIDs).enumerated() {
            for (i, id) in words.enumerated() {
                let stage = n + 1 == level ? 1 : 2 + i % 5
                store.saveItem(.init(id: id, stage: stage, due: now.addingTimeInterval(Double(stage) * 86400),
                                     introduced: now.addingTimeInterval(-20 * 86400), answered: now.addingTimeInterval(-3600),
                                     right: stage, wrong: 0, peak: stage))
            }
        }
        return dir
    }
}
