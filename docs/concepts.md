# Tomodachi: working concepts

Where the idea stands, what the demo already proves, and what is still open. Related docs:
- feature ideas: [user-journey.md](user-journey.md)
- systems and extension points: [architecture.md](architecture.md)
- status of everything we want: [backlog.md](backlog.md)
- decisions: [decisions.md](decisions.md)
- deep dives: [research/](research/)

## The pitch

See the root level README.md

## Concepts that work (tried in the demo)

| Concept | How it works | Demo status |
|---|---|---|
| **Lives in the notch** | Tomo sits small beside the notch, opens into a card, and its eyes follow your cursor. Built on the [Coucou](https://github.com/Louis-CFM/coucou) notch app (MIT code). | Built (`mac-demo/`) |
| **Own character** | A peach egg-shaped body with blush. It grows a sprout at 2さい and gets bigger at 3さい. Coucou's Mochi look, name and sounds aren't licensed for reuse, so we replace them. | First version built |
| **Ages are the levels** | 1さい: single baby words (ワンワン, まんま). 2さい: two-word phrases (ワンワン いた！). 3さい: real short conversations. | Built for ages 1–3 |
| **Understanding before speaking** | 1–2さい: tap the right picture, or do what Tomo asks (feed / bed / hug). 3さい: answer in your own words by typing Japanese or speaking. | Built |
| **Baby talk + grown-up word** | Tomo says ワンワン, and after you get it the card shows "grown-ups say: いぬ（犬）". | Built |
| **Drop-in visits** | Tomo opens on its own every so often (10 min in the demo) for a 3-answer visit. Ignore it for 10 s (20 s at 3さい) and it yawns and tucks back in, with no penalty. Visits wait while you're typing and skip if you're away. | Built (simple, no settings) |
| **Always there** | Between visits, click small Tomo any time for free play with no time limit. | Built |
| **Child-like feedback** | Right: happy roll, sparkles, praise. Wrong: shake and ちがう〜. Not understood: head tilt and ん？ わかんない… Poked: いたい！ | Built |
| **Voice in and out** | Tomo speaks with macOS's Japanese voice at a raised pitch. You answer through Apple's on-device Japanese speech recognition. Both are free and offline. | Built (the mic is untested by hand) |
| **AI is optional** | Stages 1–2 are fully scripted. 3さい uses AI if configured. Otherwise it uses a placeholder keyword matcher, which will be replaced by the Zenbu offline dictionary system. | Built |
| **Any AI provider** | One adapter: Anthropic's own API, plus anything that speaks the OpenAI chat format (OpenAI, Gemini, OpenRouter, Groq, Ollama, custom). Pick it under menu → **AI provider…** (key in the Keychain), or put `OPENAI_API_KEY` in `.env` and launch with `mac-demo/run.sh`. | Built; tested with OpenAI `gpt-5.4-mini` (about 2 s per reply) and local Ollama |

## Rules we've settled on

- **No study sessions.** Learning happens in short visits. Free play is always available but never required.
- **No guilt.** No streak shaming. Tomo is happy to see you, never disappointed in you.
- **Grade whether you were understood, not your pronunciation.** If Tomo doesn't get it, it reacts like a child (ん？), not like a teacher.
- **Grows over days, not minutes** (planned). A word counts as known only after you've understood it on more than one day, so you can't cram.
- **Check offline first, call AI only for leftovers** (planned). Most toddler questions have expected answers that can be checked without AI (yes/no, pick an animal or a food). AI handles the long tail.

## How the demo decides Tomo grew up (placeholder)

- 1さい → 2さい: 5 different words understood.
- 2さい → 3さい: 5 phrases understood.
- 3さい: counts "understood" conversation replies (10 is a placeholder for 4さい).

These numbers are for the demo only. See the open questions below.

## Open questions (research done; decisions tracked in [backlog.md](backlog.md))

| Question | Research file |
|---|---|
| How should points and levels work so growth feels earned and can't be crammed? | [research/leveling-points.md](research/leveling-points.md) |
| How do we get a better, child-like Japanese voice, and can it mature as Tomo ages? | [research/voices.md](research/voices.md) |
| What's the data model for the words a learner knows and has encountered? | [research/learner-data-schema.md](research/learner-data-schema.md) |
| Where do we get the vocabulary and grammar for each age, so Tomo knows what it can say and understand? | [research/age-vocabulary-data.md](research/age-vocabulary-data.md) |
| How do we check a learner's answer without AI, and when is AI worth calling? | [research/answer-evaluation.md](research/answer-evaluation.md) |
| Which AI models are good at toddler Japanese, and what does a conversation cost? | [research/ai-models-and-costs.md](research/ai-models-and-costs.md) |

## Related

- The Zenbu Japanese monorepo (`../zenbujapanese-monorepo`) already has the dictionary data (JMdict with Language Reference IDs), a Japanese word splitter (Sudachi), example sentences and word-frequency lists. Tomo's words should use the same Language Reference IDs so progress can sync with the Zenbu app later.
- [mac-demo/README.md](../mac-demo/README.md) explains how to run and rebuild the demo.
