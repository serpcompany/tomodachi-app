# Backlog: features and ideas

Everything we want, with its status. When something moves, update it here in the same change.

**Status:** Built (works in `mac-demo/`) · Next (agreed direction) · Researched (findings in `docs/research/`) · Idea (not decided)

## Built in the demo

| Feature | Notes |
|---|---|
| Tomo in the notch, small between visits, click for free play | Coucou island shell |
| 1さい single words, 2さい two-word phrases: tap a picture or do the action | Content in the language packs (`Resources/languages/<id>.json`) |
| Baby word + "grown-ups say" reveal (ワンワン → いぬ) | |
| Growing up: hatches from its eggshell at 2さい, bigger with a third feather at 3さい | Placeholder thresholds |
| Drop-in visits: every 20 min by default, 3 answers, leave after 10 s ignored | Frequency in Settings → General (10 min to 2 h, or only when clicked) |
| Talking stage works at any age (3, 5, 7, 10, 12…): reply length and style grow with age; packs can set rules and opening questions per age band (`rulesByAge`, `startersByAge`). English has a 7+ band. Settings → "Try another age (testing)" | Ages beyond 3 can't be earned yet; growth thresholds are a leveling-research item |
| Settings window: languages, visit frequency (10 min to 2 h, or click-only), voice, AI provider, About | `TomoSettingsView` |
| Own app and menu bar icon, drawn from the character code | `TomoIconRenderer`, `scripts/make-icons.py` |
| Signed + notarized beta builds for testers (0.0.1) | `scripts/release-beta.sh`; tester guide in [beta-testing.md](beta-testing.md) |
| Win / Miss / No score badge after every answer; help requests ("what?", なに？) repeat the question and open the hint | `TomoOutcome`, `OutcomeBadge`; phrases in the packs (`helpPhrases`) |
| Dismiss with × or Esc; after an unfinished visit, a red dot and a bounce every 60 s until you check in | `DropIn.nudgeEvery` |
| Conversation: typed or spoken answers | Opening questions per age from the pack (`startersByAge`) |
| AI provider adapter (Anthropic + any OpenAI-compatible), Settings → AI | Default OpenAI `gpt-5.4-mini` via `.env` |
| Sound effects synthesized in code (peeps, chirps, Win / Miss / No score, hatch, poke, love, yawn, island blips) | `TomoSounds.swift`; same switch as the voice |
| Japanese voice out (Apple TTS) and voice in (Apple, on-device only) | The mic isn't tested by hand yet |
| Language pairs: any learner language × any target language, via data files | Learn Japanese, English or Spanish (drafts); interface in English or Japanese. Japanese speakers can learn English. See [languages.md](languages.md) |

## Next

