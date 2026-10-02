# Learning modes: the ways Tomo plays with you

Researched 2026-10-03. Answers the backlog idea "More learning modes" ([backlog.md](../backlog.md)).

## Answer

Tomo doesn't need many modes. It needs one mode for each step on the ladder of knowing a word (hear it → recognize it → recall its meaning → say it → use it), and a rule that picks the step from each word's state. For the MVP, use seven modes: **Teach a new word** (pick the new thing from two you know, then Tomo names it), **Picture choice**, **Do what Tomo says** (feed / bed / hug grown into a small set of verbs), **Listen and translate** (sound only, tap one of three meanings; typing comes later), **What's this?** (say or type the word for a picture, with reply bubbles if speech fails), **Fix Tomo's mistake** (Tomo mislabels something you know and you correct it), and **Conversation**. Six of the seven run fully offline. Five are generated from one word entry plus per-language templates, so they work for any language pair without extra writing. The scheduler picks the words first (due words, at most one new), then the mode: new → teach, met → a recognition mode, known → a production mode, can say → conversation or Tomo's mistakes. Age, sound and mic settings, the visit's time budget and variety filter the choice. Reject odd one out, sorting and a "Tomo forgot" mechanic. Keep songs, dictation, kana reading and screen naming for later. A mode gives a Miss only when it's sure you got it wrong.

## The ladder

[Laufer & Goldstein (2004)][lg04] confirmed four levels of knowing a word's meaning with 435 learners, from easiest to hardest. Tomo's modes map onto them, and onto the evidence kinds in [learner-data-schema.md](learner-data-schema.md).

| Step | The learner… | Evidence kind | Modes |
|---|---|---|---|
| Hear | hears Tomo say it | `exposure` | Teach, Tomo's news, Say it with Tomo |
| Passive recognition | picks the meaning (picture, action, translation) | `comprehension` | Picture choice, Do what Tomo says, Listen and translate (tap), Fix Tomo's mistake (step 1) |
| Active recognition | picks the right target-language form | `comprehension`, `via = reply_bubble` | Reply bubbles (a fallback input, not a mode) |
| Passive recall | gives the meaning with no choices | `comprehension`, `via = typed` | Listen and translate (type) |
| Active recall | says the word | `production` | What's this?, Fix Tomo's mistake (step 2), Finish Tomo's phrase |
| Free use | uses it in a reply Tomo understood | `conversation` | Conversation |

## All modes considered

Times are estimates from the demo's pacing (Tomo speaks, you answer, 2.2 s of feedback), not measurements. The notch card has about 620×144 pt, with 112 pt reserved for Tomo on the left.

