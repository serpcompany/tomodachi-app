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

    /// The stage rule can't drift loose (#236): light stages that look alike fall short at every step, in their fills
    /// and in greyscale, while the light stages clear every step. #217's are its exact light stages; A1 is #236's first
    /// idea, greens that deepen in the text on #217's 15% tint, whose texts alone are 0.09 to 0.10 apart.
    func testTheStageRuleFailsLightStagesThatLookAlike() {
        let tint = { (hex: String) in TomoStagePill.Look(text: hex, fill: hex, opacity: 0.15) }
        let lookalikes = [("#217", ["#0E625F", "#035C42", "#02513E", "#024635", "#6042B8"]),
                          ("A1", ["#016165", "#01652C", "#014A23", "#012D16", "#6A37BF"])]
        for (name, hexes) in lookalikes {
            let steps = TomoStagePill.steps(hexes.map(tint), dark: false)
            XCTAssertEqual(steps.count, 4, name)
            for step in steps {
                XCTAssertLessThan(step.apart, TomoStagePill.minimumStep, "\(name): \(step.from) to \(step.to), fills apart")
                XCTAssertLessThan(step.darker ?? .infinity, TomoStagePill.minimumStep, "\(name): \(step.from) to \(step.to), darker")
            }
        }
        let light = TomoStagePill.steps(TomoStagePill.stages.compactMap { TomoStagePill.look($0, dark: false) }, dark: false)
        XCTAssertEqual(light.count, 4)
        for step in light {
            XCTAssertGreaterThanOrEqual(step.apart, TomoStagePill.minimumStep, "light: \(step.from) to \(step.to), fills apart")
            XCTAssertGreaterThanOrEqual(step.darker ?? 0, TomoStagePill.minimumStep, "light: \(step.from) to \(step.to), darker")
        }
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
