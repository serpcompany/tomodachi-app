# Checking a learner's answer, mostly without AI

Researched 2026-10-03. Open question from [concepts.md](../concepts.md): how do we check a learner's answer without AI, and when is AI worth calling?

## Answer

Give each Tomo question a small **answer spec**: its type (yes/no, pick from a category, or open), the intents it expects, and the word lists those intents use. Run the learner's text through **Sudachi**, which turns each word into its dictionary form and reading, then match **whole words** against the spec instead of substrings. This fixes all three current weaknesses: answers are checked against the question that was asked, うんどう can't match うん, and たべた, 食べました and たべてない all become 食べる (with past, polite and negative kept as flags). Use `sudachi-swift`, pinned to the Zenbu iOS app's versions so dictionary forms line up with Zenbu's dictionary. Its cost is a 217 MB dictionary, so download it when Tomo first reaches 3さい. Call AI only when offline confidence is below 0.8: Apple's free on-device model first where available, then the configured provider. My reasoned estimate, not a measurement, is that **75–85% of answers to Tomo's scripted questions can be graded offline**.

## Proposal

### What goes wrong today

I ran the demo's `offlineReply` rules ([TomoChat.swift](../../TomoCore/Sources/TomoCore/TomoChat.swift)) on a few likely answers:

| Learner says | Tomo replies today | Why |
|---|---|---|
| いいえ | いえ！ いってらっしゃい！ | いえ ("house") is inside いいえ |
| ううん | そっか！ えへへ (taken as yes) | うん is inside ううん |
| うんどう してる | そっか！ えへへ | うん is inside うんどう |
| パンダ | パン！ おいしそう！ | パン is inside パンダ |
| まだ たべてない | なに たべてるの？ | The negation is ignored |
| すいてない | ん？ わかんない… | Conjugations aren't handled |
| ペンギン | ん？ わかんない… | Not in the list, and nothing else catches it |

Also, `TomoBrain.reply` calls the AI first whenever one is configured, which is the opposite of the rule in concepts.md ("check offline first").

### 1. One answer spec per question

There are three question types:

- **yes_no**: a closed set of yes, no and unsure words, plus the question's own verb. The verb's polarity decides the answer: すいた means yes, すいてない means no.
- **pick**: any word from a category list (animals, foods, places) is on topic.
- **open**: a list of known intents, plus a looser rule that accepts any real verb.

Category lists are **generated at build time** from the age vocabulary data and JMdict. Each entry stores Sudachi's normalized form, the kana reading, any baby-talk variants, and the Language Reference ID, so progress can sync with Zenbu later. Specs are short and written by hand.

```yaml
lexicons:                       # generated at build time; excerpt
  food:
    - { lemma: ラーメン, kana: らーめん, lrid: "…" }
    - { lemma: 寿司,     kana: すし }
    - { lemma: パン,     kana: ぱん }
    - { lemma: ご飯,     kana: ごはん, baby: [まんま] }
  animal:
    - { lemma: 犬,       kana: いぬ, baby: [わんわん] }
    - { lemma: パンダ,   kana: ぱんだ }
    - { lemma: ペンギン, kana: ぺんぎん }

questions:
  - id: onaka-suita
    say: おなか すいた？
    type: yes_no
    target: { lemma: 空く, kana: すく }    # "used the target word"
    verb_polarity: target                  # すいた → yes, すいてない → no
    intents:
      yes:    { words: [うん, はい, ええ, そう, ぺこぺこ] }
      no:     { words: [ううん, いいえ, ぜんぜん, まだ, いっぱい] }
      unsure: { words: [うーん, わかんない, ちょっと, すこし] }
    off_topic: [animal, place]

  - id: kyou-nani-tabeta
    say: きょう なに たべた？
    type: pick
    target: { lemma: 食べる, kana: たべる }
    intents:
      food:    { lexicon: food }
      nothing: { words: [なにも, まだ] }     # "nothing yet" is a fine answer
    off_topic: [animal, place, activity]
    notes:
      - when: { lemma: 食べる, tense: present }
        say: "Tomo asked about today, so the past form たべた fits."

  - id: nani-shiteru
    say: なに してるの？
    type: open
    intents:
      work:    { lemmas: [仕事, 働く, 会議, メール] }
      study:   { lemmas: [勉強, 日本語, 宿題] }
      watch:   { lemmas: [見る, テレビ, 映画, アニメ] }
      eat:     { lemmas: [食べる], lexicon: food }
      rest:    { lemmas: [寝る, 休む, ごろごろ] }
      nothing: { words: [なにも, べつに, ひま] }
    accept_any_verb: { confidence: 0.6 }   # 運転してる → on topic, generic reply
    off_topic: [animal]
```

