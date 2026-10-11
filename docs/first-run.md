# The first run

Who sees the first run, and how each shell hosts it. What a learner sees is in
[concepts.md](concepts.md) ("First run"); the other systems are mapped in
[architecture.md](architecture.md).

## How it runs

`TomoOnboarding.swift` decides who sees it and runs the flow; `TomoOnboardingView.swift` draws it
(SwiftUI only, so any shell can host it), with the iPhone's own steps in
`TomoOnboardingPhone.swift`; the Mac shows it in a window (`TomoOnboardingWindow`), which
`AppDelegate` opens instead of the launch visit (its own steps: quiet hours for the visits, and open
at login as "Let Tomo find you", through the shell's `TomoLoginItem`; a test run never changes the
login item), and whose `preview` plays it on a copy of the Tomo (`TomoGame.useCopy`) for the Testing
menu, and the iPhone full screen over Tomo's screen (`TomoPhoneFirstRun`), holding the game, the
Lock Screen card and the reminders until it's done. `checkAtLaunch()` runs before anything opens the
store, because `TomoGame` hatches a Tomo when there's none (on the Mac, in `NotchBuddyApp.init`,
before the main menu reads the game). The guided round answers through `TomoProgress`, so the first
word counts; the visit clock is held while the window is open, and the flow ends with
`TomoGame.reload()`, which is Tomo's first visit. Invariants: the "done" mark is `onboarding.json`
in the data folder, never UserDefaults (Debug builds share the owner's defaults); a learner with a
saved Tomo never sees a hatch; a preview never writes `onboarding.json`, the saved Tomo, or a
setting that wasn't changed in it; a device that joins the iCloud Tomo during the flow (an older
`metAt` arrives) gets "welcome back", followed by the device's own setup; the Lock Screen card
starts only after the learner says yes (`TomoReminderSettings.lockScreen`). Planned: the reference's
trial and plan screens go before `ready` once pricing is decided.
