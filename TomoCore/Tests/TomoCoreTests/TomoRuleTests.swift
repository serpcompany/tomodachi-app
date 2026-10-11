import XCTest
@testable import TomoCore

/// How Tomo grows: word stages, levels, the bar, free play, the store (TomoProgress).
final class TomoGrowthRuleTests: TomoCheckCase {
    func testWordStagesLevelsAndTheStore() { expect(TomoProgress.rulesSelfTest) }
}

/// What you and Tomo did: today, weeks, streaks, the garden, the pillar, the diary, the exports (TomoStats), against a
/// simulated learner.
final class TomoStatsTests: TomoCheckCase {
    func testStatsAgainstASimulatedLearner() { expect(TomoStats.selfTest) }
}

/// Every pack can be finished, and simulated learners grow from the first word to the first talking question with
/// nothing going backwards (about 20 s).
final class TomoSimulationTests: TomoCheckCase {
    func testEveryPackAndTheSimulatedLearners() { expect(TomoProgress.simulationSelfTest) }
}

/// Tomo's drawing (evolution, Reduce Motion, touches, cue scripts, arrivals, material, hello, badges, particles,
/// dance), its look, and the calendar.
final class TomoCharacterTests: TomoCheckCase {
    func testTomosDrawingAndTheCalendar() { expect(TomoProgress.characterSelfTest) }
    func testTheLookRules() { expect(TomoLook.selfTest) }
}

/// What the Words show reads on its card (#195, #207, #236): a dark picture gets a light disc on a dark card, and each
/// stage's colour reads at 5:1 or more and stands apart from the stage before it, in light and dark mode.
final class TomoContrastTests: TomoCheckCase {
    func testDarkPicturesGetADiscOnADarkCard() { expect(TomoPicture.selfTest) }
    func testStagesReadAndStandApartOnLightAndDarkCards() { expect(TomoStagePill.selfTest) }

    /// The stage rule can't drift loose (#236): run on palettes it must catch, it fails each at the steps that look
    /// alike, and passes the light stages. Removing or loosening either light floor fails one of them.
    func testTheStageRuleCatchesLightStagesThatLookAlike() {
        let light = TomoStagePill.stages.compactMap { TomoStagePill.look($0, dark: false) }
        let tint = { (hex: String) in TomoStagePill.Look(text: hex, fill: hex, opacity: 0.15) }
        /// The checks a light palette fails, as "<stage> <measure>".
        func fails(_ looks: [TomoStagePill.Look]) -> [String] {
            XCTAssertEqual(looks.count, TomoStagePill.stages.count)
            return TomoStagePill.stepChecks(looks, dark: false).filter { !$0.holds }.map { "\($0.to) \($0.measure)" }
        }
        let everyStep = ["knows apart", "knows darker", "good apart", "good darker",
                         "loves apart", "loves darker", "forever apart", "forever darker"]
        // #217's exact light stages: dark greens as text, each on a 15% tint of itself.
        XCTAssertEqual(fails(["#0E625F", "#035C42", "#02513E", "#024635", "#6042B8"].map(tint)), everyStep, "#217")
        // A1, #236's first idea: greens that deepen in the text, on #217's tint. Their texts alone are 0.09 to 0.10 apart.
        XCTAssertEqual(fails(["#016165", "#01652C", "#014A23", "#012D16", "#6A37BF"].map(tint)), everyStep, "A1")
        // B2, a dark text at a rising opacity, then a solid Forever: its Just heard and Knows it fills nearly match
        // (0.056 apart), though each is darker than the last.
        let b2 = zip(["#036A66", "#016048", "#004E38", "#012A1D"], [0.08, 0.18, 0.30, 0.45])
            .map { TomoStagePill.Look(text: $0, fill: $0, opacity: $1) } + [TomoStagePill.Look(text: "#FFFFFF", fill: "#7B53DC", opacity: 1)]
        XCTAssertEqual(fails(b2), ["knows apart"], "B2")
        // The light stages with round 1's Forever (#7850DA): apart from Loves it, but as dark in greyscale.
        let flatForever = light.dropLast() + [TomoStagePill.Look(text: "#FFFFFF", fill: "#7850DA", opacity: 1)]
        XCTAssertEqual(fails(Array(flatForever)), ["forever darker"], "Forever as dark as Loves it")
        XCTAssertEqual(fails(light), [], "the light stages")
    }
}

/// Words lands on Tomo's level each time it shows (resting at once if the list is already there), and again whenever
/// its lazy rows move the level or SwiftUI puts the list back (3 times at most), until the learner moves it in any way
/// (with or without a scroll phase or new rows); while another tab shows, it hears nothing (#193, #218).
final class TomoWordsLandingTests: TomoCheckCase {
    func testWordsLandsOnTomosLevelUntilTheLearnerScrolls() { expect(TomoLanding.selfTest) }
}

/// One Tomo across devices: the merge rules and the store's sync columns (no iCloud).
final class TomoSyncTests: TomoCheckCase {
    func testTheMergeRules() { expect(TomoSync.selfTest) }
}

/// Who sees the first run, when reminders come, every moment's sound, and the moment's light.
final class TomoAppRuleTests: TomoCheckCase {
    func testWhoSeesTheFirstRun() { expect(TomoOnboarding.selfTest) }
    func testWhenRemindersCome() { expect(TomoReminders.selfTest) }
    func testEveryMomentHasASoftSound() { expect(TomoSounds.selfTest) }
    func testTheMomentsLight() { expect(TomoMoment.selfTest) }
    func testWhatTheWidgetsSay() { expect(TomoGlance.selfTest) }
}

/// A visit offered as a peek, on the game itself with a stand-in shell and a testing Tomo in memory (about 3 s).
final class TomoVisitTests: TomoCheckCase {
    func testAVisitThatPeeksFirst() { expect(TomoGame.offerSelfTest) }
}
