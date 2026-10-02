# Backlog: features and ideas

Everything we want, with its status. When something moves, update it here in the same change.

**Status:** Built (works in `mac-demo/`) · Next (agreed direction) · Researched (findings in `docs/research/`) · Idea (not decided)

## Built in the demo

| Feature | Notes |
|---|---|
| Tomo in the notch, small between visits, click for free play | Coucou island shell |
| 1さい single words, 2さい two-word phrases: tap a picture or do the action | Content hard-coded in `TomoGame.swift` |
| Baby word + "grown-ups say" reveal (ワンワン → いぬ) | |
| Growing up: sprout at 2さい, bigger at 3さい | Placeholder thresholds |
| Drop-in visits: every 10 min, 3 answers, leave after 10 s ignored | No settings yet |
| 3さい conversation: typed or spoken answers | 5 starter questions |
| AI provider adapter (Anthropic + any OpenAI-compatible), AI provider window | Default OpenAI `gpt-5.4-mini` via `.env` |
| Japanese voice out (Apple TTS) and voice in (Apple, on-device only) | The mic isn't tested by hand yet |

## Next

| Feature | Status | Notes |
|---|---|---|
| Save learner progress (words seen/understood/said, Tomo's age) | Researched | [learner-data-schema.md](research/learner-data-schema.md): local SQLite event log keyed by Language Reference ID |
| Real age vocabulary for each stage (what Tomo can say vs understand) | Researched | [age-vocabulary-data.md](research/age-vocabulary-data.md): ages 1–3 from Wordbank's Japanese CDI data (CC BY 4.0, 891 kids; half say 79 words by 23 months and 574 by 35 months). Ages 3–6 from NINJAL's preschool-speech and picture-book lists (CC BY 4.0) plus JMdict's children's-language and onomatopoeia tags (needs a vulgarity block-list). Each word gets a `say_age` and an `understand_age`, keyed by Language Reference ID. Before speaking, Tomo's lines are checked against its age list |
| Point and level-up system (days, not minutes) | Researched | [leveling-points.md](research/leveling-points.md): no points shown. Each word has a hidden memory strength (simplified FSRS), credited at most once per day, with up to 10 new words a day. A word is known at 4+ days of strength. Tomo grows in half-years at 50 / 150 / 280 / 450 known words. Simulated: 10 visits a day reach 2さい around day 27 and 3さい around day 77, and cramming doesn't help. Never forgets; no streaks. All parameters are guesses, so log every answer to tune them later |
| Better child-like voice that ages with Tomo | Researched | [voices.md](research/voices.md): **VOICEVOX** (free, offline, can be embedded; credit like "VOICEVOX:<character>" required). Next: a one-day listening test, then pre-render the fixed stage 1–2 lines. Apple's voices are adult-only and can't be used for pre-rendered clips (license). No cloud provider has a Japanese child voice. Later: a custom voice from a hired actor |
| Plug in the Zenbu offline dictionary system to check answers; AI only for leftovers | Researched | [answer-evaluation.md](research/answer-evaluation.md). Don't polish the current keyword matcher |
| Pick the AI model with a small test set; control cost | Researched | [ai-models-and-costs.md](research/ai-models-and-costs.md): recommends Claude Haiku 4.5 (about $0.38 per active 3さい learner per month at 70% offline). Cheaper options: Gemini 3.1 Flash-Lite and GPT-6 Luna (reasoning off). Free on-device: Apple Foundation Models (macOS 26+). We run `gpt-5.4-mini` because that's the key we have. Decide with the doc's 32-line test set. Heads-up: Haiku 4.5's retirement window opens 2026-10-15 |
| 2さい reply bubbles + "say this word" (between tapping and free talk) | Next | The answer ladder in [user-journey.md](user-journey.md) §3 |
| Move content out of code into data files | Next | Needed before real vocabulary lands |
| Own character art and sounds; remove Coucou leftovers | Next | Required before showing publicly (license) |
| Adapter: send a JSON schema and `reasoning_effort` per provider | Next | From ai-models-and-costs.md: guarantees Tomo's JSON shape; avoids paying for unneeded reasoning |
| Speech recognition hints: pass the question's expected words as `contextualStrings` | Next | From voices.md / answer-evaluation.md |
| Try Apple's on-device model as a free AI tier | Idea | Japanese supported per Apple; needs macOS 26+ |
| Visit settings: quiet / normal / chatty, ignore timeout | Idea | Keep it simple for now |
| Busy detection: calls, full-screen video, Focus mode | Idea | Open question in user-journey.md |

## Ideas (later)

- **Watch a show together:** at 3さい+, Tomo chats while you watch kids' shows in Japanese (from the README).
- **Tomo names what's on your screen:** drag Tomo onto a window and it names things it sees in baby Japanese. Coucou's `WindowContextCapture` is a starting point.
- **なんで？ phase at 4さい:** Tomo asks "why?" about everything, and you explain in simple sentences.
- **Time of day:** おはよう in the morning, まんま at lunch, ねんね at night.
- **Voice that matures** from 1さい to 5さい.
- **Share card:** "My Japanese is like a 3-year-old's."
- **Sync with the Zenbu iOS/web apps:** shared known words via Language Reference IDs.
- **iPhone, Watch, widgets:** the Grok Bot reference showed this across devices.

## Open product questions

- From leveling-points.md: switch to half-year ages (1さい半, 2さい半)? Move reply bubbles from 2さい to 1さい半?
- Licensing for age data: CHILDES (non-commercial, no LLM use) is out. Mochizuki & Ota's age ratings are CC BY-NC (needed for 4–6, so ask them or run our own small study). Ask the J-CDI developers whether a word list derived from Wordbank needs their permission.

- Tomo's gender and self-reference: the AI currently uses ぼく (boy). Decide, and put it in the prompt.
- Does Tomo open on its own (it does now), or peek and wait for a click?
- Default visit frequency for a new user.
- Transcripts: off, kept on this Mac, or synced?
- How Tomo's "known" relates to the iOS app's manual Known words.