| Feature | Status | Notes |
|---|---|---|
| Save learner progress (words seen/understood/said, Tomo's age) | Researched | [learner-data-schema.md](research/learner-data-schema.md): local SQLite event log keyed by Language Reference ID |
| Point and level-up system (days, not minutes) | Researched | [leveling-points.md](research/leveling-points.md): no points shown. Each word has a hidden memory strength (simplified FSRS), credited at most once per day, with up to 10 new words a day. A word is known at 4+ days of strength. Tomo grows in half-years at 50 / 150 / 280 / 450 known words. Simulated: 10 visits a day reach 2さい around day 27 and 3さい around day 77, and cramming doesn't help. Never forgets; no streaks. All parameters are guesses, so log every answer to tune them later |
| Better child-like voice that ages with Tomo | Researched | [voices.md](research/voices.md): **VOICEVOX** (free, offline, can be embedded; credit like "VOICEVOX:<character>" required). Next: a one-day listening test, then pre-render the fixed stage 1–2 lines. Apple's voices are adult-only and can't be used for pre-rendered clips (license). No cloud provider has a Japanese child voice. Later: a custom voice from a hired actor |
| Plug in the Zenbu offline dictionary system to check answers; AI only for leftovers | Researched | [answer-evaluation.md](research/answer-evaluation.md). Don't polish the current keyword matcher |
| Pick the AI model with a small test set; control cost | Researched | [ai-models-and-costs.md](research/ai-models-and-costs.md): recommends Claude Haiku 4.5 (about $0.38 per active 3さい learner per month at 70% offline). Cheaper options: Gemini 3.1 Flash-Lite and GPT-6 Luna (reasoning off). Free on-device: Apple Foundation Models (macOS 26+). We run `gpt-5.4-mini` because that's the key we have. Decide with the doc's 32-line test set. Heads-up: Haiku 4.5's retirement window opens 2026-10-15 |
| Click a word → word card; drag across words → "I don't understand" → explanation; Explain button (meaning, key parts, tip, ask about a part, "say it simpler") | Built (prototype) | The word card shows an AI meaning in context, the Mac's built-in dictionary (Dictionary Services, offline), Open in Dictionary, and Open in Zenbu. Still to come: the Zenbu dictionary with Language Reference IDs, pitch, ✓ Known, and underlined unknown words |
| Tap any word for a dictionary card (like the Zenbu app's Player): linked words in Tomo's lines, unknown words underlined, card with reading, pitch, meaning in your language, 🔊, grown-up word, ✓ Known, and Open in Zenbu | Next (full version) | [user-journey.md](user-journey.md) §4. Japanese uses the Zenbu dictionary and Language Reference IDs. Known words shared with the Zenbu apps |
| Learning modes + a mode scheduler | Researched | [learning-modes.md](research/learning-modes.md). The modes can be built now; how the scheduler picks words waits for the content logic (Ideas, below). MVP: Teach a new word, Picture choice, Do what Tomo says (6–8 verbs), Listen and translate (sound only, tap a meaning), What's this? (say or type it), Fix Tomo's mistake, Conversation. Scheduler: pick words first (due first, ≤1 new per visit, ≤10 per day), then a mode from each word's state (new → teach; met → recognize; known → produce; can say → conversation or fix-the-mistake). Ages unlock modes; never the same mode twice in a row; 30 s per visit |
| 2さい reply bubbles + "say this word" (between tapping and free talk) | Next | The answer ladder in [user-journey.md](user-journey.md) §3 |
| Native-speaker review of the language packs (ja, es) | Next | Both are drafts (`reviewedByNativeSpeaker: false`) |
| Save progress per language pair; one Tomo per target language | Next | Key the learner store by (learner, target) |
| Debrand: remove Coucou, Mochi and Grok Bot names, assets and leftovers | Next (character and sounds done: Tomo is our own chick with its own synthesized sounds; names and leftover features remain) | [serpcompany/zenbujapanese-tomo-app#1](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/1). Required before showing publicly (license). Keep the MIT notice and one credit line |
| Judge answers in layers, never by AI alone: (1) right language (built); (2) on-topic via the Zenbu dictionary + per-question expected answers; (3) AI fills yes/no verdict fields that code double-checks. Outcomes Win / Miss / No score are built and shown as badges | Next (layers 2–3) | Seen live: `gpt-5.4-mini` accepted "car" as understood. Layer 1 now blocks that |
| Adapter: send a JSON schema and `reasoning_effort` per provider | Next | From ai-models-and-costs.md: guarantees Tomo's JSON shape; avoids paying for unneeded reasoning |
| Speech recognition hints: pass the question's expected words as `contextualStrings` | Next | From voices.md / answer-evaluation.md |
| Try Apple's on-device model as a free AI tier | Idea | Japanese supported per Apple; needs macOS 26+ |
| Visit settings: quiet / normal / chatty, ignore timeout | Idea | Keep it simple for now |
| Busy detection: calls, full-screen video, Focus mode | Idea | Open question in user-journey.md |

## Ideas (later)

- **What Tomo asks and does (content logic).** Which words, questions and activities Tomo picks. Deferred: it will tie into the other Zenbu Japanese apps (dictionary, Language Reference IDs, what the learner knows there), not only child-age word lists. Pack content is a placeholder until then. The child-vocabulary research ([age-vocabulary-data.md](research/age-vocabulary-data.md)) is background only; no license requests needed. See [decisions.md](decisions.md).

- **Sound polish:** the synthesized effects are fine for now; later, tune volume and timbre from tester feedback, maybe a separate effects switch and volume in Settings. The list is in [architecture.md](architecture.md#sound-effects).
- **Character polish (ideas from Coucou's old engine, rebuilt our own way):** a fuller head turn (eyes and beak sliding around the body like a ball), a soft glow or tint per mood, wing "hands" that wave, point or cover the eyes.
- **Character options.** Notchi and Buddi (other open notch companions) are GPL-3.0, so they can't go in a closed app. Real options:
  - variants from our own engine (shape, colors, accessories; maybe one per target language)
  - a commissioned original character (code-drawn or Rive)
  - CC0 art (Kenney)

  All of these tie into issue #1, since Tomo's expressions still come from Coucou's engine.

- **Named word stages in the word book** (WaniKani-style, in Tomo's voice): "Tomo just heard it" → "Tomo knows it" → "Tomo's favorite word". Progress you can see, with no points.

- **Watch a show together:** at 3さい+, Tomo chats while you watch kids' shows in Japanese (from the README).
- **Tomo names what's on your screen:** drag Tomo onto a window and it names things it sees in baby Japanese. Coucou's `WindowContextCapture` is a starting point.
- **なんで？ phase at 4さい:** Tomo asks "why?" about everything, and you explain in simple sentences.
- **Time of day:** おはよう in the morning, まんま at lunch, ねんね at night.
- **Voice that matures** from 1さい to 5さい.
- **Share card:** "My Japanese is like a 3-year-old's."
- **Sync with the Zenbu iOS/web apps:** shared known words via Language Reference IDs.
- **iPhone surfaces (after the foundation; needs the `TomoCore` split first):** based on the cross-device concept in [docs/reference/grokbot1.PNG](reference/grokbot1.PNG) (a design mockup, not an app).
  - **Lock screen visits:** an interactive Live Activity where Tomo asks まんま！ and you tap 🍙 / 😴 / 🤗 without opening the app.
  - **Home screen widget:** small Tomo showing its age and mood, with tap-to-play buttons.
  - **Watch:** tiny Tomo with one-tap answers.
  - Option: host Tomo inside the existing Zenbu iPhone app instead of a separate app.

## Open product questions

- Dictionaries for non-Japanese targets: for a Japanese speaker learning English, the Zenbu dictionary works in reverse (JMdict's English meanings → Japanese words), but it's not an English dictionary. Which source for English and Spanish word cards (licenses)?
- AI for testers: they bring their own key or get offline replies. Shared AI needs a small server that holds our key (never ship a key inside the app).

- From leveling-points.md: switch to half-year ages (1さい半, 2さい半)? Move reply bubbles from 2さい to 1さい半?

- Does Tomo open on its own (it does now), or peek and wait for a click?
- Default visit frequency for a new user.
- Transcripts: off, kept on this Mac, or synced?
- How Tomo's "known" relates to the iOS app's manual Known words.
