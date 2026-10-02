# Tomodachi notch demo (macOS)

A click-through demo of the Tomodachi idea: Tomo lives in the MacBook notch and talks like a 1-year-old Japanese child. You show you understood by picking the right picture or by doing what it asks (feed, bed, hug). After 5 words, Tomo grows up to 2さい, sprouts a leaf, and starts using two-word phrases.

Forked from [Coucou](https://github.com/Louis-CFM/coucou) (MIT code). Coucou's coding-agent hooks and integrations are switched off, not deleted.

## Run

```bash
./run.sh   # from mac-demo/
```

`run.sh` loads `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` from the repo's `.env` (gitignored) and passes it to the app, so Tomo replies with AI at 3さい (OpenAI default: `gpt-5.4-mini`). A provider saved under menu → **AI provider…** takes precedence. Without either, Tomo uses offline replies. You can also run `open build/Build/Products/Debug/Tomodachi.app`, which skips the AI keys.

Tomo opens on its own every 10 minutes for a 3-answer visit. If you ignore it for 10 seconds, it tucks back in. In between, it sits small beside the notch: click it to play any time, and press Esc to close.

The menu bar icon has:
- **Open Tomo**
- **Drop in now** (⌘D)
- **Restart demo** (⌘R)
- **Skip to 3さい (talking)** (⌘3): Tomo asks questions and you answer by typing Japanese or with the mic
- **AI provider…** (⌘,): pick any provider (Anthropic, OpenAI, Gemini, OpenRouter, Groq, Ollama, or custom OpenAI-compatible), paste a key (stored in the Keychain), fetch models, and test

## Rebuild

```bash
cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath ../build build
```

## What changed from Coucou

| File | Change |
|---|---|
| `Sources/App/TomoGame.swift` | New. Word lists for stages 1–2, rounds, growth, and the Japanese voice (`AVSpeechSynthesizer`, ja-JP, raised pitch) |
| `Sources/App/TomoView.swift` | New. Island card, picture/action tiles, header status |
| `Sources/App/TomoChat.swift` | New. 3さい questions, replies (AI if configured, offline otherwise), on-device Japanese speech recognition |
| `Sources/App/TomoAI.swift` | New. Provider adapter (Anthropic API + any OpenAI-compatible endpoint) and the AI provider window |
| `BotEngine.swift` | Peach egg-shaped body, a sprout when grown, a hop when talking, softer state tint |
| `AppDelegate.swift`, `AppState.swift` | No hooks or pollers. A single "tomo" task. Launches straight into the game |
| `IslandRootView.swift`, `IslandViewContent.swift`, `IslandTypes.swift` | The header and overview show Tomo. The island is taller |

Debug only:
- `TOMO_AUTOPLAY=1` plays stages 1–2 by itself.
- `TOMO_STAGE=3 TOMO_AUTOCHAT="しごと してる|うん"` starts at the talking stage and types those answers.
- `TOMO_DROPIN_EVERY=8` sets the seconds between visits.
- `TOMO_SNAPSHOT_DIR=/path` saves a PNG of the island every second.

## License note

Coucou's **code** is MIT (see `LICENSE`). Its name, its Mochi character and its **sounds** are not (see `LICENSE-ASSETS.md`). For that reason, Coucou's sound effects are off by default. The menu toggle that turns them on is for private use only. Before showing this publicly, replace those sounds and finish making the character your own.
