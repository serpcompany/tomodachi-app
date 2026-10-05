# Tomodachi: working concepts

Where the idea stands, what the demo already proves, and what is still open. Related docs:
- systems and extension points: [architecture.md](architecture.md)
- plans, ideas and open questions: [GitHub issues](https://github.com/serpcompany/zenbujapanese-tomo-app/issues)
- decisions: [decisions.md](decisions.md)
- deep dives: [research/](research/)

## The pitch

See the root level README.md

**The core: Tomo comes to you.** You never have to find the discipline to open a learning app every day. Tomo drops in through the day for a 10–30 second moment, then leaves. What it brings comes from a **content source**. Today the only source is the age track (the README's idea). Other sources, like an Anki deck, are ideas ([#11](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/11), [#12](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/12)).

## Concepts that work (tried in the demo)

| Concept | How it works | Demo status |
|---|---|---|
| **Lives in the notch** | Tomo sits small beside the notch, opens into a card, and its eyes follow your cursor. Built on the [Coucou](https://github.com/Louis-CFM/coucou) notch app (MIT code). | Built (`mac-demo/`) |
| **Own character** | Tomo is a hiyoko (baby chick), drawn and animated by our own code. At 1さい it sits in the bottom half of its eggshell; at 2さい it hatches (the shell falls away, feet and a second head feather appear); at 3さい it's bigger with a third feather. It's drawn and animated live in code and never sits still: it breathes, blinks, leans and looks toward your cursor, its feathers bounce, it fidgets between events (glances, peeps, wing stretches, curious tilts, preening, little hops), and it dozes off if ignored, waking with a start. Nothing of Coucou's Mochi character is left. | First version built |
| **Levels and ages** | Tomo has levels: small sets of words. When 9 in 10 of a level's words reach "knows it", Tomo levels up (Lv 2, Lv 3…), with a sparkle and a chirp, and the next set unlocks. Some levels are birthdays, like a Pokémon evolving: 1さい speaks single baby words (ワンワン, まんま), 2さい hatches and uses two-word phrases (ワンワン いた！), 3さい has real short conversations. The header shows "1さい · Lv 2" and the words known in this level. Level and age never go down | Built for ages 1–3 (placeholder content: 5 levels) |
| **Word stages** | Every word has a stage, following WaniKani's published rules in our own code: just heard (1–4) → knows it (5–6) → good at it (7) → loves it (8) → forever (9, never asked again). A right answer moves a word up one stage only when it's due; Tomo asks again after 4 h, 8 h, 1 day, 2 days, 1 week, 2 weeks, 1 month, then 4 months (levels 1–2 start faster). Wrong tries in the same round move it down, twice as far from "knows it" up. Right after the hint, it stays. Answers on words that aren't due are practice: Tomo still reacts, nothing moves | Built |
| **Saved progress** | Tomo's level, age and every word's stage are saved on this Mac, one Tomo per language pair. Every answer is logged, to tune the rules later. Start over (menu, header ↺, Settings) asks first | Built |
| **Understanding before speaking** | 1–2さい: tap the right picture, or do what Tomo asks (feed / bed / hug). 3さい: answer in your own words by typing Japanese or speaking. | Built |
| **Baby talk + grown-up word** | Tomo says ワンワン, and after you get it the card shows "grown-ups say: いぬ（犬）". | Built |
| **Drop-in visits** | Tomo opens on its own every so often (20 min by default; 10 min to 2 h, or only when clicked, in Settings), starting at launch, for up to 3 answers: words that are due first, then at most one new word (10 new a day). A scheduled visit with nothing due or new is skipped. Ignore it for 10 s (20 s at 3さい), or close it with ×/Esc, and it tucks back in with a red dot and an occasional bounce until you check in. Visits wait while you're typing and skip if you're away. | Built (simple timing) |
| **Always there** | Between visits, click small Tomo any time for free play with no time limit. | Built |
| **Child-like feedback** | Right: hop, wing flap, sparkles, praise. Wrong: shake, > < eyes and ちがう〜. Not understood: head tilt, a "?" and ん？ わかんない… Poked: a squish and いたい！ (three pokes make it dizzy) | Built |
| **Help when you're stuck** | Help opens in a large-text panel that grows out of the notch under Tomo's card. Click a word for its card (meaning in your language, the Mac dictionary, Open in Zenbu). Drag across words → "I don't understand" → an explanation of just that part. **Hint** shows the meaning and example answers (click one to use it). **Explain** gives the key parts and a tip, and can ask Tomo to say it simpler. Tomo doesn't leave while help is open | Built (prototype) |
| **Every answer has an obvious result** | **✓ Win +1** (green): understood or right picture; the word moves up a stage. **✓ Win** without +1: right, but the word wasn't due (practice). **✗ Miss** (red): tried, Tomo didn't get it, or wrong picture. **– No score** (grey): wrong language, or a help request ("what?", なに？); no credit, no penalty. Help requests repeat the question slowly and open the hint. | Built |
| **Sound effects** | Tomo peeps and chirps: a "piyo piyo" when a visit starts, happy chirps for a Win, a soft boo-oop for a Miss, a questioning "hm?" for No score, a pop and fanfare when it hatches or grows, a boing when poked, a trill for love, a yawn. The island blips when it opens and closes. All synthesized in code; the peeps get lower as Tomo grows. One switch with the voice. | Built |
| **Voice in and out** | Tomo speaks with macOS's Japanese voice at a raised pitch. You answer through Apple's on-device Japanese speech recognition. Both are free and offline. | Built (the mic is untested by hand) |
| **AI is optional** | Stages 1–2 are fully scripted. 3さい uses AI if configured. Otherwise it uses a placeholder keyword matcher, which will be replaced by the Zenbu offline dictionary system. | Built |
| **Settings** | Menu → Settings…: languages, how often Tomo visits (or only when clicked), voice, AI provider, About | Built |
| **Any language pair** | What you speak and what you learn are separate settings (Settings → General). Packs: Japanese, English, Spanish; interface in English or Japanese, so a Japanese speaker can learn English. | Built; see [languages.md](languages.md) |
| **Any AI provider** | One adapter: Anthropic's own API, plus anything that speaks the OpenAI chat format (OpenAI, Gemini, OpenRouter, Groq, Ollama, custom). Pick it under Settings → **AI** (key in the Keychain), or put `OPENAI_API_KEY` in `.env` and launch with `mac-demo/run.sh`. | Built; tested with OpenAI `gpt-5.4-mini` (about 2 s per reply) and local Ollama |

## Rules we've settled on

- **Tomo comes to you.** The visits are the product; the material is a content source that can be swapped.
- **No study sessions.** Learning happens in short visits. Free play is always available but never required.
- **No guilt.** No streak shaming. Tomo is happy to see you, never disappointed in you.
- **Grade whether you were understood, not your pronunciation.** If Tomo doesn't get it, it reacts like a child (ん？), not like a teacher.
- **Grows over days, not minutes.** A word only moves up when it's due, so knowing it takes several visits over days. You can't cram.
- **Check offline first, call AI only for leftovers** (planned). Most toddler questions have expected answers that can be checked without AI (yes/no, pick an animal or a food). AI handles the long tail.

## How Tomo grows

The rules are in `TomoProgress.swift`; the levels come from the language pack. Japanese today: Lv 1–2 are 1さい (4 baby words each), Lv 3–4 are 2さい (3 phrases each), Lv 5 is 3さい (5 conversation openers). The content is a placeholder ([#13](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/13)). At the fastest, a word reaches "knows it" in about 1.5 days on levels 1–2 and 3.5 days after that, so Tomo turns 2さい after about 3 days and 3さい after about 10. Growing past 3さい, the growth screen and the word book are [#3](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/3).

## Open questions (research done; each has a GitHub issue)

| Question | Issue | Research file |
|---|---|---|
| How should points and levels work so growth feels earned and can't be crammed? | [#3](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/3) | [research/leveling-points.md](research/leveling-points.md) |
| How do we get a better, child-like Japanese voice, and can it mature as Tomo ages? | [#5](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/5) | [research/voices.md](research/voices.md) |
| Which learning modes should Tomo use, and when? | [#14](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/14) | [research/learning-modes.md](research/learning-modes.md) |
| What's the data model for the words a learner knows and has encountered? | [#4](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/4) | [research/learner-data-schema.md](research/learner-data-schema.md) |
| Where do we get the vocabulary and grammar for each age, so Tomo knows what it can say and understand? | [#13](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/13) | Deferred: it will come from the Zenbu learning system. Background: [research/age-vocabulary-data.md](research/age-vocabulary-data.md) |
| How do we check a learner's answer without AI, and when is AI worth calling? | [#6](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/6) | [research/answer-evaluation.md](research/answer-evaluation.md) |
| Which AI models are good at toddler Japanese, and what does a conversation cost? | [#7](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/7) | [research/ai-models-and-costs.md](research/ai-models-and-costs.md) |

## Related

- The Zenbu Japanese monorepo (`../zenbujapanese-monorepo`) already has the dictionary data (JMdict with Language Reference IDs), a Japanese word splitter (Sudachi), example sentences and word-frequency lists. Tomo's words should use the same Language Reference IDs so progress can sync with the Zenbu app later.
- [mac-demo/README.md](../mac-demo/README.md) explains how to run and rebuild the demo.
