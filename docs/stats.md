# Stats: what you and Tomo did together

What the stats screens count, where the numbers come from, and the rules they keep. Stats are four
screens built in stages from [Stats, Take Two](reference/tomo/stats-take-two.html) ([#137](https://github.com/serpcompany/tomodachi-app/issues/137),
item 2): Tomo's week as a postcard first, then the word garden, a height pillar for growing up and Tomo's
diary, all on the same layer. The code: `TomoStats.swift` (the layer), `TomoStatsExport.swift` (the recap
and the export), `TomoGarden.swift` (the garden), `TomoPostcard.swift` and `TomoPostcardView.swift` (Tomo's
week), `TomoDiary.swift` and `TomoDiaryView.swift` (Tomo's diary), `TomoTogetherScreen.swift` (the Together
screen), `TomoHeightPillar.swift` (growing up, on the Tomo screen).

## One layer

- `TomoStats` takes the `TomoProgress` it describes, so another Tomo (a friend) has its own. Every
  screen and the Today line read it; no screen counts anything itself. The Together screen and the
  postcard also take the Tomo's look and material (the learner's own: `.own`, jelly), and so does the
  picture they share: it's made for this learner when they share it, so it shows their own Tomo.
- It counts from that Tomo's logs in `TomoStore`: `answer` (every try), `growth` (level-ups and
  birthdays) and `visit` (below), only since the Tomo hatched. Start over begins the stats again; the logs
  stay. A testing Tomo has no logs.
- The logs stay on each device until they sync (sync is Francis's; [store-and-sync.md](store-and-sync.md)), so
  stats show what happened on this device. A level reached on the other device shows as the
  level now.

## What counts

- **Answers:** right and wrong tries; help requests and the wrong language aren't answers. **Wins:** right
  answers that counted. **Practice:** right answers that didn't. **Misses:** wrong tries. **New words:**
  words met for the first time. **Words that got stronger:** words met before that moved up a stage.
- **Days:** a day starts at 4 am, like the daily new words, so an answer at 1 am belongs to the day before;
  Tomo's week starts on Monday at 4 am. **The streak** is days in a row with at least one answer; before
  today's first answer it's still yesterday's, and a day with none breaks it once that day is over.
  **Missed days** are days with no answer since the stats began. **Days together** ("Day 17 together") count
  those days from the one Tomo hatched, which is Day 1, on this device's time zone: one rule
  (`TomoStats.dayTogether`) for the Tomo screen, the diary's pages, the postcard, the pillar and the export, so
  the diary's page for today and the Tomo screen agree, and the count moves at 4 am ([#224](https://github.com/serpcompany/tomodachi-app/issues/224)).
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

One page, on the Mac's sidebar and as an iPhone tab: the Today line, the word garden, Tomo's week, then
Tomo's diary. The garden is the stats screen and the postcard is its share moment, so they share a page
rather than take a tab each; on the Monday a postcard comes, it moves to the top. The diary is last: it's
the long read, about the days you spent together.

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

## Tomo's diary

A page for every day you played (a day starts at 4 am), written by Tomo in its own words at its age, from
the target pack, the way the postcard's message is (`TomoStats.diary`):
- ばあ！ on the first day; the day's words (new picture words first); a sulk after days apart (まってた！
  もう！, at 3さい ずっと まってたんだよ！ さみしかった！); おおきく なった！ at a birthday, else a やったー
  per level grown; a groan on a hard day (5 misses or more, and a third of the answers); a cheer on a run
  of 3 days or more; and またね！. The pack's `diary` holds those lines by age.
- Under Tomo's words: the day's new words as stickers (tap one for its card), and what you did: new
  words, wins, practice, misses, words that got stronger, the run of days, the level, how often Tomo came by.
  Never a zero.
- A day without play has no page; in the list of pages, the days apart show as a dashed line. Tomo on the
  page is alive at that day's form: it leaps on a day it grew, and sulks before it cheers up after days apart.
- **Copy this page** puts the page's text on the clipboard. A brand-new Tomo's diary is a first page:
  ばあ！ and what the diary will be.
- On the Mac it's a book, the list of pages beside the page; on the iPhone, the page with arrows to the
  days before and after, and the list under it.

## Growing up: the height pillar

On the Tomo screen's Growing up, since it's about Tomo rather than what you did: the way a Japanese family
marks a child's height on a wooden pillar (柱のきず), Tomo gets a mark for every level it reaches
(`TomoStats.marks`, from the growth log), with the day, and a big one at the hatch and each birthday. Tomo
stands beside it at its age's form, bigger through each age.
- **Levels:** this age's marks, from its birthday up (the newest ones when there are many), and the next
  birthday dashed above them, with Tomo's next form asleep beside it. Slide back in time and Tomo shrinks to
  that day's size and form, and later marks fade. Tap a mark for its day and the words of that level you've
  met, each with its stage.
- **Every age:** a band per age, each birthday at its foot, Tomo's level in its age's band, and each age with
  what it brings (grown / now / later), the list the screen had before.
- A level reached on another device is on the pillar without a day. A brand-new Tomo's pillar has one mark,
  the day it hatched, and says what the marks will be.

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
the ranges, the recap, both exports (the JSON reads back; the Markdown has a row for everything), the
pillar's marks (each dated when the level was reached; the level on each mark's day), the diary (a page per
day played with that day's numbers, the days apart, the run of days, and Tomo's hello, sulk, cheers and
groan exactly when they're due), the Today line and the postcards against its own tally
(`TomoStatsCheck.swift`), and that the diary's page for today and the Tomo screen say the same "Day N together"
in English and Japanese: late in the day, just after midnight, on the nights the clocks go back and forward, and
after a flight to another time zone. `TomoVisitCheck.swift` checks the visit log on the game. The growth simulations
check each pillar's birthdays up to 3さい, and the diary's birthday lines (`TomoGrowthCheck.swift`). Snapshots: `TOMO_OPEN_WINDOW=together` with a `seed-progress.py --history`
folder ([debug-flags.md](debug-flags.md)).
