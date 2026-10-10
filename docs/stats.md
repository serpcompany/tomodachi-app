# Stats: what you and Tomo did together

What the stats screens count, where the numbers come from, and the rules they keep. Stats are four
screens built in stages from [Stats, Take Two](reference/tomo/stats-take-two.html) ([#137](https://github.com/serpcompany/tomodachi-app/issues/137),
item 2): Tomo's week as a postcard first, then the word garden, a height pillar for growing up and Tomo's
diary, all on the same layer. The code: `TomoStats.swift` (the layer), `TomoStatsExport.swift` (the recap
and the export), `TomoGarden.swift` (the garden), `TomoPostcard.swift` and `TomoPostcardView.swift` (Tomo's
week), `TomoTogetherScreen.swift` (the Together screen).

## One layer

- `TomoStats` takes the `TomoProgress` it describes, so another Tomo (a friend) has its own. Every
  screen and the Today line read it; no screen counts anything itself. The Together screen and the
  postcard also take the Tomo's look and material (the learner's own: `.own`, jelly), and so does the
  picture they share: it's made for this learner when they share it, so it shows their own Tomo.
- It counts from that Tomo's logs in `TomoStore`: `answer` (every try), `growth` (level-ups and
  birthdays) and `visit` (below), only since the Tomo hatched. Start over begins the stats again; the logs
  stay. A testing Tomo has no logs.
- The logs stay on each device until they sync ([#62](https://github.com/serpcompany/tomodachi-app/issues/62),
  Francis's), so stats show what happened on this device. A level reached on the other device shows as the
  level now.

## What counts

- **Answers:** right and wrong tries; help requests and the wrong language aren't answers. **Wins:** right
  answers that counted. **Practice:** right answers that didn't. **Misses:** wrong tries. **New words:**
  words met for the first time. **Words that got stronger:** words met before that moved up a stage.
- **Days:** a day starts at 4 am, like the daily new words, so an answer at 1 am belongs to the day before;
  Tomo's week starts on Monday at 4 am. **The streak** is days in a row with at least one answer; before
  today's first answer it's still yesterday's, and a day with none breaks it once that day is over.
  **Missed days** are days with no answer since the stats began.
- Streaks, misses and missed days are data, and screens may show them (decisions.md, 2026-10-11). The one
  rule: never a growing count of things to review or do ([concepts.md](concepts.md)). Ignored visits are
  counted (`ignoredVisits`) but left off the Today line and the postcards for now: a choice, since Tomo's
  mood will show them.

## The visit log

`TomoGame` records each time Tomo and the learner are together: a visit (as the card or a peek, and when
its card opened) or the learner opening Tomo, and how it ended (finished, ignored, closed, or rested when
nothing counted). A time together that spans the app being suspended ends then. It's there for the mood
ladder's "ignored in a row" ([#130](https://github.com/serpcompany/tomodachi-app/issues/130)) and the diary.

## The Together screen

One page, on the Mac's sidebar and as an iPhone tab: the Today line, the word garden, then Tomo's week.
The garden is the stats screen and the postcard is its share moment, so they share a page rather than
take a tab each; on the Monday a postcard comes, it moves to the top.

## The word garden

- Every word met is a plant (`TomoStats.garden`), planted at its first right answer and grown to its stage:
  a sprout while Tomo has just heard it, leaves once it knows it, a bud when it's good at it, a flower when
  it loves it, a gold star for forever. A word that slipped turns pale until it's answered right again; no
  plant ever wilts. Words not met yet aren't planted, so nothing there waits to be done.
- The first words are at the back, the newest at the front, and Tomo strolls along the front.
- **Today, this week or since we met:** in the range, words met or grown glow and words practiced are
  watered; the summary says how many sprouted, grew, were watered and missed. Since we met, it says how
  many words are planted.
- **Tap a plant** for its word: the picture, the word, its reading and meaning, its stage, when it was met.
- **The replay** grows the garden again from the first day, from this device's log (a word met on another
  device shows at its stage now); the slider picks a day.
- **Copy recap** puts the range's recap on the clipboard (the shell's pasteboard: TomoCore has none).
  **Export my log** saves the learner's own log as Markdown (tables of weeks, words and answers) or JSON
  (every answer, level-up, birthday and visit as stored, and the words now), from `TomoStats`.
- Under Reduce Motion nothing sways or falls and Tomo stays at the side, still breathing; watered words
  get a still drop.

## Today and Tomo's week

- **The Today line** ("12 answers · 3 new words · 5 days in a row · Lv 61 → 62") is on the Tomo and
  Together screens. Before the first answer it's "Nothing yet today", with the streak that's waiting on
  today ("· 4 days in a row"). A streak shows from two days.
- **Tomo's week:** every Monday morning Tomo sends a postcard of the week before. The front has the
  week's picture word (the one answered most), Tomo reacting to the week, a stamp with its level and a
  postmark; the back has Tomo's message in its own words (that word and two more, やったー for a level-up,
  またね) and what you did: new words, wins, practice, misses, words that got stronger, the week's longest
  run of days in a row, the level, days together. Nothing that's zero is listed.
  It turns over with a tap and shares as a picture of both sides (#29), with the same recap as text.
- **A quiet week** still gets a postcard, kept light: Tomo sleeps on the front ("Zz… またね！"), and the
  back has its level and days together.
- **A brand-new Tomo** gets a first postcard before its first Monday: Tomo says hello and when the first
  one comes.
- On the Monday it comes, the Tomo screen says so. No notification and no badge.
- Tomo's words come from the target pack (`postcard`, `lines.hello`), the rest from `ui.<id>.json`.

## Checking it

The self-test plays a simulated learner for three weeks on a stopped clock and checks today, every week,
the misses, the streak (across the 4 am boundary, broken by a quiet week, waiting on today), missed days,
the garden (every word met at its stage, and the replay's stage of every word at the end of every day),
the ranges, the recap, both exports (the JSON reads back; the Markdown has a row for everything), the Today
line and the postcards against its own tally (`TomoStatsCheck.swift`), plus the visit log on the game
(`TomoVisitCheck.swift`). Snapshots: `TOMO_OPEN_WINDOW=together` with a `seed-progress.py --history`
folder ([verification.md](verification.md)).
