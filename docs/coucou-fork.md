# The Coucou fork

The demo app started as a fork of [Coucou](https://github.com/Louis-CFM/coucou), a notch companion for
coding agents. Coucou supplies the notch window and its open/close logic; everything Tomo is our own.
This page says what we may use, which Coucou files we changed, and what's left to remove.

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
| `AppDelegate.swift`, `AppState.swift` | No hooks or pollers. A single "tomo" task. Launches straight into the game. `AppDelegate` sets `TomoGame`'s shell closures and `TomoSync.registerForPushes`; `AppState.soundEnabled` forwards to `TomoGame.soundEnabled`. The menu: Tomo's words…, Start Tomo over… (asks first). The Settings window is resizable with a full-size content view |
| `IslandRootView.swift`, `IslandViewContent.swift`, `IslandTypes.swift` | The header and overview show Tomo, with room for the level bar. Draws `TomoCharacterView`. The dizzy card's text comes from the language files. `BotState` and `BotEmote` moved to TomoCore (`TomoSignals.swift`) |
| `IslandWindowController.swift` | A taller window (560 pt) so the help panel fits; the drag ghost draws Tomo. Tomo's notification names moved to TomoCore (`TomoSignals.swift`) |
| `NotchBuddyApp.swift` | The Settings scene shows `TomoSettingsView` |
| `project.yml`, `Resources/Info.plist` | App name, bundle ID `com.zenbujapanese.tomodachi`, microphone and speech permission text, Release signing for beta builds. Depends on the local `TomoCore` package; the language packs come from its bundle |
| `SoundEngine.swift` | A shim that sends the island's open, close and peek to `TomoSounds`. Coucou's 28 sound files are deleted |
| `ClaudeService.swift` | The Keychain service is `co.zenbu.tomodachi`. Its `Keychain` helper moved to TomoCore (`TomoKeychain.swift`), where `TomoAI` uses it |
| `BotEngine.swift`, `BotCanvasView.swift`, `GreetingCanvasView.swift`, `UploadCanvasView.swift` | Deleted: Coucou's character and the canvases that drew it |

## Switched off, still compiled

`HookServer`, the `*Poller` integrations, `PillCatalog`, the upload, mail and file-drop flow,
`SettingsView` and `WindowContextCapture` compile but never start. Removing them, and the
Coucou names left in code and comments, is
[#1](https://github.com/serpcompany/tomodachi-app/issues/1). `WindowContextCapture` may be
worth keeping for [#24](https://github.com/serpcompany/tomodachi-app/issues/24) (Tomo names
what's on your screen).
