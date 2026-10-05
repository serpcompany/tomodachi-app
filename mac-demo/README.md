# Tomodachi notch demo (macOS)

A click-through demo of the Tomodachi idea: Tomo lives in the MacBook notch and talks like a 1-year-old Japanese child. You show you understood by picking the right picture or by doing what it asks (feed, bed, hug). Tomo is a baby chick: it starts in its eggshell, and after 5 words it hatches into 2さい and starts using two-word phrases.

Forked from [Coucou](https://github.com/Louis-CFM/coucou) (MIT code). Coucou's coding-agent hooks and integrations are switched off, not deleted.

## Run

```bash
./run.sh   # from mac-demo/
```

`run.sh` loads `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` from the repo's `.env` (gitignored) and passes it to the app, so Tomo replies with AI at 3さい (OpenAI default: `gpt-5.4-mini`). A provider saved under Settings → **AI** takes precedence. Without either, Tomo uses offline replies. You can also run `open build/Build/Products/Debug/Tomodachi.app`, which skips the AI keys.

Tomo opens on its own every 20 minutes by default (Settings → General) for a 3-answer visit. If you ignore it for 10 seconds, it tucks back in. In between, it sits small beside the notch: click it to play any time, and press Esc to close.

The menu bar icon has:
- **Open Tomodachi**
- **Drop in now** (⌘D)
- **Skip to talking (3さい)** (⌘3)
- **Restart Tomo** (⌘R)
- **Settings…** (⌘,):
  - *General:* the language pair (I speak / I'm learning), how often Tomo visits (10 min to 2 h, or only when you click), Tomo's voice and sounds, restart
  - *AI:* any provider (Anthropic, OpenAI, Gemini, OpenRouter, Groq, Ollama, or a custom OpenAI-compatible endpoint), key stored in the Keychain
  - *About*

## Beta builds for testers

```bash
mac-demo/scripts/release-beta.sh                 # build, sign (Developer ID), notarize, staple, zip
mac-demo/scripts/release-beta.sh --no-notarize   # build and sign only
```

- **One-time setup:** store notarization credentials. You type an app-specific password from appleid.apple.com, and it goes to your Keychain:
  ```bash
  xcrun notarytool store-credentials tomodachi-notary --apple-id "you@example.com" --team-id <team>
  ```
- **Team:** `DEVELOPMENT_TEAM` in `NotchBuddy/project.yml` (currently 847HR8U8D9), or `TOMO_TEAM=…` for one build. You need a Developer ID Application certificate for that team, and the notary profile must use the same team.
- **Output:** `mac-demo/build/release/Tomodachi-<version>-beta.zip`. The build is universal (Apple Silicon and Intel), macOS 15+. The version is `CFBundleShortVersionString` in `NotchBuddy/project.yml`.
- **What the script checks:** your Developer ID team, hardened runtime, the microphone permission, and that no Coucou sounds are bundled.
- **What to send testers:** the zip, plus [docs/beta-testing.md](../docs/beta-testing.md).

## App icon

The icon is drawn by the real character code:

```bash
TOMO_RENDER_ICON=/tmp/tomo-icon build/Build/Products/Debug/Tomodachi.app/Contents/MacOS/Tomodachi
python3 scripts/make-icons.py /tmp/tomo-icon     # writes AppIcon + MenuBarIcon (needs Pillow)
```

## Rebuild

```bash
cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath ../build build
```

## What changed from Coucou

| File | Change |
|---|---|
| `Sources/App/TomoGame.swift` | New. Rounds, visits, level-ups and birthdays, help state, and the voice (`AVSpeechSynthesizer`, the pack's locale, raised pitch) |
| `Sources/App/TomoProgress.swift`, `Sources/App/TomoStore.swift` | New. Word stages, levels and ages; saved progress in SQLite |
| `Sources/App/TomoView.swift` | New. The fixed-grid card (`TomoGrid`), picture/action tiles, chat card, help panel, header status |
| `Sources/App/TomoChat.swift` | New. Talking-stage replies (language check, then AI if configured, offline otherwise), explain, on-device speech recognition |
| `Sources/App/TomoLanguage.swift`, `Resources/languages/` | New. Language packs (`ja.json`, `en.json`, `es.json`), interface strings (`ui.en.json`, `ui.ja.json`), and the pair selection |
| `Sources/App/TomoSettingsView.swift` | New. Settings window (General, AI, About) |
| `Sources/App/TomoIconRenderer.swift`, `scripts/make-icons.py` | New. App and menu bar icons drawn from the character code |
| `scripts/release-beta.sh`, `Resources/Tomodachi.entitlements` | New. Signed, notarized beta builds |
| `Sources/App/TomoWords.swift` | New. Clickable words (`TomoLineView`), the font fit, word-card lookup (AI meaning + the Mac dictionary) |
| `Sources/App/TomoCharacter.swift` | New. Tomo the chick (`TomoChick`): drawing, faces, moves, growth, particles; `TomoCharacterView` puts it in the island |
| `Sources/App/TomoSounds.swift` | New. Tomo's sound effects, synthesized in code (no audio files) |
| `Sources/App/TomoAI.swift` | New. Provider adapter (Anthropic API + any OpenAI-compatible endpoint) and the AI provider window |
| `BotEngine.swift`, `BotCanvasView.swift`, `GreetingCanvasView.swift`, `UploadCanvasView.swift` | Deleted: Coucou's character and the canvases that drew it. The last versions are in git history (`git show 43a5ada:mac-demo/NotchBuddy/Sources/App/BotEngine.swift`) and in the upstream Coucou repo. Read them for technique only; Mochi's look, expressions and animations are reserved |
| `AppDelegate.swift`, `AppState.swift` | No hooks or pollers. A single "tomo" task. Launches straight into the game. "Start Tomo over…" asks first |
| `IslandRootView.swift`, `IslandViewContent.swift`, `IslandTypes.swift` | The header and overview show Tomo. The island is taller. Draws `TomoCharacterView`; no greeting or upload canvas |
| `IslandWindowController.swift` | Taller window (560 pt) so the help panel fits; the island's frame includes the help panel. The drag ghost draws `TomoCharacterView` |
| `NotchBuddyApp.swift` | The Settings scene shows `TomoSettingsView` |
| `project.yml`, `Resources/Info.plist` | App name Tomodachi, bundle ID `com.zenbujapanese.tomodachi`, microphone and speech permission text (Coucou's French strings removed), Release signing for beta builds |
| `SoundEngine.swift`, `Resources/sounds/` | `SoundEngine` is now a shim that sends the island's open/close/peek to `TomoSounds`; Coucou's 28 sound files are deleted |
| `ClaudeService.swift` | Keychain service renamed to `co.zenbu.tomodachi` (kept, so saved keys still load) |

Debug only:
- `TOMO_AUTOPLAY=1` answers picture rounds by itself (one miss, then right).
- `TOMO_STAGE=3 TOMO_AUTOCHAT="しごと してる|うん"` starts a testing Tomo at that age and types those answers. Testing ages run in memory; saved progress isn't touched.
- `TOMO_DATA_DIR=/path` keeps saved progress in that folder instead of Application Support. **Use a temporary folder for test runs**, so they never change the learner's own Tomo.
- `TOMO_TIME_TRAVEL=<hours>` starts Tomo's clock that far ahead, so due words come back without waiting. Settings → "Skip ahead a day (testing)" adds a day until you quit. Answers given while ahead are saved with those dates.
- `TOMO_SELFTEST=1` checks the word-stage and level rules and the store in a temporary folder, prints each check, and quits (exit code 1 on a failure).
- `TOMO_DROPIN_EVERY=8` sets the seconds between visits; `TOMO_NUDGE_EVERY=5` sets the seconds between nudge bounces.
- `TOMO_TARGET=es` and `TOMO_LEARNER=en` pick the language pair.
- `TOMO_SNAPSHOT_DIR=/path` saves a PNG of the island every second; with `TOMO_OPEN_SETTINGS=1` it also captures the Settings window.
- `TOMO_RENDER_ICON=/path` renders the icon images and quits.
- `TOMO_RENDER_SHEET=/path` renders `tomo-sheet.png` (every age and face of the character) and quits.
- `TOMO_RENDER_SOUNDS=/path` writes every sound effect at every age as a WAV, plus `all-sounds.wav`, and quits.
- `TOMO_RENDER_ANIM=/path` renders a scripted 16-second scene as `frame-0000.png`… (20 fps) and quits. Join the frames into a GIF to check motion.

## License note

Coucou's **code** is MIT (see `LICENSE`). Its name, its Mochi character and its **sounds** are not (see `LICENSE-ASSETS.md`).

- **Replaced:** Coucou's sounds (deleted; Tomo's are synthesized in `TomoSounds.swift`) and its icons (drawn from Tomo's code).
- **Replaced:** the character. Tomo is our own chick (`TomoCharacter.swift`); Coucou's character code is deleted, so no permission is needed.
- **Still open (issue #1):** Coucou names in code and comments, the sound files, and leftover features.
