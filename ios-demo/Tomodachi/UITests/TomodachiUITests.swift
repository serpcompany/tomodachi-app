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
    /// `settings`), and returns once it shows that tab, chosen, with no first run: the sign that it came up with this
    /// test's settings. Launched while the simulator was still installing it, it once came up without them (the first
    /// run, on Play) (#203); then it's launched again, once, and the relaunch is recorded with what it came up on, so
    /// a start that's sometimes wrong shows in every run's log. A second wrong start fails. XCUITest still sees the
    /// tabs under the first run, so the check looks for the first run itself.
    private func launch(_ folder: URL? = nil, tab: String? = nil) {
        let dir = folder ?? TomoSeed.folder(), want = tab ?? "play"
        for attempt in 1...2 {
            app = XCUIApplication()
            app.launchEnvironment = ["TOMO_DATA_DIR": dir.path, "TOMO_HEADLESS": "1", "TOMO_LEARNER": "en",
                                     "TOMO_TARGET": "ja", "TOMO_ONBOARDING": "0"]
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

    /// Words opens at Tomo's level (#193): the level's header and its first word show under the stage chips. The rows
    /// are lazy, so the jump to Lv 14 lands on estimated heights for the 13 levels above it; it once left the header
    /// scrolled away under the chips. Reading the screen lays the list out anew, which once moved it on to Lv 16 (#218).
    func testWordsOpensAtTomosLevel() {
        let level = 14
        launch(TomoSeed.atLevel(level), tab: "words")
        let chips = app.scrollViews["words.stages"]
        let header = app.staticTexts["words.level.\(level)"]
        let first = app.descendants(matching: .any)["words.word.\(TomoSeed.pack.levels[level - 1].itemIDs[0])"]
        XCTAssertTrue(chips.waitForExistence(timeout: 30), "the stage chips")
        let hittable = NSPredicate(format: "hittable == true")
        expectation(for: hittable, evaluatedWith: header)
        expectation(for: hittable, evaluatedWith: first)
        waitForExpectations(timeout: 30)
        XCTAssertGreaterThanOrEqual(header.frame.minY, chips.frame.maxY, "Lv \(level)'s header is below the chips")
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
    /// or more), and its own level's words just met.
    static func atLevel(_ level: Int) -> URL {
        let dir = folder(), now = Date()
        guard let store = TomoStore(learner: "en", target: "ja", directory: dir) else { return dir }
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
