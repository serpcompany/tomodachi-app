# Languages: any language you speak × any language you learn

Tomo works with a **language pair**:
- The **learner language** is the one you speak.
- The **target language** is the one you're learning.

Japanese-for-English-speakers is just the first pair. No Swift code contains text in a specific language; everything comes from data files (`.github/scripts/check-swift-text.mjs` fails on Japanese in Swift strings).

## The two sides

| | Learner language (you speak) | Target language (you learn) |
|---|---|---|
| Decides | The interface text, hints, translations, and the "need" labels (feed / bed / hug) | Tomo's words and lines, voice, speech recognition, the "is this the right language?" check, the AI's character rules, age labels (1さい / 1 año) |
| File | `Resources/languages/ui.<id>.json` | `Resources/languages/<id>.json` (a **language pack**) |
| Today | `en`, `ja` | `ja`, `en`, `es` (all drafts until a native speaker reviews them) |

Translations live inside each pack, keyed by learner language: `"meaning": {"en": "doggy", "es": "perrito"}`. If a translation is missing, English is used.

Code: `mac-demo/NotchBuddy/Sources/App/TomoLanguage.swift` holds:
- `TargetPack` and `LearnerPack` (the file formats)
- `LanguageContext` (the pair, passed to background work)
- `TomoLanguages` (the current selection)

Change them in **Settings → General** (I speak / I'm learning). The menu and Settings switch to the new interface language right away. For testing: `TOMO_TARGET=en`, `TOMO_LEARNER=ja`.

## What a language pack contains

| Field | Purpose |
|---|---|
| `id`, `name`, `nativeName`, `script` | BCP-47 id, the language's name in each learner language, and its ISO 15924 script (`Jpan`, `Latn`) |
| `reviewedByNativeSpeaker` | `false` marks a draft. The menu shows "· draft" |
| `speechLocale`, `recognitionLocale` | Tomo's voice and the speech-recognition locale (`ja-JP`, `es-ES`) |
| `romanization` | The name of the romanization (romaji), or `null` for Latin-script languages |
| `age` | Age label format: `{n}さい`, `{n} año` / `{n} años` |
| `labels`, `lines` | Tomo's own words: "again", "listening…", wrong, ouch, grew up, level up, bye, "say it in my language", "I don't understand" |
| `ai` | Persona (`"a {age}-year-old child from Spain"`) and language-specific rules (script, register), placed into a shared prompt template. `ai.rulesByAge` replaces the rules from an age on. Reply length and style follow Tomo's age |
| `levels` | Tomo's levels, in order. Each has an `age` and either `rounds` or `starters` (conversation openers with example answers). A round is a **picture** round (`answer` emoji + 3 `choices`), a **need** round (`need`: eat / sleep / hug), or, with neither, a **meaning** round: the learner picks its meaning out of three, the other two taken from other words (a different `category` first, never a word that sounds the same). Every item has an `id` like `ja:wanwan` or `ja:talk-onaka-suita`. A level whose `age` is higher than the one before is a birthday. Japanese levels are generated: see below |
| `startersByAge` | Openers for ages past the levels (testing older Tomos), from an age on (`fromAge`) |
| `offlineReplies` | Placeholder keyword replies. The dictionary system replaces them |
| `helpPhrases` | Whole answers that mean "I didn't understand" in this language (なに, わかんない). The learner file has its own ("what", "huh") |

## How each system uses the pair

| System | Target language | Learner language |
|---|---|---|
| Content | Levels (rounds, starters), "grown-ups say" | Meanings, example translations |
| Voice out | `speechLocale`: the best installed voice for it | — |
| Voice in | `recognitionLocale`, on-device only | Error messages |
| Language check (layer 1 of answer checking) | `Jpan`: contains kana or kanji. Latin-script: Apple's language identifier decides between target and learner, and a known pack word also passes | — |
| AI | Persona and rules from the pack; `say` must be in the target language | `translation` comes back in the learner language |
| Growth | Levels and their ages; item ids are namespaced per language (`ja:…`, `es:…`) | — |

## Japanese and English levels are generated

`mac-demo/scripts/build-levels.py ja|en` rebuilds a pack's levels from Wordbank's CDI data (Japanese; American English norming samples). Sources are pinned (commit and SHA-256 per file) in `mac-demo/scripts/sources/wordbank-<language>.source.json`; downloads are cached in `mac-demo/build/data-cache/`. Hand fixes live in `mac-demo/scripts/data/<id>-curation.json`: a picture (emoji) or an action per word, meaning and reading fixes, grown-up words for baby talk, and words to leave out. The talking level and `startersByAge` are kept as they are. `--review` writes a table of every word for checking.

Japanese goes on to 6さい with NINJAL's 幼児語彙 (words four preschoolers used in everyday speech) and 絵本語彙 (picture-book words), both CC BY 4.0 (`ninjal-bev.source.json`). Readings and English meanings come from JMdict, the same snapshot the Zenbu apps use (`jmdict.source.json`, read from `../zenbujapanese-monorepo`; CC BY-SA 4.0). Age: used by all 4 children or in 20+ books → 3さい; 3 children or 10+ books → 4さい; 2 or 5+ → 5さい; 1 or 3+ → 6さい, common words only. Wrong dictionary senses are fixed in `ja-curation.json` under `ninjal`.

English is for learners who speak Japanese, so every English word needs a Japanese meaning. Words that match a Japanese CDI word for the same concept (Wordbank's `uni_lemma`, after the Japanese curation) get it automatically; the rest are written in `en-curation.json` (`ja`). English-only grammar words (helping verbs, a/an/the, of, to, at, by, for, about) are left out. Spanish can follow the same way.

## Adding a language

**A new target language:**
1. Copy `es.json` to `<id>.json`. Fill in the locales, script, labels, lines, AI persona and rules, and the levels (rounds and starters, each with an `id`).
2. Check the Mac has a voice (System Settings → Accessibility → Spoken Content) and on-device dictation for it.
3. Run `TOMO_TARGET=<id>` with `TOMO_AUTOPLAY=1`, then `TOMO_STAGE=3 TOMO_AUTOCHAT="<an English word>|<a target answer>"` (see [verification.md](verification.md)).
4. Have a native speaker review it, then set `reviewedByNativeSpeaker: true`.

**A new learner language:**
1. Copy `ui.en.json` to `ui.<id>.json` and translate the strings.
2. Add `"<id>": "…"` translations to each pack's `name`, `meaning`, `translation` and example fields. Missing ones fall back to English.

## Decided

- **One Tomo per language pair.** Progress is saved keyed by `(learner, target)`, so switching "I speak" or "I'm learning" brings that pair's saved Tomo.
- **Item ids are namespaced by target language.** For Japanese they become Zenbu Language Reference IDs (`ja:<LRID>`).
- **"Tomo" stays the character's name in every language** for now.

## Open questions

Tracked in GitHub issues: more packs, interface text and harder cases ([#34](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/34)), dictionaries for non-Japanese targets ([#31](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/31)), and what Tomo asks per language ([#13](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/13)).
