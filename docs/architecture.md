# Architecture: systems and seams

How the demo is put together, and where each part plugs in as it grows. Change code behind these seams. When a seam moves, update this page in the same change.

All paths are under `mac-demo/NotchBuddy/Sources/App/`.

## Layers

```
Island shell (Coucou)       notch window, open/close state machine, click-through
  └─ Character (BotEngine)  Tomo's body, eyes, states, emotes, growth
  └─ Tomo app               TomoGame (flow) · TomoView (UI)
       ├─ Content           what Tomo says at each age
       ├─ Answer checking   offline matcher → AI fallback
       ├─ Conversation AI   TomoAI provider adapter
       ├─ Voice out / in    speech synthesis · speech recognition
       ├─ Visits            when Tomo drops in, when it leaves
       ├─ Growth rules      when Tomo gets older
       └─ Learner store     words seen, understood, said (not built)
```

## Systems

| System | Today (file) | Seam to keep | What plugs in later | Research |
|---|---|---|---|---|
| **Island shell** | Coucou: `IslandWindowController`, `IslandStateMachine`, `IslandRootView`, `IslandTypes` (layouts) | `TomoGame.openIsland` / `closeIsland` / `isIslandOpen` / `focusInput` closures, wired in `AppDelegate` | iPhone/widget shells would set the same closures | — |
| **Character** | `BotEngine` (Coucou engine, reskinned: egg shape, peach colors, sprout, `talk()`, `grow`), `BotCanvasView` | Notifications: `.botTalk`, `.botGrow` (0/1/2), `.botGreet`, `.triggerEmote`, and task state through `AppState.updateTask("tomo", …)` | Original Tomo art direction; per-age looks | — |
| **Content** | Hard-coded `stage1` / `stage2` rounds in `TomoGame.swift`, `tomoStarters` in `TomoChat.swift` | `TomoRound` and `TomoLine` structs | Data files per age, keyed by Language Reference ID and built from age vocabulary data | [age-vocabulary-data.md](research/age-vocabulary-data.md) |
| **Answer checking** | `TomoBrain.reply`: AI if configured, otherwise the `offlineReply` keyword placeholder | `TomoBrain.reply(to:ai:) -> TomoReply` (`say`, `understood`, `mood`) | The Zenbu offline dictionary system as the first check; AI only for leftovers | [answer-evaluation.md](research/answer-evaluation.md) |
| **Conversation AI** | `TomoAI.complete(system:user:config:)`: the Anthropic API plus any OpenAI-compatible endpoint. The prompt is `TomoBrain.system` | `TomoAI.complete` is the only network call to an AI. `TomoAIConfig` holds the provider, URL, model and key | More presets; per-age prompts; caching | [ai-models-and-costs.md](research/ai-models-and-costs.md) |
| **AI config** | `TomoAI.config`: the saved provider (UserDefaults + Keychain), else `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` from the environment (`run.sh` loads `.env`) | `TomoAISettingsView` window (menu → AI provider…) | Account-level keys from a backend | — |
| **Voice out** | `TomoGame.speak(_:slow:)`: `AVSpeechSynthesizer`, ja-JP, pitch ×1.6 | Every line goes through `speak()` | A `TomoVoice` adapter: Apple, VOICEVOX, cloud TTS, pre-rendered clips; voice that ages with Tomo | [voices.md](research/voices.md) |
| **Voice in** | `TomoListener`: Apple speech recognition, on-device only | `toggle(onPartial:onDone:)` | Recognition hints (the question's expected words); other recognizers | [answer-evaluation.md](research/answer-evaluation.md) |
| **Visits** | `DropIn` constants and `TomoGame.tick()`: every 10 min, leave after 10 s ignored (20 s at 3さい), 3 answers per visit, wait while typing | `DropIn` enum; `dropIn(force:)` | User settings (quiet/normal/chatty), busy detection (calls, full-screen, Focus) | [user-journey.md](user-journey.md) |
| **Growth rules** | `TomoGame.stageGoal`: 5 words → 2さい, 5 phrases → 3さい, 10 good replies (placeholder) | `progress` / `goal` / `growUp()` | A point system, "known" rules, anti-cram | [leveling-points.md](research/leveling-points.md) |
| **Learner store** | None. Progress is in memory and resets on relaunch | — | Local SQLite event log keyed by Language Reference ID; sync with Zenbu apps later | [learner-data-schema.md](research/learner-data-schema.md) |

## Coucou code that's still there but switched off

`HookServer`, the `*Poller` integrations, `PillCatalog`, the upload/mail/file-drop flow, `SettingsView`, `WindowContextCapture`, and `GreetingCanvasView`. It compiles but isn't started. Remove it when the shell stabilizes. Two exceptions:
- **Keep the `Keychain` helper in `ClaudeService.swift`**, which `TomoAI` uses.
- **Consider `WindowContextCapture`** for the "Tomo names what's on your screen" idea.
