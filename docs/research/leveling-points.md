# Leveling and points: how Tomo grows

Research for the open question in [concepts.md](../concepts.md): how should points and levels work so growth feels earned and can't be crammed? Written 2026-10-03.

## Answer

Don't use XP. Give every word a hidden **memory strength** from a simplified FSRS model. Its *stability* is the number of days until recall drops to 90%. Update it **at most once per word per day**, weighted by how strong the evidence is: tapping a picture < tapping a Japanese reply < saying the word < using it in a sentence. A word is **known** at a stability of 4 days, which takes right answers on 2–3 different days. Tomo grows half a year at a time when its known words pass thresholds at the low end of real toddlers' vocabularies (50 → 1さい半, 150 → 2さい, 280 → 2さい半, 450 → 3さい). The once-a-day rule and a cap of 10 new words a day stop grinding; free play stays unlimited but can't go past them. Tomo never shrinks or forgets. Words the learner is forgetting just come up more often. Show Tomo's growth and the words it picks up from you, not points or streaks. In a simulation, 10 visits a day reach 2さい in about 4 weeks and 3さい in about 11.

## Proposal

### Events

| Event | Mode (from age) | Kind of evidence ([Laufer & Goldstein 2004](https://doi.org/10.1111/j.0023-8333.2004.00260.x)) | First-time stability S0 | Boost B |
|---|---|---|---|---|
| Tap the right picture or do the right action | 1さい | passive recognition (easiest; 1 in 3 can be a guess) | 1 day | 1.0 |
| Tap the right Japanese reply bubble | 1さい半 | active recognition | 1 day | 1.2 |
| Say or type a single word Tomo understands | 2さい | active recall | 2 days | 1.5 |
| Use a tracked word or pattern in a short sentence | 3さい | active recall in context | 2 days | 1.5 |
| Reply sensibly to a Tomo line (`understood = true`) | 3さい | each tracked word in Tomo's line counts as passive recall | 1 day | 0.5 |
| Answered right after a hint or slow replay | any | weaker | same | B × 0.5 |
| Wrong answer (ちがう〜) | any | lapse | — | S × 0.5 (minimum 0.5 days) |
| ん？ (not understood, possibly a speech-recognition miss) | production | none | — | no change |
| Visit ignored, or the same word answered again the same day | any | none | — | 0 (Tomo still reacts) |

The boosts follow the difficulty order Laufer & Goldstein confirmed with 435 learners: passive recognition < active recognition < passive recall < active recall. The one exception is conversation credit, which is kept low because it covers every word in Tomo's line, and context can carry the meaning. This proposal moves reply bubbles from 2さい ([#15](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/15)) to 1さい半, so each half-year adds something new.

### Formulas

Retrievability, the chance of recalling a word *t* days after its last review, uses the FSRS-4.5 forgetting curve ([FSRS wiki](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm)):

```
R(t, S) = (1 + 19/81 · t/S) ^ -0.5        # R = 0.9 when t = S
```

On the **first graded answer for a word on a given day** (the day starts at 4 am, as in [Anki](https://docs.ankiweb.net/preferences.html)):

```
new word, correct:  S = S0[mode]
correct:            S = S × (1 + B[mode] × h × min(3, (1 − R) / 0.1))   # h = 0.5 if a hint was used
wrong:              S = max(0.5, S × 0.5)
due for review:     R ≤ 0.9   (t ≥ S)
known:              S ≥ 4 days
```

- On time (R = 0.9), a tap doubles S, like Leitner's 1 → 2 → 4 boxes. A spoken answer multiplies it by 2.5, SM-2's starting E-Factor.
- An early review earns little. A word recalled after a long gap earns up to 4× (5.5× spoken). That is the spacing effect ([Cepeda et al. 2006](https://doi.org/10.1037/0033-2909.132.3.354)).
- Taps reach "known" after right answers on 3 different days (1 → 2 → 4); speaking takes 2 (2 → 5). A pure guesser passes three taps 1 time in 27.
- A wrong answer halves S instead of resetting it, as Leitner and SM-2 would. Taps are noisy, and nothing about the miss is shown.

**Level-up:** Tomo grows when its known words (cumulative) reach the next threshold. Age **never goes down**. Growth shows at the next day's first visit ("Tomo grew in its sleep").

| Tomo | Known words | Median Japanese child, words said (Wordbank J-CDI, from [age-vocabulary-data.md](age-vocabulary-data.md)) |
|---|---|---|
| 1さい | 0 (start) | half say 6 words by 17 months |
| 1さい半 | 50 | 45 at 18–20 months (and understands 177). In every Wordbank language, the median child says 50 words at 16–20 months ([Frank et al. 2021](https://langcog.github.io/wordbank-book/vocabulary.html)) |
| 2さい | 150 | 282 at 24–26 months. The spread is wide: US 2-year-olds average 319 words, SD 175 ([same chapter](https://langcog.github.io/wordbank-book/vocabulary.html)) |
| 2さい半 | 280 | 401 at 30–32 months |
| 3さい | 450 | 586 at 36–41 months, near the 711-word checklist ceiling ([Hagihara et al. 2023](https://doi.org/10.17605/osf.io/s5ydw)); real vocabulary is higher |
| 4さい | ~800 + a conversation check: at least 70% of turns understood, on 5 or more days (placeholder) | — |

1さい半 matches the median. Later thresholds are 53–77% of it, a "late talker", so birthdays arrive within weeks rather than months. Once Tomo's word list for each age exists, set each threshold at about 75% of that list (the README's "70–80% mastery" idea).

### Example timeline

From a throwaway simulation of these rules (not committed): median of 30–40 simulated learners, 3 answers per visit, at most 1 new word per visit, due reviews first. The simulated learner forgets exactly as the model says, so this checks the rules; it isn't a forecast.

| Learner | First known word | 1さい半 | 2さい | 3さい |
|---|---|---|---|---|
| **10 visits/day, every day** | day 4 | day 12 | **day 27 (about 4 weeks)** | **day 77 (about 11 weeks)** |
| Same, but forgets 40% faster than modeled | day 4 | day 12 | day 28 | day 87 |
| 10 visits on weekdays only | — | day 15 | day 36 | day 113 |
| 3 visits + about 15 free-play answers a day | — | day 16 | day 36 | day 107 |
| 10 visits + 100 free-play answers a day | — | day 9 | day 19 | day 48 (the cap on new words sets this limit) |
| 100 extra visits on day 1 (cramming) | — | day 12 | day 27 | day 77 (no gain) |
| 10 visits, away days 30–44 | — | day 12 | day 27 | day 94 (no regression) |

About 90% of due reviews are recalled, which is FSRS's default target ([Anki manual](https://docs.ankiweb.net/deck-options.html)).

### Forgetting without guilt

- **Tomo doesn't forget.** The learner's forgetting lives only in the hidden model. A due word comes back in a visit as play ("ねえ、これ なあに？"), never as "you forgot".
- **Nothing visible decays.** Duolingo's strength meters had learners practicing "just to keep the tree gold" instead of what they needed, and complaining when words decayed fast no matter what they did ([Settles & Meeder 2016](https://aclanthology.org/P16-1174/)). Once known, a word stays in Tomo's word book.
- **Coming back is cheap.** After a break, Tomo is sleepy and happy. Visits start with one easy word, then the most overdue ones, and no new words until the backlog thins. The backlog is never shown as a number.

### Visits vs free play (anti-grind)

An answer scores the same in a visit or in free play; visits matter because they spread practice out. Three limits replace an XP cap:

1. One stability update per word per day.
2. 10 new words a day, shared by visits and free play (at most 1 per visit).
3. Early reviews earn little (the `1 − R` term).

Free play past these limits still gets Tomo's full reactions. Duolingo found that learners who binge are much more likely to quit ([Duolingo 2017](https://blog.duolingo.com/how-streaks-keep-duolingo-learners-committed-to-their-language-goals)).

### What to show

Show growth and competence, not points: Tomo's body at each half-year; Tomo **using words you taught it** on its own (a small reward for every known word); an optional word book (ことば ずかん) with a count; "もうすぐ 2さい！" near the next age. At most, a "days together" total that never resets. Never a streak.

### Tuning

| Knob | Default | Effect |
|---|---|---|
| New words per day | 10 | The main pace control and the hard limit on grinding |
| Known threshold | S ≥ 4 days | Higher = slower but longer-lasting growth |
| B and S0 per mode | table above | How much each answer mode is worth |
| Age thresholds | 50/150/280/450 | Matching the Japanese medians (45/282/401/586) moves 2さい to day 53 and 3さい to day 111 at 10 visits a day (simulated) |
| Answers per visit, visits per day | 3, chattiness setting | Light users mostly need more answers |

Watch recall on due reviews (aim for 85–90%; if lower, cut B), days to each age (first known word by day 3–4, 1さい半 within about 2 weeks), ignored visits, and D7/D30 return. Log every answer (word, mode, correct, hint, timestamp) so the FSRS optimizer can fit real parameters later, or so [swift-fsrs](https://github.com/open-spaced-repetition/swift-fsrs) (FSRS-5) can replace these formulas. See [learner-data-schema.md](learner-data-schema.md).

## Options compared

| Option | Can't cram? | Fits taps → talk? | Honest "age"? | Effort | Verdict |
|---|---|---|---|---|---|
| Count right answers (demo now) | No: done in minutes | Yes | No | Done | Replace |
| XP + daily cap (Duolingo-style) | Partly | Yes | No: XP measures activity, not knowledge | Low | No |
| Leitner boxes ([as described by Settles & Meeder](https://aclanthology.org/P16-1174/)) | Yes | One step size for every mode | OK | Low | Fallback |
| [SM-2](https://super-memory.com/english/ol/sm2.htm) | Yes | Needs 0–5 grades, but taps give only right/wrong; "ease hell" ([Anki](https://docs.ankiweb.net/deck-options.html)) | OK | Low | No |
| **FSRS-lite (this proposal)** | Yes | Yes, through mode weights | Good | Medium | **Use now** |
| Full FSRS, trained parameters ([Ye et al. 2022](https://doi.org/10.1145/3534678.3539081)) | Yes | Again/Hard/Good/Easy map awkwardly to taps | Best | Medium; needs logs first | Later |
| Grow by days only (Tamagotchi) | Yes | — | No | Trivial | No |

## Evidence from apps and pets

- **Streaks work, and they hurt when they break.** A 7-day streak makes learners 2.4× more likely to return the next day ([Duolingo 2020](https://blog.duolingo.com/improving-the-streak)). Offering a break (the "Weekend Amulet") made learners 4% more likely to return a week later ([Duolingo 2017](https://blog.duolingo.com/how-streaks-keep-duolingo-learners-committed-to-their-language-goals)). In seven studies, broken streaks lowered later engagement, more so when people blamed themselves and less when they could repair the streak ([Silverman & Barasch 2023](https://doi.org/10.1093/jcr/ucac029)). So: no streak.
- **Points can push out learning.** In a study of Duolingo forums and interviews, some users fixated on points and leaderboards at the cost of learning ([Hadi Mogavi et al. 2022](https://arxiv.org/abs/2203.16175)).
- **Self-determination theory.** Motivation rests on competence, autonomy and relatedness ([Ryan & Deci 2000](https://doi.org/10.1037/0003-066X.55.1.68)), and all three predict game enjoyment and continued play ([Ryan, Rigby & Przybylski 2006](https://doi.org/10.1007/s11031-006-9051-8)). Across 128 studies, expected tangible rewards undermined intrinsic motivation (engagement-contingent: d = −0.40), while positive feedback raised it (d = 0.33) ([Deci, Koestner & Ryan 1999](https://doi.org/10.1037/0033-2909.125.6.627)). Tomo's growth should read as feedback, not payment.
- **Tamagotchi** ages in real time (reportedly one year per day) and grows differently depending on care. Neglect could kill it, which upset children and led schools to ban it ([Wikipedia](https://en.wikipedia.org/wiki/Tamagotchi); Bandai manual unverified). Keep the daily clock and drop the death.
- **Animal Crossing** keeps time in step with the real world on purpose, though plenty of players change the clock. Mr. Resetti's shouting made some young players cry, so *New Leaf* made him optional ([Iwata Asks](https://iwataasks.nintendo.com/interviews/3ds/animalcrossing-newleaf/0/1)). So: a real clock, and no scolding.

## Risks and open questions

- **Untested parameters.** All values are guesses until real logs exist. The simulation treats all words as equally hard; FSRS adds per-word difficulty.
- **Honest age.** Age never drops, so someone away 6 months is still "3さい". Should the "your Japanese is like a 3-year-old's" line count only words that are strong now (R ≥ 0.8)?
- **Light users grow slowly.** With 3 visits a day and no free play, 2さい takes about 3.5 months in the simulation. Should quiet mode use 5 answers per visit?
- **Noisy evidence.** Guessed taps, speech-recognition misses, and AI "understood" calls at 3さい. See [answer-evaluation.md](answer-evaluation.md).
- **Clock changes.** Moving the clock only cheats yourself. Ignore it unless it becomes common.
- **Adults aren't toddlers.** They know abstract words but few baby words, so the age is a fun mirror, not a test.

## Sources

- FSRS algorithm (formulas): https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm
- Ye, Su & Cao (2022), KDD: https://doi.org/10.1145/3534678.3539081
- Su et al. (2023), IEEE TKDE: https://doi.org/10.1109/TKDE.2023.3251721
- Anki manual, deck options and preferences: https://docs.ankiweb.net/deck-options.html, https://docs.ankiweb.net/preferences.html
- swift-fsrs: https://github.com/open-spaced-repetition/swift-fsrs
- Wozniak (1990), SM-2: https://super-memory.com/english/ol/sm2.htm
- Settles & Meeder (2016), ACL (HLR, Leitner): https://aclanthology.org/P16-1174/
- Cepeda et al. (2006), *Psychological Bulletin*: https://doi.org/10.1037/0033-2909.132.3.354
- Laufer & Goldstein (2004), *Language Learning*: https://doi.org/10.1111/j.0023-8333.2004.00260.x
- Frank, Braginsky, Yurovsky & Marchman (2021), *Variability and Consistency in Early Language Learning* (Wordbank), MIT Press: https://langcog.github.io/wordbank-book/
- Hagihara et al. (2023), Japanese CDI dataset: https://doi.org/10.17605/osf.io/s5ydw
- Duolingo blog (2017, 2020): https://blog.duolingo.com/how-streaks-keep-duolingo-learners-committed-to-their-language-goals, https://blog.duolingo.com/improving-the-streak
- Silverman & Barasch (2023), *Journal of Consumer Research*: https://doi.org/10.1093/jcr/ucac029
- Hadi Mogavi et al. (2022), L@S: https://arxiv.org/abs/2203.16175
- Ryan & Deci (2000), *American Psychologist*: https://doi.org/10.1037/0003-066X.55.1.68
- Ryan, Rigby & Przybylski (2006), *Motivation and Emotion*: https://doi.org/10.1007/s11031-006-9051-8
- Deci, Koestner & Ryan (1999), *Psychological Bulletin*: https://doi.org/10.1037/0033-2909.125.6.627
- Iwata Asks, *Animal Crossing: New Leaf*: https://iwataasks.nintendo.com/interviews/3ds/animalcrossing-newleaf/0/1
- Tamagotchi (secondary source): https://en.wikipedia.org/wiki/Tamagotchi
