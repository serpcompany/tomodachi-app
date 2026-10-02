# Languages: any language you speak × any language you learn

Tomo works with a **language pair**:
- The **learner language** is the one you speak.
- The **target language** is the one you're learning.

Japanese-for-English-speakers is just the first pair. No Swift code contains text in a specific language; everything comes from data files.

## The two sides

| | Learner language (you speak) | Target language (you learn) |
|---|---|---|
| Decides | The interface text, hints, translations, and the "need" labels (feed / bed / hug) | Tomo's words and lines, voice, speech recognition, the "is this the right language?" check, the AI's character rules, age labels (1さい / 1 año), and later the age vocabulary data |
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
| `labels`, `lines` | Tomo's own words: "again", "listening…", wrong, ouch, grew up, bye, "say it in my language", "I don't understand" |
| `ai` | Persona (`"a {age}-year-old child from Spain"`) and language-specific rules (script, register), placed into a shared prompt template. `ai.rulesByAge` replaces the rules from an age on. Reply length and style follow Tomo's age |
| `stages` | Rounds per age. Picture rounds (`answer` + `choices`) or need rounds (`need`: eat / sleep / hug). Each round has an `id` like `ja:wanwan` |
| `starters`, `startersByAge` | Conversation openers for the talking stage, with example answers. `startersByAge` replaces them from an age on (`fromAge`) |
| `offlineReplies` | Placeholder keyword replies. The dictionary system replaces them |
| `helpPhrases` | Whole answers that mean "I didn't understand" in this language (なに, わかんない). The learner file has its own ("what", "huh") |

## How each system uses the pair

| System | Target language | Learner language |
|---|---|---|
| Content | Rounds, starters, "grown-ups say" | Meanings, example translations |
| Voice out | `speechLocale`: the best installed voice for it | — |
| Voice in | `recognitionLocale`, on-device only | Error messages |
| Language check (layer 1 of answer checking) | `Jpan`: contains kana or kanji. Latin-script: Apple's language identifier decides between target and learner, and a known pack word also passes | — |
| AI | Persona and rules from the pack; `say` must be in the target language | `translation` comes back in the learner language |
| Growth | Item ids are namespaced per language (`ja:…`, `es:…`) | — |

## Adding a language

**A new target language:**
1. Copy `es.json` to `<id>.json`. Fill in the locales, script, labels, lines, AI persona and rules, stages and starters.
2. Check the Mac has a voice (System Settings → Accessibility → Spoken Content) and on-device dictation for it.
3. Run `TOMO_TARGET=<id>` with `TOMO_AUTOPLAY=1`, then `TOMO_STAGE=3 TOMO_AUTOCHAT="<an English word>|<a target answer>"` (see `mac-demo/README.md`).
4. Have a native speaker review it, then set `reviewedByNativeSpeaker: true`.

**A new learner language:**
1. Copy `ui.en.json` to `ui.<id>.json` and translate the strings.
2. Add `"<id>": "…"` translations to each pack's `name`, `meaning`, `translation` and example fields. Missing ones fall back to English.

## Decided

- **One Tomo per target language.** Switching "Learning" starts that language's Tomo. Progress isn't saved yet; when it is, it's keyed by `(learner, target)`.
- **Item ids are namespaced by target language.** For Japanese they become Zenbu Language Reference IDs (`ja:<LRID>`).
- **"Tomo" stays the character's name in every language** for now.

## Open questions

- **Interface text:** move from JSON strings to Apple String Catalogs once the app has more screens.
- **Translations from the dictionary:** for Japanese, JMdict has meanings in several languages (German, French, Spanish, Russian…), so learner-language translations could come from the Zenbu dictionary instead of hand-written pack text.
- **Age data per language:** Wordbank has toddler vocabulary data for dozens of languages, so the age-vocabulary pipeline ([research/age-vocabulary-data.md](research/age-vocabulary-data.md)) should generalize. Ages 3–6 need per-language sources.
- **Harder cases:**
  - right-to-left scripts (Arabic, Hebrew): the island layout
  - tonal languages (Mandarin): pinyin with tone marks as the romanization
  - languages with no Apple voice or on-device recognition: cloud fallback, which conflicts with the on-device-only decision
- **Same-script language check:** one-word answers are hard for Apple's language identifier (is "no" English or Spanish?). The dictionary system should decide instead.
- **Regional variants and culture:** es-ES vs es-MX words (coche vs carro). Should Tomo's persona or name change per culture?
