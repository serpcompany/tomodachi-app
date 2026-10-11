# Architecture

The map of the demo app's systems: what each one owns, the seam to go through, and the invariants to
keep. A system with more to say than a paragraph has a leaf of its own, linked from its entry: read
the one your change touches. Names are types and files you can search for; the code and its comments
hold the detail. Planned work links to its issue.

Tomo's code is in `Tomo*.swift` files, in two places. **`TomoCore/`** is a Swift package for macOS
and iOS with everything that isn't tied to one device: the game, growth, store, languages and their
packs, AI, voice, sounds, and Tomo's drawing. Each app is a shell around it: the Mac app in
`mac-demo/NotchBuddy/Sources/App/`, where Coucou's files (`Island*`, `AppDelegate`, `AppState`…) are
the notch ([coucou-fork.md](coucou-fork.md)), and the iPhone app in `ios-demo/` with its widget
extension ([iphone.md](iphone.md)). Mac-only parts stay in the Mac app: the card (`TomoView`), the
Tomodachi window and the menus (`TomoAppWindow`, `TomoMenus`), clickable words with the Mac's
dictionary (`TomoLineView`) and Tomo in the island (`TomoIslandCharacter`). The screens both apps
show (Tomo, Words, Together, Settings, About) are in TomoCore ([screens.md](screens.md)). Invariant:
TomoCore never imports AppKit or UIKit, or reaches into a shell, and takes the app's identity from
it (Info.plist's `TomoAppGroup`, `TomoCloudContainer`).

## Layers

```
Island shell (Coucou)       notch window, open/close state machine, click-through
  └─ Character (TomoBlob)   Tomo the blob: a look from a seed, faces, moves, evolving
  └─ Tomo app               TomoGame (flow) · TomoView (UI)
       ├─ Content source    what Tomo brings: the age track (language packs)
       ├─ Growth            word stages, levels, ages (TomoProgress)
       ├─ Learner store     saved progress and answer log (TomoStore, SQLite)
       ├─ Stats             what you and Tomo did, from the logs (TomoStats)
       ├─ Sync              one Tomo across the learner's devices (TomoSync, iCloud)
       ├─ Visits            when Tomo drops in, when it leaves
       ├─ Reminders         iPhone notifications when words are ready (TomoReminders)
       ├─ First run         who sees the welcome, and its flow (TomoOnboarding)
       ├─ Answer checking   language check → AI → offline placeholder
       ├─ Conversation AI   TomoAI provider adapter
       └─ Voice and sound   speech out and in · TomoSounds
```

## Shells

**The island** (the Mac). Coucou's notch window and its open and close rules, cut down to Tomo's
card, the dizzy card and a visit's peek. Tomo reaches it only through closures on `TomoGame`, set in
`AppDelegate`. The card is a fixed grid (`TomoGrid`), and help grows a panel under it, never inside
it. The shell, its invariants, the card and the help panel: [island.md](island.md).

**The iPhone app.** `TomoPhoneShell` sets the same closures, with the app on screen counting as
open. Widgets and the Lock Screen card can't run the game: they draw the `TomoGlance` the app
writes, and the card's buttons reach the game through `TomoVisitHook`. The shell, its files, the
widgets and the card: [iphone.md](iphone.md).

## Systems

**Character.** `TomoBlob` in `TomoCharacter.swift`: Tomo the blob, drawn every frame in code on a
clock, so it can be rendered offline. Its look (`TomoLook`, from a seed) and what it's made of
(`TomoMaterial`: jelly for the learner's own Tomo, classic for the mascot and what ships as files)
come from its host, and the game drives it through notifications and Tomo's state, never directly,
so any screen can host it. Big moments, arrivals and its hello are cue scripts on that clock, and
Reduce Motion is an input. How it works, what hosts pass in, and its invariants:
[character.md](character.md).

**Languages.** `TomoLanguage.swift`: the target pack (Tomo's words, voice, recognition, AI rules)
and the learner pack (interface text) for the current pair, `TomoLanguages.shared`; background work
takes a `LanguageContext`. Invariant: no language-specific text in Swift (checked by
`.github/scripts/check-swift-text.mjs`). The pack format and pairs are in
[languages.md](languages.md). Planned:
[#34](https://github.com/serpcompany/tomodachi-app/issues/34).

**Content source.** What Tomo brings. Today there's one source, the age track: the pack's `levels`,
turned into `TomoRound` (a picture, need or meaning round; a talking question as a meaning or reply
round) and `TomoLine` (typed conversation, switched off by `TomoGame.talkAsChoices`). Planned: a
`TomoContentSource` seam ([#10](https://github.com/serpcompany/tomodachi-app/issues/10)), Anki and
other sources ([#11](https://github.com/serpcompany/tomodachi-app/issues/11),
[#12](https://github.com/serpcompany/tomodachi-app/issues/12)), and age-track content from the Zenbu
learning system ([#13](https://github.com/serpcompany/tomodachi-app/issues/13)).

**Growth.** `TomoProgress.swift` holds every rule: word stages and their waits, levels and
birthdays, what to ask next, and whether a right answer counts. `TomoGame` asks; only `TomoProgress`
decides. What a learner sees, the levels, and the invariants: [growth.md](growth.md).

**Learner store and sync.** `TomoStore` is one SQLite file on each device, keyed by (learner,
target), and stays the truth there; `TomoSync` carries one Tomo across the learner's Mac and iPhone
through their own iCloud, and a merge never moves progress back. The tables, the logs, the merge
rules and the environments: [store-and-sync.md](store-and-sync.md).

**Stats.** `TomoStats` reads the store's logs to show what you and Tomo did (Together, the postcard,
the garden, the diary, the height pillar); no screen counts anything itself: [stats.md](stats.md).

**Visits and reminders.** How Tomo comes to you: visits (`TomoGame.tick()`, `DropIn`) in every
shell, and reminders (`TomoReminders`, a pure plan) on the iPhone. Both come only when something
counts and hold for quiet hours: [visits.md](visits.md).

**First run.** `TomoOnboarding` decides who sees it (`onboarding.json` in the data folder, checked
before anything opens the store) and runs the flow, which each shell hosts:
[first-run.md](first-run.md).

**Answer checking.** `TomoBrain.reply`, in layers. First a language check: an answer in the wrong
language gets no credit and no AI call. Then AI, if configured. Otherwise the pack's offline
replies, a placeholder that the Zenbu dictionary replaces
([#6](https://github.com/serpcompany/tomodachi-app/issues/6)).

**Conversation AI.** `TomoAI.complete` is the only network call to an AI: Anthropic's API, or any
OpenAI-compatible endpoint. The prompt is a shared template plus the pack's persona and rules. The
provider comes from the AI page (key in the Keychain; shown with the testing tools, `TomoFeatures`),
else from the environment. Only Debug builds have AI (`TomoAI.isAvailable`): in a Release build
there's no AI page, no provider and no AI call. Planned:
[#7](https://github.com/serpcompany/tomodachi-app/issues/7),
[#8](https://github.com/serpcompany/tomodachi-app/issues/8).

**Voice and sound.** Every spoken line goes through `TomoGame.speak` (the system voice for the
pack's locale, pitched up); answers come in through `TomoListener` (on-device recognition). Sound
effects are synthesized in code, with no audio files, and all triggered in one place
(`TomoSounds.listen()` and `outcome(_:)`). `TomoSoundSynth` mixes each sound's voices and sets it to
its moment's loudness (K-weighted, peaks under -3 dBFS), so every age plays equally loud;
`TomoBlobSound` (bubbly) says how each moment sounds, lower and fuller as Tomo grows. Planned: a
voice that ages with Tomo ([#5](https://github.com/serpcompany/tomodachi-app/issues/5)), recognition
hints ([#17](https://github.com/serpcompany/tomodachi-app/issues/17)), sound polish
([#21](https://github.com/serpcompany/tomodachi-app/issues/21)).

**Screens.** Tomo, Words, Together, Settings and About are SwiftUI views in TomoCore that both
shells show. `TomoScreens.swift` holds the seam (`TomoScreen`, `TomoScreenNav`, `TomoFeatures`); the
screens read `TomoGame`, `TomoProgress` and `TomoStats` and decide nothing themselves. How each
shell shows them, and their invariants: [screens.md](screens.md).

The research behind these systems is mapped in [research/README.md](research/README.md).
