# The Coucou fork

The demo app started as a fork of [Coucou](https://github.com/Louis-CFM/coucou), a notch companion for
coding agents. Coucou supplies the notch window and its open/close logic; everything Tomo is our own.
This page says what we may use, which Coucou files we changed, what we deleted, and what's left.

## What we may use

- **Code: MIT** (`mac-demo/LICENSE`). Use, change and ship it.
- **Assets: reserved** (`mac-demo/LICENSE-ASSETS.md`): the Coucou name, the Mochi character and its
  sounds. Never ship them.
  - The sounds are deleted; Tomo's are synthesized in `TomoSounds.swift`. `release-beta.sh` refuses a
    build that bundles a Coucou sound.
  - The icons are drawn from Tomo's own code.
  - Coucou's character code is deleted. The last version is in git history
    (`git show 43a5ada:mac-demo/NotchBuddy/Sources/App/BotEngine.swift`) and upstream. Read it for
    technique only: Mochi's look, expressions and animations are reserved.

## Coucou files we changed

Tomo's code lives in new `Tomo*.swift` files behind the seams in [architecture.md](architecture.md).
These are the Coucou files we had to touch; add a file here when a change has to go into one.

| File | Change |
|---|---|
| `AppDelegate.swift`, `AppState.swift` | Launches straight into the game (its first visit waits out quiet hours, `TomoGame.launchVisit`; `TOMO_ONBOARDING=preview` opens the first run's preview instead). `AppDelegate` sets `TomoGame`'s shell closures, `TomoSync.registerForPushes` and Reduce Motion (`TomoMotion.follow`, from `NSWorkspace`). `AppState` keeps only what the island draws: its mode and view, Tomo's state (`tomoState`, from `TomoGame.onBotState`) and the pointer; `soundEnabled` forwards to `TomoGame.soundEnabled`. Tomodachi is a regular app with a Dock icon (an agent until launch, so test runs stay out of the Dock); opening it again opens the Tomodachi window (`applicationShouldHandleReopen`). The menu bar icon's menu comes from `TomoMenus`, shared with the main menu; ⌥-click adds the testing tools (`TomoTestingTools`) |
| `IslandRootView.swift`, `IslandViewContent.swift`, `IslandTypes.swift`, `IslandScreenGeometry.swift` | The island shows Tomo's card (`TomoView`) or the dizzy card, nothing else. The header shows Tomo, with room for the level bar. Draws `TomoCharacterView`. Open, an amber countdown line under the card while an ignored visit runs out (`TomoCountdownLine`). Resting, small Tomo sits left of the notch and Tomo's right side (`TomoRestingSide`: あそぼ！ or when words are back, and a level ring) right of it, never under it (`IslandRestingLayout`); no count or red dot. The dizzy card's text comes from the language files. `BotState` and `BotEmote` moved to TomoCore (`TomoSignals.swift`) |
| `IslandWindowController.swift`, `IslandStateMachine.swift` | A taller window (560 pt) so the help panel fits. Hover, click, pokes and Esc only (resting on Tomo shows love at most every 6 s: `TomoLoveCooldown`, shared with the iPhone); no greeting state. Esc is a local key monitor (no Accessibility), and the island follows the notch screen when displays change. `TOMO_NO_NOTCH` sizes it for a screen without a notch, for snapshots. The panel can't be hidden, so hiding the app (now a regular one) leaves Tomo in the notch. Tomo's notification names moved to TomoCore (`TomoSignals.swift`). Coucou's 60 Hz pointer poll is gone: the pointer's moves come from mouse event monitors (global and local, no permission), and the island's own changes check it again; the 60 Hz clock runs only while the pointer is in the island or Tomodachi is the active app |
| `NotchBuddyApp.swift` | An empty Settings scene that carries the main menu (`TomoCommands`); the window is `TomoAppWindow`. Its `init` decides who sees the first run (`TomoOnboarding.checkAtLaunch`) before the menu opens the store |
| `project.yml`, `Resources/Info.plist` | App name, bundle ID `com.zenbujapanese.tomodachi`, starts as an agent (`LSUIElement`; `AppDelegate` makes it regular), no microphone or speech permission while answers are choices, Release signing for beta builds. Depends on the local `TomoCore` package; the language packs come from its bundle |
| `SoundEngine.swift` | A shim that sends the island's open, close and peek to `TomoSounds`. Coucou's 28 sound files are deleted |

## Deleted

- **Coucou's character:** `BotEngine`, `BotCanvasView`, `GreetingCanvasView`, `UploadCanvasView`.
- **Its coding-agent features** ([#1](https://github.com/serpcompany/tomodachi-app/issues/1)): the hook
  server (`HookServer`), the seven `*Poller` integrations and their pills (`PillCatalog`), the chat
  (`ClaudeService`, which also read Coucou's API keys from the Keychain at every launch), file drop with
  its "ask a question" and "send by email" flow (`FileDropView`, `UploadSequenceEngine`), drag-to-attach a
  window (`WindowContextCapture`), Coucou's settings (`SettingsView`), `AppLog`, `SafeWebURL`, and the
  views they drew in the island. The `Keychain` helper moved to TomoCore first (`TomoKeychain.swift`).
- The last versions are in git history, for example
  `git show 7992e4e:mac-demo/NotchBuddy/Sources/App/WindowContextCapture.swift`, worth a look for
  [#24](https://github.com/serpcompany/tomodachi-app/issues/24) (Tomo names what's on your screen).

## Left to do

Renaming the Xcode project, target, scheme and folder from `NotchBuddy` to `Tomodachi`
([#1](https://github.com/serpcompany/tomodachi-app/issues/1)). It touches every path under
`mac-demo/NotchBuddy/`, so it waits until no branches are open there.
