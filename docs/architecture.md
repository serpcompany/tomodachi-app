# Architecture

A bird's-eye view of the demo app: its systems, what each one owns, the seam to go through, and the
invariants to keep. Names are types and files you can search for; the code and its comments hold the
detail. Planned work links to its issue.

Tomo's code is in `Tomo*.swift` files, in two places. **`TomoCore/`** is a Swift package for macOS and
iOS with everything that isn't tied to one device: the game, growth, store, languages and their packs,
AI, voice, sounds, and Tomo's drawing. Each app is a shell around it: the Mac app in
`mac-demo/NotchBuddy/Sources/App/`, where Coucou's files (`Island*`, `AppDelegate`, `AppState`…) are
the notch ([coucou-fork.md](coucou-fork.md)), and the iPhone app in `ios-demo/` with its widget extension. Widgets can't run the game: the app writes a `TomoGlance` (age, level, bar, what's waiting, in the learner's language) to the App Group `group.com.zenbujapanese.tomodachi`, and the widget draws it, with the mascot moving through a font of its own frames (`TomoMovingMascot`; decisions.md). The same glance drives Tomo's Lock Screen card, a Live Activity (`TomoLiveVisit` in the app, `TomoVisitLiveActivity` in the extension), once the learner said yes to it; its stale date is the next due time, so it turns to "ready" without the app running. Mac-only parts stay in
the Mac app: the card (`TomoView`), Settings, clickable words with the Mac's dictionary
(`TomoLineView`) and Tomo in the island (`TomoIslandCharacter`). Invariant: TomoCore never imports AppKit
or UIKit, or reaches into a shell.

## Layers

```
Island shell (Coucou)       notch window, open/close state machine, click-through
  └─ Character (TomoBlob)   Tomo the blob: a look from a seed, faces, moves, evolving
  └─ Tomo app               TomoGame (flow) · TomoView (UI)
       ├─ Content source    what Tomo brings: the age track (language packs)
       ├─ Growth            word stages, levels, ages (TomoProgress)
       ├─ Learner store     saved progress and answer log (TomoStore, SQLite)
       ├─ Sync              one Tomo across the learner's devices (TomoSync, iCloud)
       ├─ Visits            when Tomo drops in, when it leaves
       ├─ Reminders         iPhone notifications when words are ready (TomoReminders)
       ├─ First run         who sees the welcome, and its flow (TomoOnboarding)
       ├─ Answer checking   language check → AI → offline placeholder
       ├─ Conversation AI   TomoAI provider adapter
       └─ Voice and sound   speech out and in · TomoSounds
```

## Systems

**Island shell.** Coucou's notch window and state machine (`IslandWindowController`,
`IslandStateMachine`, `IslandRootView`), cut down to what Tomo uses: it shows Tomo's card or the dizzy
card, and nothing of Coucou's agent features is left ([coucou-fork.md](coucou-fork.md)). Tomo reaches it only through four closures on `TomoGame`
(`openIsland`, `closeIsland`, `isIslandOpen`, `focusInput`, plus `isPointerInside`, `onBotState`,
`onHelpChange`, `onActivity` and `secondsSinceInput`), set in `AppDelegate`. Another shell sets the same
closures: the iPhone app's `TomoPhoneShell` treats the app being on screen as open, so Tomo never times
out while you look at it, and so is a round open on the Lock Screen card (`TomoLiveVisit.isPlaying`). The
card's Play and choice buttons are `LiveActivityIntent`s (`TomoPlayIntent`, `TomoAnswerIntent`) that iOS
runs in the app's process, launching it in the background if needed; they reach the game through
`TomoVisitHook`, set in the app's `init` ([#52](https://github.com/serpcompany/tomodachi-app/issues/52)).
Invariants on the Mac: the island sits on the notch screen (else the main display) and moves when displays
change; it needs no permission; it takes the keyboard only when the learner opens it (a click, the menu),
so Esc works then and a visit never takes a keystroke (decisions.md).

