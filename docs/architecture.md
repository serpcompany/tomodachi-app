# Architecture: systems and seams

How the demo is put together, and where each part plugs in as it grows. Change code behind these seams. When a seam moves, update this page in the same change.

All paths are under `mac-demo/NotchBuddy/Sources/App/`.

## Layers

```
Island shell (Coucou)       notch window, open/close state machine, click-through
  └─ Character (TomoChick)  Tomo the chick: body, faces, moves, growth
  └─ Tomo app               TomoGame (flow) · TomoView (UI)
       ├─ Content source    what Tomo brings: the age track (language packs)
       ├─ Answer checking   offline matcher → AI fallback
       ├─ Conversation AI   TomoAI provider adapter
       ├─ Voice out / in    speech synthesis · speech recognition
       ├─ Sound effects     TomoSounds: synthesized peeps and blips
       ├─ Visits            when Tomo drops in, when it leaves
       ├─ Growth            word stages, levels, ages (TomoProgress)
       └─ Learner store     saved progress and answer log (TomoStore, SQLite)
```

## Systems

| System | Today (file) | Seam to keep | Planned (issues) | Research |
|---|---|---|---|---|
| **Island shell** | Coucou: `IslandWindowController`, `IslandStateMachine`, `IslandRootView`, `IslandTypes` (layouts) | `TomoGame.openIsland` / `closeIsland` / `isIslandOpen` / `focusInput` closures, wired in `AppDelegate` | iPhone and widget shells set the same closures ([#30](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/30)) | — |
| **Character** | `TomoCharacter.swift`: `TomoChick` (our own hiyoko chick: drawing, faces, moves, particles) and `TomoCharacterView` (the Canvas in the island). Growth 0 = in its eggshell, 1 = hatched, 2 = bigger. Idle life (`fidget()`, saccades, breathing, feather spring, dozing) runs on its own. Time comes from `clock`, so scenes can be rendered offline: `TOMO_RENDER_SHEET` (every age and face) and `TOMO_RENDER_ANIM` (a scripted 16 s scene, frame by frame) | Notifications: `.botTalk`, `.botNudge`, `.botGrow` (0/1/2, animated), `.botSetGrowth` (no animation: launch, switching pairs), `.botLevelUp`, `.botGreet`, `.botGulp`, `.triggerEmote`, `.triggerSlap`, and task state through `AppState.updateTask("tomo", …)` | More faces and moves, looks beyond 3さい ([#22](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/22)); variants ([#23](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/23)) | [decisions.md](decisions.md) |
| **Languages** | `TomoLanguage.swift`: `TargetPack` (`Resources/languages/<id>.json`), `LearnerPack` (`ui.<id>.json`), `TomoLanguages.shared` (the selection), `LanguageContext` (the pair, passed to background work) | No language-specific text in Swift. Everything goes through the pack or learner strings | More packs, String Catalogs, translations from the dictionary ([#34](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/34)) | [languages.md](languages.md) |
| **Content sources** | One source, the age track: the language pack's `levels` (each level's rounds or starters), turned into `TomoRound` / `TomoLine` for the learner's language. `TomoProgress` picks the items; `TomoGame` asks them | `TomoRound` and `TomoLine` structs. A `TomoContentSource` seam is planned ([#10](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/10)) | The seam ([#10](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/10)); Anki ([#11](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/11)); other sources ([#12](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/12)); age-track words from the Zenbu learning system ([#13](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/13)) | [age-vocabulary-data.md](research/age-vocabulary-data.md) |
| **Answer checking** | `TomoBrain.reply`, in layers. (1) `languageGate` (`TargetPack.looksLikeTarget`): not in the target language, no credit, and no AI call. (2) AI if configured. (3) Otherwise the pack's `offlineReplies` placeholder | `TomoBrain.reply(to:ai:) -> TomoReply` (`say`, `understood`, `mood`) | The Zenbu dictionary as the first check, AI only for leftovers ([#6](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/6)) | [answer-evaluation.md](research/answer-evaluation.md) |
| **Conversation AI** | `TomoAI.complete(system:user:config:)`: the Anthropic API plus any OpenAI-compatible endpoint. The prompt is `TomoBrain.systemPrompt(language)`: a shared template plus the pack's persona and rules | `TomoAI.complete` is the only network call to an AI. `TomoAIConfig` holds the provider, URL, model and key | JSON schema, `reasoning_effort`, presets, per-age prompts, caching ([#8](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/8)); model choice ([#7](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/7)) | [ai-models-and-costs.md](research/ai-models-and-costs.md) |
| **AI config** | `TomoAI.config`: the saved provider (UserDefaults + Keychain), else `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` from the environment (`run.sh` loads `.env`) | `TomoAISettingsView` (Settings → AI) | A shared AI server that holds our key ([#32](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/32)) | — |
| **Voice out** | `TomoGame.speak(_:slow:)`: `AVSpeechSynthesizer`, the pack's `speechLocale`, pitch ×1.6 | Every line goes through `speak()` | A `TomoVoice` adapter and a voice that ages with Tomo ([#5](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/5)) | [voices.md](research/voices.md) |
| **Sound effects** | `TomoSounds.swift`: every effect synthesized in code on first use (no audio files) and played through `AVAudioEngine`. Peeps drop in pitch as Tomo grows. Follows the same switch as the voice (`AppState.soundEnabled`). `SoundEngine` is a shim that sends the island's open/close to it | All triggers in one place: `TomoSounds.listen()` (character notifications) and `outcome(_:)` (Win / Miss / No score, from `TomoGame.outcome`). New sounds = a new `Effect` case + its notes. `TOMO_RENDER_SOUNDS` writes them all as WAVs | Effects switch, volume, tuning ([#21](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/21)) | [decisions.md](decisions.md) |
| **Voice in** | `TomoListener`: Apple speech recognition in the pack's `recognitionLocale`, on-device only | `toggle(onPartial:onDone:)` | Recognition hints, other recognizers ([#17](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/17)) | [answer-evaluation.md](research/answer-evaluation.md) |
| **Visits** | `DropIn` constants and `TomoGame.tick()`: every 20 min by default (Settings → General, saved as `tomoVisitEvery`; 0 = only when clicked), leave after 10 s ignored (20 s at 3さい), up to 3 answers per visit, the first at launch. A visit's items come from `TomoProgress.visitItems`; a scheduled visit with nothing due or new is skipped and rechecked every `DropIn.recheck` (5 min). Launch and "Drop in now" fill up with practice; in a visit, practice never repeats the item just asked. If you're typing, a visit retries in 20 s; after 5+ min with no input, it waits. Hovering, listening or an open help panel keeps a visit open. `dismiss()` (× button) and Esc close it. An unfinished visit sets `pending`: a red dot (`TomoPendingDot`) and a `.botNudge` bounce every `nudgeEvery` | `DropIn` enum; `dropIn(force:)`, `dismiss()`, `pending` | Chattiness, back-off, natural breaks ([#19](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/19)); busy detection ([#20](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/20)) | — |
| **Growth** | `TomoProgress.swift`: `TomoSRS` (stages 0–9, the waits, the wrong-try rule), levels (`levelUpIfReady`: 90% of a level at "knows it"; a level with a higher age is a birthday), what to ask (`visitItems`: due first, then ≤1 new; `nextFreePlayItem`; `practiceItem`; 10 new a day, the day starts at 4 am), `TomoClock` (a testing offset). `TomoGame` publishes `stage` (age), `level`, `levelKnown`, `levelNeeded` for the header. `TOMO_SELFTEST=1` checks the rules | `visitItems` / `answeredRight` / `logTry` / `levelUpIfReady`; testing ages use `scratch(age:)`, an in-memory Tomo | Growing past 3さい, a pace estimate, adaptive scheduling (swift-fsrs) behind the same stages ([#38](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/38)) | [leveling-points.md](research/leveling-points.md) |
| **Help panel** | `TomoGame.help` (`.hint` / `.explain` / `.word`) → `AppState.helpPanelHeight`. The island grows by `TomoGrid.helpHeight` and draws `TomoHelpPanel` under the card. The window is 560 pt tall and transparent; clicks only land inside the island's current shape | One help view at a time. New help modes become new `TomoHelp` cases | Learning modes could use it ([#14](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/14)) | — |
| **Dictionary / word cards** | Prototype: `TomoWords.swift` (clickable words via `TomoLineView`, `TomoBrain.define` AI meaning, the Mac dictionary via `DCSCopyTextDefinition`); `TomoBrain.explain` / `simpler`; all drawn by `TomoHelpPanel` in `TomoView.swift` | A per-target-language provider: `segment(text) → tokens` (surface, dictionary id, range) and `lookup(id, learner) → word card` | The Zenbu dictionary for Japanese ([#9](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/9)); other targets ([#31](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/31)) | — |
| **Settings** | `TomoSettingsView.swift`: a System Settings–style window (sidebar + page). Pages: Tomo (`TomoGrowthPane`: live `TomoLiveAvatar`, level bar, growing up, today), Words (`TomoWordsPane` in `TomoWordsView.swift`), General, AI (`TomoAISettingsView`), Testing, About. Opened by `AppDelegate.openSettings`; `TomoSettingsNav.open(_:)` picks the page (header age → Tomo, menu Tomo's words… → Words). Pages read `TomoGame.progress` and refresh on `progressVersion` | `TomoSettingsPane` (one case per page); text from `settings.pane.*`, `growth.*`, `stage.*` strings | Word cards from the Words page, a pace estimate ([#38](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/38)) | — |
| **Learner store** | `TomoStore.swift`: SQLite at `~/Library/Application Support/com.zenbujapanese.tomodachi/learner.sqlite` (`TOMO_DATA_DIR` overrides it). Tables `tomo` (level, age, met date) and `item` (stage, due date, counts), plus append-only `answer` and `growth` logs. Keyed by (learner, target): one Tomo per pair. Start over clears `tomo` and `item`; the logs stay | `loadTomo` / `saveTomo` / `loadItems` / `saveItem` / `logAnswer` / `logGrowth` / `clear` | Language Reference IDs as item ids; sync with the Zenbu apps ([#28](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/28)) | [learner-data-schema.md](research/learner-data-schema.md) |

## Sound effects

All in `TomoSounds.swift`, synthesized from pitch sweeps (no audio files). Peeps drop in pitch at 2さい (×0.9) and 3さい (×0.82). Listen with `TOMO_RENDER_SOUNDS=<dir>` (`all-sounds.wav` plays them in this order).

| Effect | When | Sounds like | Triggered by |
|---|---|---|---|
| `greet` | A visit starts | two "piyo" peeps | `.botGreet` |
| `win` | Win | three rising chirps | `TomoGame.outcome` = `.win` |
| `miss` | Miss | soft falling "boo-oop" | `TomoGame.outcome` = `.loss` |
| `hm` | No score | questioning upward glide | `TomoGame.outcome` = `.neutral` |
| `hatch` | Tomo hatches or grows up (a birthday level) | pop, then a rising arpeggio | `.botGrow` to a higher step |
| `levelUp` | Tomo reaches a new level | quick rising chirps and a sparkle | `.botLevelUp` |
| `boing` | Tomo is clicked | wobbly falling boing | `.triggerSlap` |
| `nudge` | Waiting for you (red dot) | two quick high peeps | `.botNudge` |
| `munch` | Feeding | two crunchy low blips | `.botGulp` |
| `trill` | Love | quick alternating trill | `.triggerEmote` `.love` |
| `yawn` | Yawn | long falling breathy glide | `.triggerEmote` `.yawn` |
| `open` / `close` | The island opens / closes | soft rising / falling blip | `SoundEngine.play("open"/"close")` (shim) |
| `tick` | Tomo peeks out of the notch | tiny click | `SoundEngine.play("peek")` (shim) |

Status: fine for now (2026-10-05); tuning is [#21](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/21). Tomo's spoken lines don't get an effect (the voice is the sound).

## Coucou code that's still there but switched off

`HookServer`, the `*Poller` integrations, `PillCatalog`, the upload/mail/file-drop flow, `SettingsView` and `WindowContextCapture`. (Coucou's character, greeting and upload canvases are deleted.) It compiles but isn't started. Removing it is part of [#1](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/1). Two exceptions:
- **Keep the `Keychain` helper in `ClaudeService.swift`**, which `TomoAI` uses.
- **`WindowContextCapture`** may help with [#24](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/24) (Tomo names what's on your screen).
