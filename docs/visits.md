# Visits and reminders

How Tomo comes to you: visits in every shell, and reminders on the iPhone. What a learner sees is in
[concepts.md](concepts.md) ("Drop-in visits", "Always there", "Reminders (iPhone)"); the other
systems are mapped in [architecture.md](architecture.md).

## Visits

`TomoGame.tick()` with the `DropIn` constants. Tomo opens on its own when it has something that
counts and you're at a natural break (not typing, not away). It tucks back in when ignored and
bounces now and then until you check in (`pending`). Its deadline is `TomoGame.visitCountdown`, an
amber line under the Mac's card, nil while held (the pointer in the island, listening, help; on the
iPhone, on screen) or in free play. Resting, the island's right side says あそぼ！ while something
counts (`TomoGame.somethingCounts`, the same rule) or when it does again (`nextCountsAt`), never a
count. Opening it yourself is free play, with no time limit. A visit can peek first (the Mac's
setting, `DropIn.peekFirst`; off by default): it's `offered`, its first round shown in the peek with
its countdown running, and asked only once the card opens (`acceptOffer`); ignored, it leaves like
any visit. When nothing counts, Tomo rests (`TomoPhase.resting`, `TomoGame.rest`) in every shell
until something counts, which the tick notices, or the learner picks Practice; opening Tomo again
shows the rest, never a new offer. Quiet hours (`DropIn.quietEnds`, the reminders' setting) hold the
visits, the launch visit (`launchVisit`) and small Tomo's bounces until morning; clicking Tomo still
plays. Planned: chattiness and back-off
([#19](https://github.com/serpcompany/tomodachi-app/issues/19)), busy detection
([#20](https://github.com/serpcompany/tomodachi-app/issues/20)).

## Reminders

`TomoReminders.swift`: how Tomo comes to you on the iPhone. `TomoReminders.plan` is a pure function
from the learner's ready times (`TomoProgress.readyTimes`: each word's due time, and when new words
are ready) and `TomoReminderSettings` (rhythm, quiet hours, on, the Lock Screen card; saved per
device) to the reminders to schedule; `TomoReminderCenter` schedules them with
`UNUserNotificationCenter`, in Tomo's words at its age (the pack's `reminders`). The shell calls
`install()` at launch (the delegate: no banner while the app is open) and `start()` once the game
runs; then every progress change, and the app coming and going, schedules again.
`TomoReminderSettingsView` is their settings page. Invariants: a reminder only when something
counts; never sooner than one rhythm after now, never in quiet hours; at most 48 pending (iOS keeps
64); the iOS prompt only after its reason (the first run's "Let words find you", or the Settings
switch); `TOMO_SELFTEST` checks the rules (`TomoReminders.selfTest`). The Mac has no reminders: its
visits are its cadence.