**Character.** `TomoBlob` in `TomoCharacter.swift`: a blob drawn every frame in code. Its look is a
`TomoLook` (`TomoLook.swift`) hashed from a seed: a colour and eyes for life, and a form for each age
(silhouette, size, details) that changes at every birthday. The learner's look is `TomoLook.current`,
which `TomoGame` sets from the saved Tomo; the seed is the language pair and the second the Tomo first
appeared, which is already synced, so every device draws the same Tomo. Places that can't draw it live
(widgets, Live Activities, the icons) show `TomoLook.mascot`. It's driven by notifications (`.botGrow`,
`.botLevelUp`, `.triggerEmote` and others, in `TomoSignals.swift`) and Tomo's state
(`TomoGame.onBotState`), never called directly, so any screen can host it: `TomoBlobView` on the iPhone,
`TomoCharacterView` in the island. Its time comes from a clock, so it can be rendered offline.
Invariants: idle life never stops; a seed always gives the same Tomo. Trait keys can be added freely, but
changing a range, a band or a list changes every learner's Tomo (`TomoLook.selfTest`). `TomoLook.variety` scales how different Tomos are. Planned: evolution that reads as growing up
([#87](https://github.com/serpcompany/tomodachi-app/issues/87)).

**Languages.** `TomoLanguage.swift`: the target pack (Tomo's words, voice, recognition, AI rules) and the
learner pack (interface text) for the current pair, `TomoLanguages.shared`; background work takes a
`LanguageContext`. Invariant: no language-specific text in Swift (checked by
`.github/scripts/check-swift-text.mjs`). The pack format and pairs are in [languages.md](languages.md).
Planned: [#34](https://github.com/serpcompany/tomodachi-app/issues/34).

**Content source.** What Tomo brings. Today there's one source, the age track: the pack's `levels`,
turned into `TomoRound` (a picture, need or meaning round; a talking question as a meaning or reply round) and `TomoLine` (typed conversation, switched off by `TomoGame.talkAsChoices`). Planned: a
`TomoContentSource` seam ([#10](https://github.com/serpcompany/tomodachi-app/issues/10)), Anki
and other sources ([#11](https://github.com/serpcompany/tomodachi-app/issues/11),
[#12](https://github.com/serpcompany/tomodachi-app/issues/12)), and age-track content from the
Zenbu learning system ([#13](https://github.com/serpcompany/tomodachi-app/issues/13)).

**Growth.** `TomoProgress.swift` holds every rule: word stages and their waits (`TomoSRS`), levels and
birthdays, what to ask next, and whether a right answer counts. `TomoGame` asks; only `TomoProgress`
decides. Invariants:
- An answer counts only when the word is due, or at least halfway through its wait.
- Level and age never go down, and the experience bar never moves back (it uses each word's best stage).
- The bar counts the level's best `levelNeeded` words, and its goal (`goalShare`, the last tenth) fills only
  when the level is done. Every surface draws the same number (`TomoGrowthBar` on the card, the iPhone and
  Settings; the glance for widgets).
- Practice is a mode the learner picks, and it never moves the bar.

`TomoClock` moves time for testing, and `TOMO_SELFTEST=1` checks the rules. Planned:
[#38](https://github.com/serpcompany/tomodachi-app/issues/38).

**Learner store.** `TomoStore.swift`: one SQLite file on the device, keyed by (learner, target), so each
language pair has its own Tomo. `tomo` and `item` hold the current state; `answer` and `growth` are
append-only logs. Start over clears the words and notes when (`tomo.reset_at`), never the logs.
`TOMO_DATA_DIR` moves the file. Planned: Language Reference IDs as item ids and sync with the Zenbu apps
([#28](https://github.com/serpcompany/tomodachi-app/issues/28)).

**Sync.** `TomoSync.swift`: one Tomo across the learner's Mac and iPhone through their own iCloud
(CloudKit private database, zone `Tomo`, container `iCloud.com.zenbujapanese.tomodachi`) with Apple's
`CKSyncEngine`; no server of ours. `TomoStore` stays the truth on each device: a save reports itself
(`TomoStore.didChange`) and becomes a pending record, one per Tomo and one per word; what arrives is
merged (`mergeTomo`, `mergeItem`) and written back without echoing, then `TomoGame` reloads. Invariants:
a merge never moves progress back (the higher level and age, the copy of a word answered last, its best
stage); a start over wins over older progress, and each word record carries the start over it belongs
to; a device meeting the iCloud Tomo for the first time joins it. CloudKit pushes tell the other devices
(the shells register through `TomoSync.registerForPushes`); a timer and the iPhone coming to the front
fetch too. Debug builds use CloudKit's Development environment, Developer ID and App Store builds
Production. The logs and settings stay on each device for now
([#62](https://github.com/serpcompany/tomodachi-app/issues/62)).

**Visits.** `TomoGame.tick()` with the `DropIn` constants. Tomo opens on its own when it has something
that counts and you're at a natural break (not typing, not away). It tucks back in when ignored, leaving
a red dot. Opening it yourself is free play, with no time limit. When nothing counts, Tomo rests
(`TomoPhase.resting`, `TomoGame.rest`) in every shell until something counts, which the tick notices, or the
learner picks Practice; opening Tomo again shows the rest, never a new offer. Planned: chattiness and back-off
([#19](https://github.com/serpcompany/tomodachi-app/issues/19)), busy detection
([#20](https://github.com/serpcompany/tomodachi-app/issues/20)).

**Reminders.** `TomoReminders.swift`: how Tomo comes to you on the iPhone. `TomoReminders.plan` is a pure
function from the learner's ready times (`TomoProgress.readyTimes`: each word's due time, and when new words
are ready) and `TomoReminderSettings` (rhythm, quiet hours, on, the Lock Screen card; saved per device) to the
reminders to schedule; `TomoReminderCenter` schedules them with `UNUserNotificationCenter`, in Tomo's words at
its age (the pack's `reminders`). The shell calls `install()` at launch (the delegate: no banner while the
app is open) and `start()` once the game runs; then every progress change, and the app coming and going,
schedules again. `TomoReminderSettingsView` is their settings page. Invariants: a reminder only when something
counts; never sooner than one rhythm after now, never in quiet hours; at most 48 pending (iOS keeps 64);
the iOS prompt only after its reason (the first run's "Let words find you", or the Settings switch);
`TOMO_SELFTEST` checks the rules (`TomoReminders.selfTest`). The Mac has no reminders: its visits are its
cadence.

**First run.** `TomoOnboarding.swift` decides who sees it and runs the flow; `TomoOnboardingView.swift`
draws it (SwiftUI only, so any shell can host it), with the iPhone's own steps in `TomoOnboardingPhone.swift`;
the Mac shows it in a window (`TomoOnboardingWindow`), which `AppDelegate` opens instead of the launch visit,
and the iPhone full screen over Tomo's screen (`TomoPhoneFirstRun`), holding the game, the Lock Screen card
and the reminders until it's done. `checkAtLaunch()` runs before anything opens the
store, because `TomoGame` hatches a Tomo when there's none. The guided round answers through
`TomoProgress`, so the first word counts; the visit clock is held while the window is open, and the flow
ends with `TomoGame.reload()`, which is Tomo's first visit. Invariants: the "done" mark is
`onboarding.json` in the data folder, never UserDefaults (Debug builds share the owner's defaults); a
learner with a saved Tomo never sees a hatch; a device that joins the iCloud Tomo during the flow (an older
`metAt` arrives) gets "welcome back" (on the iPhone, followed by the device's own setup); the Lock Screen
card starts only after the learner says yes (`TomoReminderSettings.lockScreen`). Planned: the reference's
trial and plan screens go before `ready` once pricing is decided.

**Card and help panel.** `TomoView.swift`. The card is a fixed grid (`TomoGrid`): Tomo's column plus
fixed rows, and new UI goes into a slot. Help (a hint, an explanation, a word card) never squeezes into
the card: `TomoGame.help` grows the island by a panel underneath. Word cards (`TomoWords.swift`) are a
prototype, using an AI meaning and the Mac's dictionary until the Zenbu dictionary provides lookups per
target language ([#9](https://github.com/serpcompany/tomodachi-app/issues/9),
[#31](https://github.com/serpcompany/tomodachi-app/issues/31)).

**Answer checking.** `TomoBrain.reply`, in layers. First a language check: an answer in the wrong
language gets no credit and no AI call. Then AI, if configured. Otherwise the pack's offline replies, a
placeholder that the Zenbu dictionary replaces
([#6](https://github.com/serpcompany/tomodachi-app/issues/6)).

**Conversation AI.** `TomoAI.complete` is the only network call to an AI: Anthropic's API, or any
OpenAI-compatible endpoint. The prompt is a shared template plus the pack's persona and rules. The
provider comes from Settings → AI (key in the Keychain), else from `.env` through `run.sh`. Planned:
[#7](https://github.com/serpcompany/tomodachi-app/issues/7),
[#8](https://github.com/serpcompany/tomodachi-app/issues/8),
[#32](https://github.com/serpcompany/tomodachi-app/issues/32).

**Voice and sound.** Every spoken line goes through `TomoGame.speak` (the system voice for the pack's
locale, pitched up); answers come in through `TomoListener` (on-device recognition). Sound effects are
synthesized in `TomoSounds.swift`, with no audio files, and all triggered in one place (`listen()` and
`outcome(_:)`). Planned: a voice that ages with Tomo
([#5](https://github.com/serpcompany/tomodachi-app/issues/5)), recognition hints
([#17](https://github.com/serpcompany/tomodachi-app/issues/17)), sound polish
([#21](https://github.com/serpcompany/tomodachi-app/issues/21)).

**Settings.** `TomoSettingsView.swift`: a System Settings–style window with one `TomoSettingsPane` case
per page, and `TomoSettingsNav.open(_:)` to jump to a page. Pages read `TomoGame.progress`. Testing shows
only after a deliberate step (`TomoTestingTools`), and testing never touches the saved Tomo. Opening at
login is `TomoLoginItem`, off until the learner turns it on.

The research behind these systems is mapped in [research/README.md](research/README.md).