| Mode | Ages | Input | Time | Shows (evidence kind) | AI? | Notch card | Evidence | Any pair? | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| **Picture choice** (built) | 1さい+ | tap | 4–7 s | passive recognition → `comprehension`; 1 in 3 is a guess | offline | Tomo's line + 3 picture tiles | testing effect: retrieval with feedback ([Roediger & Karpicke 2006][rk06]; [Butler & Roediger 2008][br08]); words are learned across many ambiguous trials ([Yu & Smith 2007][ys07]) | yes; needs picturable words | **MVP**. Add an audio-first variant (text appears after the answer) from 2さい |
| **Do what Tomo says** (built as feed / bed / hug) | 1さい+ | tap an action (later: click Tomo's head or tummy) | 4–6 s | `comprehension` of verbs and requests | offline | line + 3 action tiles; reuses Tomo's eat, sleep, love and wave animations | TPR ([Asher 1969][asher]); gestures help word memory ([Macedonia & Knösche 2011][mk11]). Whether a click carries any of that benefit is **unverified** | yes; per-language command words | **MVP**. Grow from 3 needs to 6–8 actions (なでなで, こちょこちょ, バイバイ) |
| **Conversation** (built) | 3さい+ (bubbles from 2さい半) | type, voice | 15–30 s | `conversation` + `comprehension` of Tomo's line | offline answer specs first, AI for the rest | line + text field + mic | output hypothesis: speaking makes learners notice gaps ([Swain & Lapkin 1995][sl95]); more involvement, more retention ([Hulstijn & Laufer 2001][hl01]) | yes; per-language answer specs | **MVP** (keep) |
| **Help request** (built) | all | "what?", なに？, hint pill | +3 s | nothing | offline | hint line | — | yes | A move inside every mode, not a mode. Always No score |
| **Teach a new word** (みて！) | 1さい+ | tap | 5–8 s | `exposure` | offline | 3 tiles: 2 known things + the new one. Tomo names it after your pick | 3-year-olds map a new word to the unnamed thing ([Markman & Wachtel 1988][mw88]); that mapping fades unless the thing is named and later retrieved ([Horst & Samuelson 2008][hs08]; [Karpicke & Roediger 2007][kr07]); name what's already in focus ([Tomasello & Farrar 1986][tf86]) | yes | **MVP** |
| **Listen and translate: tap** | 1さい半+ | tap | 5–8 s | passive recognition → `comprehension` | offline | no target text; 3 meaning pills stacked, in your language | the recognition step ([Laufer & Goldstein 2004][lg04]); multiple choice with feedback ([Butler & Roediger 2008][br08]) | yes; meanings per learner language (packs already have them) | **MVP**, for words and phrases pictures can't show |
| **Listen and translate: type** | 3さい+ (opt-in earlier) | type (or say) it in your language | 8–15 s | passive recall → `comprehension` | offline with concept lists; on-device AI for leftovers | no target text; text field + mic | passive recall was the best predictor of classroom performance ([Laufer & Goldstein 2004][lg04]); translation tasks aid retention ([Laufer & Girsai 2008][lgi08]) | needs concept lists per learner language | **Next**: the upgrade of the tap version |
| **What's this?** (これ なあに？) | 2さい+ | voice or type; 3 bubbles after a failed try | 6–12 s | active recall → `production` | offline: accepted forms + recognition hints | one big picture + text field + mic | generation effect ([Slamecka & Graf 1978][sg78]; meta-analysis [Bertsch et al. 2007][b07]); retrieval beats restudy, tested on foreign word pairs ([Karpicke & Roediger 2008][kr08]); productive practice builds more kinds of word knowledge ([Webb 2009][w09]) | yes | **MVP** |
| **Fix Tomo's mistake** | 2さい+; known words only | tap ⭕ / ❌, then say, type or tap the right word | 6–12 s | `comprehension` (catching it) + `production` (correcting it) | offline | picture + Tomo's label + ⭕ ❌; then text field + mic | protégé effect: learning by teaching ([Chase et al. 2009][c09]); Japanese 3–6-year-olds learned English verbs by teaching a robot ([Tanaka & Matsuzoe 2012][tm12]); finding errors helps learners with prior knowledge, not novices ([Große & Renkl 2007][gr07]); real toddlers overextend words ([Rescorla 1980][r80]) | yes | **MVP**. Tomo is right about 1 time in 3 |
| **Yes or no?** (これ ワンワン？) | 1さい半+ | tap ⭕ / ❌, or say うん / ううん | 3–5 s | `comprehension`, weak (1 in 2 is a guess) | offline | picture + 2 targets | true/false practice can beat rereading ([Uner et al. 2022][u22]; [Brabec et al. 2021][b21]), but false statements can later be remembered as true ([Roediger & Marsh 2005][rm05]) | yes | Merged into Fix Tomo's mistake (its first step) |
| **Finish Tomo's phrase** (いってきます → いってらっしゃい; いただき… → ます) | 2さい+ | 3 bubbles, later voice or type | 4–8 s | `production` (with bubbles: `comprehension`) | offline | line + 3 bubbles or text field | filling in target words beat reading alone ([Hulstijn & Laufer 2001][hl01]); generation effect ([Slamecka & Graf 1978][sg78]) | per-language routines (good culture content) | **Next**, tied to time of day |
| **Say it with Tomo** (repeat after me, shadowing) | any | voice | 3–6 s | `exposure` only: copying isn't recall | offline | mic pill on the teach card | shadowing helped listening for lower-level learners ([Hamada 2016][h16]) and comprehensibility after 8 weeks ([Foote & McDonough 2017][fm17]); imitation measures proficiency only with sentences ([Yan et al. 2016][y16]) | yes | Optional add-on to Teach. Never scored |
| **Dictation** (type what you hear) | 3さい+ (Latin script), 4さい+ (kana) | type | 10–20 s | spelling, not meaning → `exposure` | offline (kana matching via Sudachi) | text field | not researched further; evidence for word learning is thin | per script; Japanese needs an input method, slow for beginners | **Later**, free play only |
| **Tomo's news** (a 2–3-line story or riddle, one question) | 2さい半+ | tap | 12–20 s | `comprehension` of the tested word + `exposure` to the rest | offline (scripted); AI-written later, checked against the age list | audio first; 3 picture tiles; text after | input first: children learned words from hearing stories, more with short explanations ([Elley 1989][e89]); comprehensible input ([Krashen 1982][k82]) | per-language writing | **Next** |
| **Song or rhyme** | any | listen (+ tap) | 20–60 s | `exposure` | offline, but needs sung audio (TTS can't sing) | too long | singing helped verbatim recall of foreign phrases ([Ludke et al. 2014][l14]) | per language; many children's songs are still under copyright | Free play only, later |
| **Sound pairs** (おばさん / おばあさん, きて / きって) | 3さい+ | tap | 4–6 s | `comprehension` (hearing the difference) | offline; needs clean audio | 2 picture tiles | high-variability listening training ([Logan, Lively & Pisoni 1991][llp91]) | per-language sounds | **Later** |
| **Odd one out / sort into groups** | — | tap, drag | 8–15 s | mostly category knowledge, little language | offline | sorting doesn't fit 3 targets | related new words learned together interfere ([Tinkham 1993][t93]; [Nation 2000][n00]) | yes | **Reject**. Keep "which one is food?" as a picture-choice prompt for category words |
| **Reading (kana)** | 4さい+ | tap the sound, or say it | 4–8 s | script knowledge: separate `kana:` items | offline | 1 kana word + 3 tiles or mic | a prerequisite skill, not vocabulary. Japanese children mostly learn to read hiragana between about 4 and 6 ([Shimamura 1998][s98]; exact ages **unverified**) | Japanese and other non-Latin scripts only | **Later**. Every line already shows kana meanwhile |
| **What's on your screen** | 3さい+ | Tomo names it, or asks you | 5–10 s | `exposure` / `production` | needs screen capture + image labels (on-device Vision or AI) | line + small thumbnail | learning in small moments of real context ([Edge et al. 2011][e11]; [Trusty & Truong 2011][tt11]; [Cai et al. 2015][c15]) | yes (labels → dictionary) | **Later, opt-in** (needs Screen Recording permission). A cheap first step: name the kind of app in front (no permission) |
| **"Tomo forgot" review** | — | — | — | — | — | — | — | — | **Reject** as a mechanic: [leveling-points.md](leveling-points.md) says Tomo never forgets and nothing visible decays. Due words come back as What's this? or picture choice. An occasional あれ？ なんだっけ？ line is fine |
| **Time-of-day routines** | all | — | — | — | offline | — | contextual study sessions happened in twice as many places ([Edge et al. 2011][e11]) | per language | **Not a mode**: a scheduler input (おはよう in the morning, まんま at lunch, ねんね at night) |

### Notes on the verdicts

- **Teaching works as a tiny game.** Toddlers pick the unnamed thing when they hear a new word ([Markman & Wachtel 1988][mw88]). But 2-year-olds who learned words this way forgot them 5 minutes later, unless the adult also named the object ([Horst & Samuelson 2008][hs08]). So Tomo names the new thing right after your pick (ブーブー！ これ ブーブー！), and the first real check waits for a later visit, where retrieval after a delay helps more ([Karpicke & Roediger 2007][kr07]). The very first words, before anything is known, use one picture and no distractors.
- **Listen and translate starts as a tap.** Typing the meaning is the step that best predicted classroom performance ([Laufer & Goldstein 2004][lg04]), but grading free text in the learner's language offline is hard. I tested Apple's `NLEmbedding` on this Mac (macOS 27.2). English, Spanish, French and German have embeddings, Japanese has none, and "doggy" is about as far from "dog" (cosine distance 0.93) as from "cat" (0.96), so embeddings can't grade. The typed version needs a short word list per item and per learner language (see the data shape), then the on-device model for the rest.
- **Saying it back isn't recall.** Repeat-after-me copies a sound that was just heard. It may help pronunciation over weeks of practice, but it says nothing about memory, and speech recognition would turn accent problems into Misses. Keep it as an unscored mic button.
- **Tomo's mistakes must be about words you know.** Wrong labels can be remembered as true ([Roediger & Marsh 2005][rm05]), and spotting errors helps only people who already know the right answer ([Große & Renkl 2007][gr07]). It suits Tomo, though: real toddlers call a cow ワンワン ([Rescorla 1980][r80]), and correcting a "care-receiving" robot helped Japanese preschoolers learn English verbs ([Tanaka & Matsuzoe 2012][tm12]).
- **Mixing modes isn't "interleaving".** The interleaving effect comes from learning categories. For word materials, a meta-analysis found blocking did better (g = −0.39; [Brunmair & Richter 2019][br19]). Interleaving Spanish tenses helped only across several sessions ([Pan et al. 2019][p19]). Spacing is the solid effect: medium to large in second-language learning, with longer gaps better on delayed tests ([Kim & Webb 2022][kw22]). So vary modes for fun and to measure different kinds of knowledge, and let the visits do the spacing.

## MVP: seven modes, ranked by value ÷ effort

| Rank | Mode | Value | Effort | What to build |
|---|---|---|---|---|
| 1 | Teach a new word | High: the only way new words come in, and it feels like play | Small | A `teach` round generated from a word entry: 2 known distractors from other categories, a naming line, no Miss |
| 2 | Picture choice | High: the core recognition check | Built; small upgrades | Distractor rules (known words from other categories early, the same category later); audio-first from 2さい |
| 3 | Do what Tomo says | Medium–high: verbs and care, which pictures can't show | Small | 6–8 actions mapped to existing animations |
| 4 | Listen and translate (tap) | Medium–high: phrases and words with no picture; pure listening | Small | 3 stacked meaning pills; target text hidden until the answer; the typed version later |
| 5 | What's this? | High: production, the strongest evidence | Medium | The chat card's mic and text field, `accept` lists, `contextualStrings`, the top 3 recognition alternatives, bubbles after one failed try |
| 6 | Fix Tomo's mistake | Medium–high: reviews known words; in character | Small once What's this? exists | A ⭕ / ❌ step, then the What's this? step |
| 7 | Conversation | High from 3さい | Built; the specs work is in [answer-evaluation.md](answer-evaluation.md) | Reply bubbles at 2さい半 |

**Unlocks by age**, so every half-year adds something new, as [leveling-points.md](leveling-points.md) proposes: 1さい teach, picture choice, do what Tomo says · 1さい半 listen and translate (tap), reply bubbles · 2さい what's this?, fix Tomo's mistake · 2さい半 bubbles in conversation (Tomo's news next) · 3さい conversation, typed translation. Below 2さい there's no production, so known words stay on recognition, using the harder audio-first variant. That keeps understanding before speaking.

## The mode scheduler

**Words first, modes second.** Pick the turn's words the way leveling-points.md already says: due words first (lowest recall), then at most one new word per visit and 10 per day, and no new words while the backlog is large. Then pick a mode for each word.

| Word state (`item_state.level`) | Step | Modes |
|---|---|---|
| new (`seen` or nothing) | hear | Teach |
| `met` | recognize | Picture choice, Do what Tomo says, Listen and translate (tap) |
| `known` | recall and say | What's this?, Fix Tomo's mistake, Finish Tomo's phrase, Listen and translate (type); 1 time in 4 still a recognition mode |
| `can_say`, `uses` | use | Conversation (when a starter uses the word), Fix Tomo's mistake, What's this? |

Then filter and weigh:

- **Age:** only unlocked modes.
- **Fit:** the mode must suit the word (a picture for picture modes, an action for Do what Tomo says, a routine for Finish Tomo's phrase).
- **Sound and mic:** audio-first modes need sound on; voice needs mic permission. Late at night, voice modes get less weight (others may be asleep, and an office can be awkward too).
- **Time budget:** a drop-in gets about 30 s, or 20 s if you only paused typing for a moment. Free play has no limit. Long modes drop out first.
- **Variety:** almost never the same mode twice in a row, and start visits with different modes.
- **Order:** after a break, one easy, well-known word first (as leveling-points.md says); a new word second, not first. A taught word becomes due 10 minutes later, so its first check comes in a later visit (in free play, after 3 other turns).
- **Time of day:** prefer words tagged for now (おはよう, まんま, ねんね).
- **Back-off:** after two production Misses on a word, drop back to recognition for a while.
- **Preference, later:** a weight per mode, 1.0 by default. Explicit settings ("no mic", "more listening") come first. Later, modes after which the learner often closes the visit can be weighted lower, within 0.5–1.5. Choice raises intrinsic motivation ([Patall et al. 2008][p08]), but production stays on the menu through typing and bubbles even with the mic off.

```swift
func planVisit(now: Date, kind: VisitKind) -> [Turn] {
    let age = tomo.age                                        // 1, 1.5, 2, 2.5, 3…
    let budget: Double = kind == .freePlay ? .infinity : (context.justPausedTyping ? 20 : 30)
    let unlocked = Mode.allCases.filter { $0.minAge <= age && $0.allowed(prefs, context) }
    //   allowed: audio-first needs sound on; voice needs the mic; reading needs the right script

    var words = store.due(now: now, limit: 3)                 // lowest recall first; a word taught
        .sorted { timeOfDayFit($0, now) > timeOfDayFit($1, now) }   // earlier is due 10 min later
    if store.daysAway >= 2, let easy = store.easiestKnownWord() {
        words.insert(easy, at: 0)                             // after a break: a warm-up first
    }
    if store.newToday < 10, store.overdueCount < 15, budget >= 20,
       let fresh = content.nextNewWord(age: age, now: now) {
        words.insert(fresh, at: min(1, words.count))          // second, not first
    }
    words = Array(words.prefix(3))

    var plan: [Turn] = [], used = 0.0
    for word in words {
        let mode = pickMode(for: word, among: unlocked, after: plan.last?.mode, budgetLeft: budget - used)
        guard let mode else { continue }
        plan.append(Turn(mode: mode, word: word))
        used += mode.typicalSeconds
    }
    return plan
}

func pickMode(for w: Word, among unlocked: [Mode], after last: Mode?, budgetLeft: Double) -> Mode? {
    let step: [Mode] = switch store.level(w) {
        case .new:            [.teach]
        case .met:            [.pictureChoice, .doWhatTomoSays, .listenTap]
        case .known:          Double.random(in: 0..<1) < 0.25
                                ? [.pictureChoice, .doWhatTomoSays, .listenTap]
                                : [.whatsThis, .fixMistake, .finishPhrase, .listenType]
        case .canSay, .uses:  [.conversation, .fixMistake, .whatsThis]
    }
    var options = step.filter { unlocked.contains($0) && $0.fits(w) && $0.typicalSeconds <= budgetLeft }
    if options.isEmpty {                                      // e.g. 1さい: no production yet
        options = Mode.recognition.filter { unlocked.contains($0) && $0.fits(w) && $0.typicalSeconds <= budgetLeft }
    }
    return options.weightedRandom { m in
        m.baseWeight
        * prefs.weight(m)                                     // the learner's preference, 1.0 by default
        * (m == last ? 0.05 : 1)                              // almost never twice in a row
        * (last == nil && history.lastFirstModes(3).contains(m) ? 0.5 : 1)  // vary how visits start
        * (m.isProduction && store.productionMisses(w, days: 2) >= 2 ? 0.3 : 1)
        * (m.usesVoice && isLateNight() ? 0.3 : 1)
    }
}
```

## Data shape in the language packs

**Write each word once; modes are templates.** Teach, picture choice, What's this? and Fix Tomo's mistake are all generated from one `words` entry plus per-language `modeLines`. Only listen-and-translate lines, routines and stories need their own `rounds`. `stages` stays until the age-vocabulary generator replaces it.

A word entry, which drives the "teach a new word" round, in `ja.json`:

```json
{
  "modeLines": {
    "teach":      { "say": "みて！ {w}！",      "romanization": "mite! {r}!" },
    "teachName":  { "say": "{w}！ これ {w}！",  "romanization": "{r}! kore {r}!" },
    "whatsThis":  { "say": "これ なあに？",      "romanization": "kore nāni?" },
    "fixMistake": { "say": "{w}！",             "romanization": "{r}!" },
    "yes": ["うん", "そう", "はい"],
    "no":  ["ううん", "ちがう", "いいえ"]
  },
  "words": [
    {
      "id": "ja:buubuu",
      "lrid": "9e27ffb688ffafe504a2acb91f4029c3",
      "say": "ブーブー",
      "romanization": "bū-bū",
      "meaning": { "en": "car (vroom vroom)" },
      "grownUp": "くるま（車）",
      "grownUpId": "ja:kuruma",
      "picture": "🚗",
      "kind": "thing",
      "category": "vehicle",
      "minAge": 1,
      "accept": ["ブーブー", "ぶーぶー"],
      "teach": { "praise": "ブーブー！ はやい！", "distractors": "known, other category" },
      "timeOfDay": null
    }
  ]
}
```

- `kind` decides which modes fit: `thing` (has a picture), `action` (Do what Tomo says), `routine` (Finish Tomo's phrase), `describing` (listen modes only).
- `accept` lists the forms What's this? and Fix Tomo's mistake take as this word. They also take the grown-up word (`grownUpId`, in any script Sudachi normalizes: くるま, 車), but credit goes to the item actually said: くるま credits `ja:kuruma`, because [learner-data-schema.md](learner-data-schema.md) keeps baby words and grown-up words as separate items.
- Both lists feed speech recognition's `contextualStrings`.

A "listen and translate" round, in the same pack:

```json
{
  "rounds": [
    {
      "id": "ja:wanwan-ita",
      "mode": "listen",
      "minAge": 1.5,
      "say": "ワンワン いた！",
      "romanization": "wan-wan ita!",
      "showText": "afterAnswer",
      "says":  ["ja:wanwan", "ja:iru"],
      "tests": ["ja:iru"],
      "meaning": { "en": "There's a doggy!" },
      "choices": {
        "en": ["There's a doggy!", "The doggy is sleeping.", "Where's the doggy?"]
      },
      "accept": {
        "en": {
          "ja:wanwan": ["dog", "doggy", "puppy", "woof"],
          "ja:iru":    ["there", "here", "see", "saw", "found", "look"]
        }
      },
      "reject": { "en": ["where", "sleep", "eat"] },
      "praise": "ワンワン かわいい！"
    }
  ]
}
```

- The tap level shows `choices` in the learner's language, shuffled; the first one is right. Missing languages fall back to English, as packs do today.
- The typed level lowercases and lemmatizes the answer (Apple's `NLTagger` lemma for English; Sudachi for a Japanese speaker learning English), then checks `accept` per item. It's a Win when every `tests` item has a hit and no `reject` word appears. Each item with a hit gets a `comprehension` row. Anything the lists can't decide goes to the on-device model, and with no model it gets No score.
- `says` and `tests` match the `round_item` roles in learner-data-schema.md.

## Scoring: Win / Miss / No score

Three rules apply to every mode:

1. **A Miss only when the app is sure.** A tap on a wrong target, or a recognized real word that's the wrong one. Unclear speech, an empty answer, or a grader that can't decide is No score, followed by a retry or bubbles.
2. **Hints and slow replays keep the Win but halve the credit**, as leveling-points.md already says. A normal replay is free.
3. **A retry after a Miss is a new turn but not a second review** that day, as the schema says.

| Mode | Win | Miss | No score | Evidence written |
|---|---|---|---|---|
| Teach a new word | — | — | Always: a "new word" badge. A wrong pick just shows the right one | `exposure` (`tomo_voice`, `card`) |
| Picture choice | the right picture | a wrong picture | help | `comprehension`, `via = picture` |
| Do what Tomo says | the right action | a wrong action | help | `comprehension`, `via = action` |
| Listen and translate (tap) | the right meaning | a wrong meaning | help | `comprehension`, new `via = meaning` |
| Listen and translate (type) | every tested item hit, no reject word | a real but wrong meaning ("sleeping") | blank, gibberish, or the grader can't decide | `comprehension` per item hit, `via = typed` |
| What's this? | any `accept` form, spoken or typed | a different real word (ニャンニャン for 🐶), or a wrong bubble | nothing usable heard, wrong language, help → bubbles | `production` right/wrong; bubbles: `comprehension`, `via = reply_bubble` |
| Fix Tomo's mistake | caught the mistake (❌), or agreed when Tomo was right (⭕) | agreed with a mistake, or rejected a right label | help | step 1: `comprehension` (low weight: 1 in 2 is a guess); step 2: `production` if the word is said right |
| Finish Tomo's phrase | the right response | a wrong response (いってきます back) | unclear speech, help | `production`; bubbles: `comprehension` |
| Tomo's news | the right picture | a wrong picture | help | `comprehension` for `tests`; `exposure` for the rest |
| Conversation | understood | tried in the target language, not understood | wrong language, help | as built |
| Say it with Tomo | — | — | no badge at all | `exposure` |

Suggested boosts for leveling-points.md's table: Listen and translate (type) is passive recall, so about 1.3, between bubbles (1.2) and saying a word (1.5). Fix Tomo's mistake step 1 is 0.5. Both are guesses to tune.

## Risks

- **Feeling like study.** Translation into your own language, typed answers, dictation and kana drills feel like homework. Lead with Tomo's voice, keep learner-language text small, allow at most one typed-in-your-language turn per visit, and never start a visit with one. The framing stays play: みて！, これ なあに？, Tomo getting things wrong.
- **Too long for a visit.** Conversation, Tomo's news, songs, dictation and the two-step mistake mode can each take 15 s or more. The time budget drops them first. Three conversation answers rarely fit 30 s, so a 3さい visit may be one quick tap turn plus one exchange.
- **Speech recognition frustration.** Learner accents, very short words (うん / ううん / うーん are easy to confuse), background noise, and speaking aloud in an office or at night. Use `contextualStrings`, the top 3 alternatives, bubbles after one failed try, a "no mic" setting, and No score for unclear speech.
- **Guessing and false knowledge.** Tap modes can be guessed (1 in 3, or 1 in 2 for ⭕ / ❌). Low weights and the once-per-day rule absorb this. Wrong labels and distractors can be learned, so Tomo's mistakes use only known words, and the right answer always shows right after.
- **Unfair exclusion.** Teach relies on the two other pictures being known. Use only words with high recall, and never give a Miss.
- **Too many modes.** Each new mode needs a one-line card hint the first time it appears (Tomo can't explain in your language). Unlock one per half-year, and keep one visual grammar: tiles mean tap, a field with a mic means say it.
- **Content cost across pairs.** Generated modes cost nothing per pair. Authored ones (meaning choices, concept lists, routines, stories) multiply by learner languages × target languages, and routines need a native-speaker review.
- **Pictures.** Emoji can't show abstract words, look different across platforms, and can be culture-specific (🍙). That's one reason Listen and translate exists.
- **Accessibility.** Audio-first modes exclude learners who can't hear them or have sound off. Always offer "show text".
- **Privacy.** Screen naming needs Screen Recording permission, and voice needs the mic. Both stay opt-in.

## Open questions

- Does tapping an action on Tomo carry any of TPR's benefit, or is it just a picture choice with verbs? An A/B test against plain picture choice would tell.
- Should a teach turn count as one of the visit's 3 answers?
- Schema additions: `round.kind` values (`teach`, `pick_meaning`, `translate`, `fix_mistake`, `finish_phrase`, `news`), `via = meaning`, and `kana:` item IDs. Update [learner-data-schema.md](learner-data-schema.md) when the first one is built.
- How often will typed translations need the AI? Label about 100 real answers to find out.
- Should audio-first be the default from 2さい, or a setting?
- Default distractor difficulty: other categories for `met` words, the same category for `known` words?
- Where do learner preferences live: a few settings, or something learned from closed visits?

## Sources

Language learning and memory:
- Krashen (1982), *Principles and Practice in Second Language Acquisition* (author's free PDF): https://www.sdkrashen.com/content/books/principles_and_practice.pdf
- Asher (1969), *Modern Language Journal*: https://doi.org/10.1111/j.1540-4781.1969.tb04552.x
- Swain & Lapkin (1995), *Applied Linguistics*: https://doi.org/10.1093/applin/16.3.371
- Laufer & Goldstein (2004), *Language Learning*: https://doi.org/10.1111/j.0023-8333.2004.00260.x
- Laufer & Hulstijn (2001), *Applied Linguistics* (involvement load): https://doi.org/10.1093/applin/22.1.1
- Hulstijn & Laufer (2001), *Language Learning*: https://doi.org/10.1111/0023-8333.00164
- Laufer & Girsai (2008), *Applied Linguistics*: https://doi.org/10.1093/applin/amn018
- Webb (2009), *RELC Journal*: https://doi.org/10.1177/0033688209343854
- Roediger & Karpicke (2006), *Psychological Science*: https://doi.org/10.1111/j.1467-9280.2006.01693.x
- Karpicke & Roediger (2007), *JEP: Learning, Memory, and Cognition*: https://doi.org/10.1037/0278-7393.33.4.704
- Karpicke & Roediger (2008), *Science*: https://doi.org/10.1126/science.1152408
- Slamecka & Graf (1978), *JEP: Human Learning and Memory*: https://doi.org/10.1037/0278-7393.4.6.592
- Bertsch et al. (2007), *Memory & Cognition*: https://doi.org/10.3758/BF03193441
- Roediger & Marsh (2005), *JEP: Learning, Memory, and Cognition*: https://doi.org/10.1037/0278-7393.31.5.1155
- Butler & Roediger (2008), *Memory & Cognition*: https://doi.org/10.3758/MC.36.3.604
- Brabec, Pan, Bjork & Bjork (2021), *Educational Psychology Review*: https://doi.org/10.1007/s10648-020-09546-w
- Uner, Tekin & Roediger (2022), *JEP: Applied*: https://doi.org/10.1037/xap0000363
- Große & Renkl (2007), *Learning and Instruction*: https://doi.org/10.1016/j.learninstruc.2007.09.008
- Chase, Chin, Oppezzo & Schwartz (2009), *Journal of Science Education and Technology*: https://doi.org/10.1007/s10956-009-9180-4
- Tanaka & Matsuzoe (2012), *Journal of Human-Robot Interaction*: https://doi.org/10.5898/JHRI.1.1.Tanaka
- Brunmair & Richter (2019), *Psychological Bulletin*: https://doi.org/10.1037/bul0000209
- Pan et al. (2019), *Journal of Educational Psychology*: https://doi.org/10.1037/edu0000336
- Kim & Webb (2022), *Language Learning*: https://doi.org/10.1111/lang.12479
- Tinkham (1993), *System*: https://doi.org/10.1016/0346-251X(93)90027-E
- Nation (2000), *TESOL Journal*: https://doi.org/10.1002/j.1949-3533.2000.tb00239.x
- Macedonia & Knösche (2011), *Mind, Brain, and Education*: https://doi.org/10.1111/j.1751-228X.2011.01129.x
- Hamada (2016), *Language Teaching Research*: https://doi.org/10.1177/1362168815597504
- Foote & McDonough (2017), *Journal of Second Language Pronunciation*: https://doi.org/10.1075/jslp.3.1.02foo
- Yan et al. (2016), *Language Testing*: https://doi.org/10.1177/0265532215594643
- Logan, Lively & Pisoni (1991), *JASA*: https://doi.org/10.1121/1.1894649
- Elley (1989), *Reading Research Quarterly*: https://doi.org/10.2307/747863
- Ludke, Ferreira & Overy (2014), *Memory & Cognition*: https://doi.org/10.3758/s13421-013-0342-5
- Patall, Cooper & Robinson (2008), *Psychological Bulletin*: https://doi.org/10.1037/0033-2909.134.2.270

Child language:
- Markman & Wachtel (1988), *Cognitive Psychology*: https://doi.org/10.1016/0010-0285(88)90017-5
- Horst & Samuelson (2008), *Infancy*: https://doi.org/10.1080/15250000701795598
- Tomasello & Farrar (1986), *Child Development*: https://doi.org/10.2307/1130423
- Yu & Smith (2007), *Psychological Science*: https://doi.org/10.1111/j.1467-9280.2007.01915.x
- Rescorla (1980), *Journal of Child Language*: https://doi.org/10.1017/S0305000900002658
- Shimamura (1998), 文字習得のふしぎ, NINJAL: https://doi.org/10.15084/00003332

Learning in small moments (HCI):
- Edge et al. (2011), MicroMandarin, CHI: https://doi.org/10.1145/1978942.1979413
- Trusty & Truong (2011), CHI: https://doi.org/10.1145/1978942.1979114
- Cai et al. (2015), Wait-Learning, CHI: https://doi.org/10.1145/2702123.2702267

Checked on this Mac (macOS 27.2, 2026-10-03): [`NLEmbedding`](https://developer.apple.com/documentation/naturallanguage/nlembedding) word and sentence embeddings exist for en, es, fr and de, not ja. This repo: [leveling-points.md](leveling-points.md), [learner-data-schema.md](learner-data-schema.md), [answer-evaluation.md](answer-evaluation.md), [TomoGame.swift](../../mac-demo/NotchBuddy/Sources/App/TomoGame.swift), [TomoView.swift](../../mac-demo/NotchBuddy/Sources/App/TomoView.swift), [ja.json](../../mac-demo/NotchBuddy/Resources/languages/ja.json).

[asher]: https://doi.org/10.1111/j.1540-4781.1969.tb04552.x
[sl95]: https://doi.org/10.1093/applin/16.3.371
[lg04]: https://doi.org/10.1111/j.0023-8333.2004.00260.x
[hl01]: https://doi.org/10.1111/0023-8333.00164
[lgi08]: https://doi.org/10.1093/applin/amn018
[w09]: https://doi.org/10.1177/0033688209343854
[rk06]: https://doi.org/10.1111/j.1467-9280.2006.01693.x
[kr07]: https://doi.org/10.1037/0278-7393.33.4.704
[kr08]: https://doi.org/10.1126/science.1152408
[sg78]: https://doi.org/10.1037/0278-7393.4.6.592
[b07]: https://doi.org/10.3758/BF03193441
[rm05]: https://doi.org/10.1037/0278-7393.31.5.1155
[br08]: https://doi.org/10.3758/MC.36.3.604
[b21]: https://doi.org/10.1007/s10648-020-09546-w
[u22]: https://doi.org/10.1037/xap0000363
[gr07]: https://doi.org/10.1016/j.learninstruc.2007.09.008
[c09]: https://doi.org/10.1007/s10956-009-9180-4
[tm12]: https://doi.org/10.5898/JHRI.1.1.Tanaka
[br19]: https://doi.org/10.1037/bul0000209
[p19]: https://doi.org/10.1037/edu0000336
[kw22]: https://doi.org/10.1111/lang.12479
[t93]: https://doi.org/10.1016/0346-251X(93)90027-E
[n00]: https://doi.org/10.1002/j.1949-3533.2000.tb00239.x
[mk11]: https://doi.org/10.1111/j.1751-228X.2011.01129.x
[h16]: https://doi.org/10.1177/1362168815597504
[fm17]: https://doi.org/10.1075/jslp.3.1.02foo
[y16]: https://doi.org/10.1177/0265532215594643
[llp91]: https://doi.org/10.1121/1.1894649
[e89]: https://doi.org/10.2307/747863
[l14]: https://doi.org/10.3758/s13421-013-0342-5
[p08]: https://doi.org/10.1037/0033-2909.134.2.270
[k82]: https://www.sdkrashen.com/content/books/principles_and_practice.pdf
[mw88]: https://doi.org/10.1016/0010-0285(88)90017-5
[hs08]: https://doi.org/10.1080/15250000701795598
[tf86]: https://doi.org/10.2307/1130423
[ys07]: https://doi.org/10.1111/j.1467-9280.2007.01915.x
[r80]: https://doi.org/10.1017/S0305000900002658
[s98]: https://doi.org/10.15084/00003332
[e11]: https://doi.org/10.1145/1978942.1979413
[tt11]: https://doi.org/10.1145/1978942.1979114
[c15]: https://doi.org/10.1145/2702123.2702267