The pick questions すきな どうぶつ なあに？ and どこ いくの？ follow the `kyou-nani-tabeta` pattern, using the `animal` and `place` lists. Tomo's reply templates (`{w}！ おいしそう！`) can stay attached to intents as they are today.

### 2. Normalizing what the learner said

- **Clean up**: apply Unicode NFKC (turns full-width letters and half-width kana into standard forms), then remove spaces and punctuation.
- **Tokenize** with Sudachi in mode C. For each word, keep the normalized form, dictionary form, reading (as hiragana), part of speech and the unknown-word flag.
- **Kana/kanji/katakana**: compare both the normalized form and the hiragana reading, so 犬/いぬ/イヌ and お腹/おなか match. Sudachi's normalized form already merges script variants (the paper's 字種 category, e.g. かつ丼/カツ丼); the reading is the backstop. Use one kana-conversion function on both sides: Foundation's ICU transform turned ラーメン into らあめん in my test.
- **Politeness and conjugation**: the dictionary form removes them. The helper words after the matched word become flags: た/だ means past, ます/です means polite, ない/ん/ません means negative, and てる/ている means ongoing.
- **Missing particles and one-word answers**: particles are ignored. いぬ, いぬ すき and いぬが すき all match the same way.
- **Speech-recognition errors**:
  - Check up to the top 3 alternatives in `SFSpeechRecognitionResult.transcriptions`. The demo reads only `bestTranscription`.
  - Pass the question's expected words as `contextualStrings`. Apple says to keep phrases to one or two words and use no more than 100 of them.
  - Allow one wrong kana for expected words of 3+ kana, at lower confidence.
- **Off-topic**: all category lists are loaded for every question. A word that is in another question's list but not this one gives *understood, but off topic*. Tomo can react like a child ("それ たべもの だよ〜") instead of saying ん？.

### 3. The matcher

