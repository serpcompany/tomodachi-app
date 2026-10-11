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
