# How Tomo grows

What a learner sees of Tomo growing (levels and ages, word stages, the screens that show it, and how
fast it goes), and the rules behind it. The rest of what a learner sees is in
[concepts.md](concepts.md); the other systems are mapped in [architecture.md](architecture.md).

## What a learner sees

| Concept | How it works |
|---|---|
| **Levels and ages** | Tomo has levels: small sets of words. When 9 in 10 of a level's words reach "knows it", Tomo levels up (Lv 2, Lv 3…): it crouches, leaps with star eyes in a burst of sparkles and sparkle dust, lands with a wobble and settles happy, with a happy sound, and the next set unlocks. Some levels are birthdays, like a Pokémon evolving: 1さい speaks single baby words (ワンワン, まんま), 2さい evolves and uses two-word phrases (ワンワン いた！), 3さい has real short conversations. The header shows "1さい · Lv 2". A full-width experience bar under it moves a little with every answer that counts (each stage one of the level's best 9 words reaches, up to "knows it"). On the Mac a +1 flies from the result into it, and the fill glows, shines and bounces as it lands; at a birthday the bar fills with Tomo's own colour. Its last tenth is the goal, set apart: it fills only when the level is done, so the bar never looks full before. It never moves back: a slip sets the word back, not the bar, and that word's part turns pale until it's answered right again. Under Tomo's word the card says what's left, in one line: "1 more word to Lv 2 · ready now", "· next one at 8:37", or "· next one tomorrow" (no time, so it fits). Level and age never go down, and Tomo is never younger than its level's age (a Tomo saved before the pack's ages moved catches up when it loads), so each birthday comes exactly where the pack's age goes up. Japanese goes to 6さい (274 levels), English to 3さい (66 levels); Spanish has small placeholders. |
| **Word stages** | Every word has a stage, following WaniKani's published rules in our own code: just heard (1–4) → knows it (5–6) → good at it (7) → loves it (8) → forever (9, never asked again). A right answer moves a word up one stage when it's due, or early once at least half its wait has passed; Tomo asks again after 4 h, 8 h, 1 day, 2 days, 1 week, 2 weeks, 1 month, then 4 months (levels 1–2 start faster). Wrong tries in the same round move it down, twice as far from "knows it" up. Right after the hint, it stays. Answering again sooner is practice: Tomo still reacts, nothing moves (the badge says **Practice**) |
| **Seeing Tomo grow** | The same screens on the Mac and the iPhone. **Tomo**: a live Tomo, its age and level, the bar to the next level and what's left ("1 more word to Lv 2 · ready now", or when it's back while it rests), days together, today ("12 answers · 3 new words · 5 days in a row · Lv 61 → 62"), growing up as a height pillar (a mark with its day for every level Tomo reaches, a big one at each birthday, Tomo standing beside it at its age's form; slide back in time and Tomo shrinks to that day; tap a mark for its words; Every age shows each age and what it brings), and Play with Tomo. **Words**: every level, locked ones too, opening at Tomo's level, with each word's picture, reading, meaning, stage and when it's due. **Together**: today, with the streak (days in a row with an answer); Tomo's word garden, where every word met is a plant grown to its stage (sprout, leaves, bud, flower, star), pale if it slipped, glowing when it was met or grew today, this week or since you met, watered by practice, with Tomo strolling through, a tap for a word, a replay from the first day, Copy recap, and the learner's own log to export as Markdown or JSON; and Tomo's week as a postcard that comes every Monday morning: the week's picture word and Tomo on the front, Tomo's message and what you did on the back (new words, wins, practice, misses, words that got stronger, the week's longest run of days in a row, the level, days together), turned over with a tap and shared as a picture; every earlier postcard underneath. A quiet week's postcard shows Tomo asleep; a brand-new Tomo's says when the first one comes; that Monday, the Tomo screen says it came. **Tomo's diary**, at the bottom of Together: a page for every day you played, in Tomo's own toddler words (the day's words, a sulk when you come back after days apart, a cheer for growing or a run of days, a groan on a hard day), with the day's words as stickers and what you did; days apart show between pages. Stats count what happened on this device for now ([stats.md](stats.md)). On the Mac they're pages of the Tomodachi window: click Tomo's age in the notch header for Tomo, Tomo → Tomo's words (⌘W) for Words. On the iPhone they're tabs. |

## The levels

The rules are in `TomoProgress.swift`; the levels come from the language pack, built from Wordbank's
toddler word data (CDI): each word's age is when half of children understand it (by 19 months: 1さい)
or say it (24–35 months: 2さい; later: 3さい), earliest first, in levels of 10. **Japanese, up to 6さい:**
2,712 words in 274 levels. Lv 1–15 are 1さい (バイバイ, ママ, ワンワン, まんま…), Lv 16–60 2さい, Lv 61 is 3さい
(talking starts), then Lv 92 4さい, Lv 121 5さい, Lv 180–274 6さい. Past 3, the words come from NINJAL's
preschool and picture-book word lists with English meanings from JMdict (ages assigned by how many
preschoolers used a word and in how many books it appears; an assumption to tune). **English** (for
Japanese speakers; each word has a Japanese meaning): 647 words; Lv 1–26 are 1さい (Daddy, Hi, Mommy,
Ball, Dog…), Lv 27–56 2さい, Lv 57 talking, Lv 58–66 later words. Built by
`mac-demo/scripts/build-levels.py` ([languages.md](languages.md)). The self-test simulates learners
with these rules ([verification.md](verification.md)): one who is always right and plays the moment
anything counts reaches Lv 2 in 19 hours, 2さい in 24 days and 3さい in 101; one who is right 85% of the
time, with 3 visits and 10 answers of free play a day, in 5.5, 99 and 442 days (always right on that
schedule: 3さい in 311; with 30 answers of free play: 299). Pacing is
[#38](https://github.com/serpcompany/tomodachi-app/issues/38). Spanish still has small placeholder
levels.

## The rules

`TomoProgress.swift` holds every rule: word stages and their waits (`TomoSRS`), levels and
birthdays, what to ask next, and whether a right answer counts. `TomoGame` asks; only `TomoProgress`
decides. Invariants:
- An answer counts only when the word is due, or at least halfway through its wait.
- Level and age never go down, and the experience bar never moves back (it uses each word's best
  stage).
- The bar counts the level's best `levelNeeded` words, and its goal (`goalShare`, the last tenth)
  fills only when the level is done. Every surface draws the same number (`TomoGrowthBar` on the
  card, the iPhone's play screen and the Tomo screen; the glance for widgets). The card's catches up
  as a counted answer's +1 lands in it, under a second later (`TomoLevelBar.swift`).
- Practice is a mode the learner picks, and it never moves the bar.

`TomoClock` moves time for testing, and `TOMO_SELFTEST=1` checks the rules. Planned:
[#38](https://github.com/serpcompany/tomodachi-app/issues/38).