This works with any analyzer that returns a dictionary form, reading and part of speech, so Sudachi and Kuromoji are interchangeable behind a protocol (as in the monorepo's `JapaneseMorphologyClient`).

```swift
struct Word { surface, lemma /*normalized*/, base /*dictionary form*/, kana, pos, isUnknown }

func grade(_ alternatives: [String], q: QuestionSpec) -> Grade {
    var best = Grade.notUnderstood                         // confidence 0
    for text in alternatives.prefix(3) {                   // typed answer: 1 alternative
        let t = normalize(text)                            // NFKC, strip punctuation and spaces
        guard containsJapanese(t) else { best = max(best, .notJapanese); continue }
        let words = analyzer.tokenize(t)                   // Sudachi mode C
        let g = intentMatch(words, q)                      // 0.95, or 0.6 on conflict
             ?? fuzzyMatch(kana(t), words, q)              // 0.6
             ?? offTopicMatch(words, q)                    // 0.85, onTopic = false
             ?? looseMatch(words, q)                       // 0.6 any verb (open) / 0.3 known words
        best = max(best, g)                                // by confidence
    }
    return best
}

func intentMatch(_ words: [Word], _ q: QuestionSpec) -> Grade? {
    var hits: [(intent: String, word: Word, weight: Int)] = []
    for w in words where !w.pos.isParticle {               // whole words: うんどう ≠ うん
        for (name, intent) in q.intents where intent.matches(w) {   // lemma or kana
            hits.append((name, w, 1))
        }
    }
    if q.type == .yesNo, let v = words.first(where: q.target.matches) {
        let negative = helperFlags(after: v, in: words).negative
        hits.append((negative ? "no" : "yes", v, 2))       // the verb beats うん/ううん
    }
    guard let top = hits.max(by: { $0.weight < $1.weight }) else { return nil }
    let conflict = hits.contains { $0.weight == top.weight && $0.intent != top.intent }
    let flags = helperFlags(after: top.word, in: words)    // past, polite, negative, ongoing
    return Grade(understood: true, onTopic: true, intent: top.intent, word: top.word.surface,
                 usedTarget: words.contains(where: q.target.matches),
                 grammarNote: q.note(for: top.word, flags), // from spec `notes`, else nil
                 confidence: conflict ? 0.6 : 0.95, source: .offline)
}

// fuzzyMatch: slide over the kana string looking for this question's expected words
// (3+ kana, at most one kana different), skipping hits inside a longer known word.
// looseMatch: open question with a known verb → on topic, intent "other";
// all words known but nothing matched → understood unknown, confidence 0.3.
```

### 4. The grading output

```json
{
  "questionId": "kyou-nani-tabeta",
  "understood": true,
  "onTopic": true,
  "intent": "food",
  "word": "ラーメン",
  "usedTarget": true,
  "flags": { "past": true, "polite": true, "negative": false },
  "grammarNote": "ました is fine, but to a 3-year-old you'd say たべた.",
  "confidence": 0.95,
  "source": "offline"
}
```

`understood` and `onTopic` are separate: ラーメン as the answer to すきな どうぶつ is understood but off topic. `grammarNote` is optional and goes on the card, like "grown-ups say"; Tomo never says it, since Tomo is a child, not a teacher. Offline notes come only from a spec's `notes`; anything subtler comes from AI or is left out.

### 5. When to call AI

| Offline confidence | No AI available | AI available |
|---|---|---|
| ≥ 0.8 | Offline reply | Offline reply, **no call** |
| 0.5–0.8 | Offline reply | Ask AI. If no answer in 3 s, use the offline reply |
| < 0.5 | Child-like ん？ わかんない | Ask AI. If no answer in 3 s, ん？ |
| No Japanese at all | にほんご で いって！ | Same, no call |

The thresholds are starting values to tune against real answers.

**Which AI, in order:**

1. **Apple's on-device model** (Foundation Models framework). It needs macOS 26 or later with Apple Intelligence turned on. The demo targets macOS 15, so check availability at runtime.
2. **The configured provider** in `TomoAI.swift`.

On this Mac (macOS 27.2) the on-device model reported Japanese support, returned structured output through `@Generable`, and took 0.7–1.4 s per answer. It judged understood and on-topic correctly on 3 samples, but for ぜんぜん (to おなか すいた？) it picked おなか as the keyword. Trust it for understood and on-topic, not grammar notes.

Send the AI the question, the spec's intents and the offline guess, and ask for the same grading JSON plus Tomo's reply. Log locally the words the AI accepted that are missing from the lists, so authors can add them and the offline share grows.

If the Sudachi dictionary isn't downloaded yet, 3さい uses AI if one is configured, and otherwise the old keyword rules.

### 6. How much the offline path would cover (reasoned estimate)

This is not measured. It assumes the hint shows example answers, which pushes learners toward the lists.

| Type | Tomo's questions | Offline share | Reasoning |
|---|---|---|---|
| yes/no | おなか すいた？ | 90–95% | A small closed set: うん/ううん/はい/いいえ, the verb itself, and a few extras. Misses are indirect answers ("さっき たべた") |
| pick | どうぶつ, たべた, どこ | 80–90% | Mostly one noun from a list of a few hundred words. Misses are brand and shop names (スタバ), dishes not in the list, and English |
| open | なに してるの？ | 55–70% | Activities are open-ended. The intent list plus "any known verb" catches the common ones |

Weighting the five questions equally gives (0.92 + 3 × 0.85 + 0.62) / 5 ≈ 0.82, so **about 75–85% offline**. Perhaps a third of the rest is garbled speech or non-Japanese, where AI can't beat ん？ either, so AI earns its cost on roughly **10–15%** of answers. Follow-up questions without a spec (such as the offline reply なに みてるの？) always need AI. To check the estimate, label about 200 real answers.

## Options compared

| Option | Dictionary form | Reading | Part of speech | Size | Swift integration | Maintenance | Verdict |
|---|---|---|---|---|---|---|---|
| **Sudachi** (`sudachi-swift` + SudachiDict core) | Yes, plus normalized form | Yes | Yes | Core: 72 MB download, 217 MB on disk. Small: 41.8 MB download, disk size not published | Native Swift package. Prebuilt arm64 binary for macOS 14+. Under 1 ms per short sentence (README) | Dictionary releases in July and Sept 2026. One-person binding (v0.3.0, Sept 2026). Already used by Zenbu iOS | **Recommended** |
| Kuromoji.js + IPADIC via JavaScriptCore | Yes (`basic_form`) | Yes | Yes | About 17 MB gzipped, bundled | Works. The monorepo wrapper `KuromojiMorphologyClient.swift` is 234 lines | IPADIC is from 2007. kuromoji.js was last pushed in 2023. It is the Zenbu iOS default for interactive text | Fallback if size matters more than quality |
| MeCab + IPADIC/UniDic | Yes | Yes | Yes | We bundle the IPADIC or UniDic files ourselves | A C++ library we would wrap ourselves | Last release 0.996 (2013) | No: same data as Kuromoji, more glue code |
| Apple NaturalLanguage (`NLTokenizer`/`NLTagger`) | **No** for Japanese | No | **No** for Japanese | 0 | Built in | Apple | No. On macOS 27.2, Japanese only gets the `Language`, `Script` and `TokenType` tag schemes (English also gets `Lemma` and `LexicalClass`). It segments only, and splits かいしゃにいく into か｜いしゃ｜に｜いく |
| `CFStringTokenizer` Latin transcription | No | Yes (romaji) | No | 0 | Built in | Apple | No. It misreads words: お腹空いた → *onaka ai ta* |
| Today's keyword "contains" check | No | No | No | 0 | Built in | — | Replace |

**Why Sudachi over Kuromoji:** native Swift, fast, a maintained dictionary, normalized forms, and it is the engine Zenbu's dictionary search already pins (`SudachiCoreContract` in `JapaneseMorphologyClient.swift`). Kuromoji wins only on size, and the matcher works with either.

## Risks and open questions

- **Size and Intel Macs.** The core dictionary is 217 MB on disk, and the prebuilt binary is arm64 only (Intel needs a source build). The small edition probably covers toddler words, but its on-disk size isn't published; the `sudachi-swift` README's "≈ 40 MB" looks like the download size. Measure it.
- **One maintainer** for the binding (0 GitHub stars). v0.3.0 moves to sudachi.rs 0.7 and a v1 dictionary format that rejects old dictionary files. Pin exactly and upgrade together with the Zenbu app; it's Apache-2.0 and builds from source.
- **Hiragana-only typing.** NLTokenizer splits かいしゃ and みそしる wrongly. I couldn't run Sudachi here (no dictionary installed), so test it on all-hiragana answers first.
- **うん / ううん / うーん** can be confused by speech recognition. Treat うーん as `unsure` and have Tomo ask どっち？.
- **Reading matches can merge homophones** (はし: chopsticks, bridge, edge). Low risk within one question's short list.
- **The "any verb" rule** can accept odd answers; at confidence 0.6 it still gets AI review when AI is available.
- **Open:**
  - Should an answer that is understood but off topic count toward growth? (See [leveling-points.md](leveling-points.md).)
  - Should grammar notes appear at 3さい at all?
  - Who writes specs for Tomo's follow-up questions?
  - The thresholds and the coverage estimate need a labeled test set.

## Sources

Apple (documentation; behavior checked on macOS 27.2 on 2026-10-03):
- [NLTagScheme.lemma](https://developer.apple.com/documentation/naturallanguage/nltagscheme/lemma) and [NLTagger.availableTagSchemes(for:language:)](https://developer.apple.com/documentation/naturallanguage/nltagger/availabletagschemes(for:language:)). The docs don't list languages; the Japanese result above comes from calling this API.
- [kCFStringTokenizerAttributeLatinTranscription](https://developer.apple.com/documentation/corefoundation/kcfstringtokenizerattributelatintranscription)
- [SFSpeechRecognitionRequest.contextualStrings](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings), [SFSpeechRecognitionResult.transcriptions](https://developer.apple.com/documentation/speech/sfspeechrecognitionresult/transcriptions), and for macOS 26+ [AnalysisContext.contextualStrings](https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings)
- [Foundation Models](https://developer.apple.com/documentation/foundationmodels) and [SystemLanguageModel.supportedLanguages](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/supportedlanguages)

Sudachi:
- [Sudachi README](https://github.com/WorksApplications/Sudachi): split modes and normalized forms
- Takaoka et al., [Sudachi: a Japanese Tokenizer for Business](https://aclanthology.org/L18-1355/), LREC 2018: normalization covers okurigana, script (字種), variant-character and misspelling variants
- [SudachiDict](https://github.com/WorksApplications/SudachiDict) and its [v20260723 release assets](https://github.com/WorksApplications/SudachiDict/releases/tag/v20260723) (download sizes)
- [sudachi-swift](https://github.com/iasnezhkov/sudachi-swift): README (editions, performance, arm64-only) and [v0.3.0 notes](https://github.com/iasnezhkov/sudachi-swift/releases/tag/v0.3.0)
- [sudachi.rs](https://github.com/WorksApplications/sudachi.rs)

MeCab and Kuromoji:
- [MeCab](https://taku910.github.io/mecab/)
- [Kuromoji (Java)](https://github.com/atilika/kuromoji)
- [kuromoji.js](https://github.com/takuyaa/kuromoji.js)

Zenbu monorepo (`../zenbujapanese-monorepo`, read only):
- `apps/ios/Modules/Package.swift`
- `apps/ios/Modules/Sources/SearchExperience/JapaneseMorphologyClient.swift` (pinned versions; 72,275,897-byte download; 217,466,039 bytes installed)
- `apps/ios/Modules/Sources/SearchExperience/KuromojiMorphologyClient.swift`
- `apps/ios/Modules/Sources/SearchExperience/Resources/LanguageTechnologyPackCatalog.json`
- `docs/technologies.md`, `docs/data-sources.md`, `docs/agents/ios.md`

This repo:
- [TomoChat.swift](../../TomoCore/Sources/TomoCore/TomoChat.swift) (`offlineReply`, `TomoBrain.reply`, `TomoListener`)
- [TomoAI.swift](../../TomoCore/Sources/TomoCore/TomoAI.swift)
