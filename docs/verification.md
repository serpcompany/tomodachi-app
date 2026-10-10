# Verifying changes

How to check a change to the demo app, and what evidence each kind of change needs. Tomo lives in the
notch and test runs stay invisible, so computer-use can't drive it; debug environment variables do instead. There's no
macOS CI yet: CI runs only the repo checks, so the build, the self-test and the snapshots run locally.

## Levels

| Level | What to run | When |
|---|---|---|
| **Inner loop** | The incremental build (`xcodebuild … build` in [AGENTS.md](../AGENTS.md); `xcodegen` first only when files were added or removed). For growth rules, the self-test | While editing |
| **Push** | `node .github/scripts/check-docs.mjs` and `node .github/scripts/check-swift-text.mjs` (CI runs both, plus the link check) | Before each push |
| **Finish gate** | Build, self-test, repo checks, and the evidence below | Once, when the branch is done |

The self-test: `TOMO_SELFTEST=1 TOMO_DATA_DIR=$(mktemp -d) <app binary>` checks the word-stage, level,
store, sync-merge and look rules, the island's (which screen, where, Esc, opening and closing, the peek; a visit offered as a peek runs on the game itself, about 3 s, and logs as one), the stats (a learner simulated for three weeks, against its own tally: `TomoStatsCheck.swift`), who sees the first run, when reminders
come, and that every moment has a short, soft sound, lower for an older Tomo; it prints each
check and quits (exit code 1 on a failure). A new growth rule gets a new check in `TomoProgress.selfTest`, a new
merge rule one in `TomoSync.selfTest`, an island rule one in `TomoIslandSelfTest`. It also checks growth end to end
(`TomoGrowthCheck.swift`, about 20 s): every level of every pack can be finished (enough words a round can ask,
each item in one level, ages never going down, talking on the first 3さい level, the last level holding), and a
perfect and a realistic learner, simulated on a stopped clock with the real rules, grow from the first word to the
first talking question with nothing going backwards, every level-up and birthday logged and each birthday on the
pack's age boundary. Each run prints a `pace` line: the days to Lv 2, 5 and 10 and to each birthday.

## Evidence a change needs

- **The card, the header or anything else on the island:** the snapshot matrix. Look at every image:
  picture and talking stages; English and Japanese interface; a short and a long Tomo line; the hint
  (talking); Win, Practice, Miss and No score; resting and a level-up; and any new state the change adds. A change
  to how a visit starts or opens needs them with the peek on too (`TOMO_PEEK=1 TOMO_PEEK_OPEN=2`).
- **Growth rules:** the self-test, with a check for the new rule.
- **The screens (Tomo, Words, Together, Settings, About):** on the Mac, the window's snapshots with seeded progress
  (`TOMO_OPEN_WINDOW=tour`, below), in English and Japanese; on the iPhone, a simctl screenshot of each
  (`SIMCTL_CHILD_TOMO_OPEN_WINDOW=<screen>`), on a regular and an SE-size simulator. Stats need a seed with logs
  (`--history`, below): both sides of the postcard (`TOMO_POSTCARD_TURN`), a quiet week, a brand-new Tomo (no seed),
  and Monday (`TOMO_TIME_TRAVEL` to Monday morning) on the Tomo screen.
- **The menus and their shortcuts:** `TOMO_DUMP_MENU=<file>` writes the main menu and the menu bar icon's
  menu, with their shortcuts; a headless run can't press them.
- **Tomo's look or motion:** `TOMO_RENDER_SHEET` and `TOMO_RENDER_ANIM` frames, with `TOMO_SEED=<text>` for
  a known learner's Tomo (the mascot otherwise), and the self-test's look checks (`TomoLook.selfTest`). They draw the
  learner's material (jelly); `TOMO_MATERIAL=classic` draws Tomo as before. A change to `classic` or to anything it
  draws needs `TOMO_RENDER_CARD_FRAMES` compared with main: those frames ship as the widgets' font.
- **Sounds:** `TOMO_RENDER_SOUNDS`, and listen. An agent can't listen: check each file with ffmpeg (`astats` or
  `volumedetect`: peaks at -3 dBFS or lower; `ebur128`: about the same loudness at every age) and look at a
  `showspectrumpic` sheet.
- **Sync:** the self-test, and `TOMO_SYNC_CHECK` runs for the case it changes (below).
- **The first run:** its window's snapshots at every step (`TOMO_ONBOARDING=1 TOMO_AUTOPLAY=1`), in English
  and Japanese, and `TOMO_ONBOARDING=welcomeBack`. On the iPhone, `simctl io` screenshots of every step on a
  regular iPhone and an iPhone SE, in both languages ([ios-demo/README.md](../ios-demo/README.md)).
- **Reminders:** the self-test (`TomoReminders.selfTest`), and the pending ones on a simulator
  (`TOMO_REMINDERS_LOG=1`), checked against quiet hours.
- **Esc, the keyboard, changing displays:** a headless run can't press keys or plug in a monitor. Put the rule
  in a pure function with a check in `TomoIslandSelfTest`, and say in the PR what wasn't tried by hand.

## Testing tools in the app

The Testing menu, the window's Testing and AI pages and the "I'm learning" picker are hidden from learners. The AI
page exists in Debug builds only.
**⌥-click the menu bar icon** to show them for the rest of that run, or show them always with
`defaults write com.zenbujapanese.tomo tomoTestingTools -bool true` (`defaults delete` to hide them again).
They work in every build, Developer ID included (`TomoTestingTools`). The Testing menu is in the main menu while
Tomodachi is the active app, and in the menu bar icon's menu: **Skip to talking (3さい)** (⌘3), **Grow one
step** (⌘G), **Finish this level** (⌘L) and **Grow to the next birthday** (⌘B), which grow Tomo without waiting
and celebrate as usual (`TomoGame.testGrow`); `TOMO_GROW=step|level|birthday` does the same 3 s after launch,
for snapshots. Testing never touches the saved Tomo: another age, "Skip ahead a day" and Grow run on a copy in
memory until **Back to my Tomo** (in the menu too), which also puts Tomo's clock back.

## Sync (iCloud)

Debug builds sync in CloudKit's Development environment, never with a learner's real Tomo, and a test
run (`TOMO_DATA_DIR`) syncs only with `TOMO_SYNC=1`. `TOMO_SYNC_CHECK=<step>` with both syncs that
folder and quits: `play:N` answers N new words, `blind:N` does too without fetching first (its saves
conflict), `reset` starts over, `show` only fetches; each prints the Tomo. Folders act as devices, but
CloudKit doesn't send a device its own changes: a folder sees the others' only on its first fetch, so
look with a new folder each time. Changes arriving later, and pushes, need a second device: the iPhone
simulator signed in to iCloud, or the owner's phone on TestFlight (Production).

Production gets new record types and fields (today `Tomo` and `Item`) only when they're deployed, after a
Development run created them. The owner does it: in CloudKit Console, open the container with the
Development environment selected, then click Deploy Schema Changes, which copies Development's schema to
Production. Until then Production saves fail and are retried, and the app marks the `cloud-resend` file in
its data folder again every 5 minutes. When saves go through, the marking stops. The `cloud` table in
`learner.sqlite` has a row for each record iCloud has accepted (read it with `sqlite3 -readonly`).

## Keep the owner's Tomo safe

- Progress is saved, so **every test run gets `TOMO_DATA_DIR=<a temp dir>`**. Without it, the run changes
  the owner's own Tomo.
- **Every test run gets `TOMO_HEADLESS=1`** too, so it never shows on the owner's screen: each window stays
  transparent and click-through, none takes the keyboard (the owner's typing would land in it), the app
  never activates and stays out of the Dock, the menu bar icon is hidden and Tomo is silent, without
  touching the saved sound setting. Snapshots still work: they draw the views, not the screen (`TomoHeadless.swift`).
- Debug builds share the owner's bundle ID and preferences ([#54](https://github.com/serpcompany/tomodachi-app/issues/54)).
  Launch test runs by their binary path and never `pkill` by name: that quits the owner's copy, and other
  agents' runs. If one was quit, relaunch it with `mac-demo/run.sh`.
- iPhone: boot the simulator with `xcrun simctl boot` and capture with `simctl io … screenshot`; never
  open Simulator.app, which puts a window on the owner's screen.
- The owner may be watching or clicking the live app. A click shows up in snapshots as an unexpected
  answer or restart.

## Driving the app

Set these in the app's environment (run the binary in `Tomodachi.app/Contents/MacOS/` directly):

- `TOMO_HEADLESS=1`: nothing shows, sounds or takes focus (above). Use it on every test run.
- `TOMO_SNAPSHOT_DIR=<dir>`: a PNG of the island every second, and of the Tomodachi window while it's open
  (`window-<screen>-NNN.png`, and `window-sheet-NNN.png` for the start-over question), and the picture Together
  shares (`postcard-share-<day>.png`). `TOMO_SNAPSHOT_EVERY=<seconds>` takes them more often (0.1, to catch a motion
  midway). `TOMO_APPEARANCE=light|dark` draws the window in either. In a headless run the card's first frame takes about 0.4 s
  to draw, so a motion as it opens shows in one or two frames.
- `TOMO_RESTING_HOVER=1`: the resting island as it is under the pointer (a little bigger), which a headless run can't
  move there.
- `TOMO_PEEK=1` (or `0`): visits peek first (or open the card), whatever Settings says. `TOMO_PEEK_OPEN=<seconds>`:
  that long after a peek shows, it opens as a click on it would (without taking the keyboard), so a test run sees its
  word slide into the card. A headless run can't point at it.
- `TOMO_OPEN_WINDOW=<screen>` (tomo, words, together, settings, about, ai, testing): the Tomodachi window opens at that
  screen a second after launch (`ai` and `testing` also show the testing tools). `startOver` opens Settings
  asking to start over; `tour` shows every screen for 3 s each, then the question. On the iPhone it picks the
  tab. `TOMO_OPEN_SETTINGS` is its old name. Seed a mid-level Tomo first (below), so the screens have content.
- `TOMO_POSTCARD=<n>`: Together shows the postcard n weeks before the newest. `TOMO_POSTCARD_TURN=<seconds>`: that
  long after it shows, it turns over.
- `TOMO_AUTOPLAY=1`: answers picture rounds by itself (one miss, then right) and picks Practice when Tomo rests.
  `TOMO_AUTOPLAY=right` answers every round right the first time, so the answer counts in full: a level-up on cue
  from a `seed-progress.py --edge` folder.
- `TOMO_AUTOREOPEN=<seconds>`: that long after Tomo first tucks back in, it opens once, the way a click on
  small Tomo does (free play), to see what the learner gets then (the resting card, or what counts now).
- `TOMO_STAGE=3 TOMO_AUTOCHAT="しごと してる|うん"`: a testing Tomo at that age, typing those answers. Testing
  ages run in memory; saved progress isn't touched.
- `TOMO_TARGET=es`, `TOMO_LEARNER=ja`: the language pair.
- `TOMO_TIME_TRAVEL=<hours>`: Tomo's clock starts that far ahead, so due words come back. Answers given
  while ahead are saved with those dates, so only in a test run's `TOMO_DATA_DIR`. The window's Testing
  page → "Skip ahead a day" moves the clock live, on a copy of Tomo in memory.
- `TOMO_DROPIN_EVERY=8`, `TOMO_NUDGE_EVERY=5`: seconds between visits and between nudge bounces.
- `TOMO_RENDER_ICON`, `TOMO_RENDER_SHEET`, `TOMO_RENDER_SOUNDS`, `TOMO_RENDER_ANIM`, `TOMO_RENDER_CARD_FRAMES` (`=<dir>`): render
  the icons, every age and face, every sound (WAV), or a 32-second scene (20 fps frames, with the hello at 25.2 s and
  small Tomo's badges from 27.6 s, drawn as the resting island draws them, 3 times as big), then quit. The
  sheet shows one Tomo at every age and with every face, then a crowd of other seeds. The sounds are
  `<effect>-age<N>.wav` for 1さい to 6さい, and `all-sounds.wav` (every effect at 1さい, in order).
- `TOMO_SEED=<text>`: the seed Tomo's look is made from, in place of the saved Tomo's.
- `TOMO_MATERIAL=classic|jelly`: the material of `TOMO_RENDER_ANIM` and the sheets (the learner's own, jelly, otherwise).
  The icons and the card frames are always classic.
- `TOMO_HELLO=<seconds>`: that long after Tomo first shows, it says hello as it does when the Mac wakes (a test run
  can't sleep the Mac). The hello at launch needs no flag: the launch visit's card shows it.
- `TOMO_BADGE=checking|dozing`: small Tomo wears that badge in the resting island. `checking` holds Tomo in its
  thinking state (nothing makes it check an answer while small today: answers are choices); `dozing` lets it doze 2 s
  after the pointer stops instead of 45 s (the real doze needs the owner's pointer to stay still).
- `TOMO_REDUCE_MOTION=1`: Tomo honours Reduce Motion whatever the system says, in snapshots, `TOMO_RENDER_ANIM` and
  the sheet (on the iPhone, `SIMCTL_CHILD_TOMO_REDUCE_MOTION=1`). Without it a test run (`TOMO_HEADLESS`) ignores this
  Mac's setting, and the renders always do, so none depends on the Mac it runs on. `TOMO_RENDER_CARD_FRAMES` ignores
  the flag too: its frames are the shipped font.
- `TOMO_NO_NOTCH=1`: the island a Mac without a notch gets (the 80 × 24 strip, 240 × 24 resting), on any screen.
  Snapshots of the resting island need both. A test run at night has no visits (quiet hours); `TZ=<a daytime zone>`
  gives it one.
- `TOMO_ONBOARDING=1`: the first run, if the data folder has no Tomo (test runs skip it otherwise). A step
  name opens it there: `hatch`, `round`, `result`, `visits`, `rhythm`, `quiet`, `login`, `ready`, or
  `welcomeBack` (the iPhone has `notify`, `widget` and `lockScreen` in place of `login`). `preview` opens the
  Testing menu's preview of it on a copy of the data folder's Tomo, which is never changed (seed one first,
  below). A test run never changes the login item: it logs what it would have done. With
  `TOMO_AUTOPLAY=1` it plays itself through; `TOMO_SNAPSHOT_DIR` captures its window (`onboarding-NNN.png`).
- `TOMO_RENDER_VARIETY=<dir>`: the same eight Tomos at several `TomoLook.variety` settings, to judge how
  different Tomos should be.
- `TOMO_RENDER_EVOLUTION=<dir>`: eight Tomos at every age, one per row, to judge how they evolve.

## Starting from a known state

`mac-demo/scripts/seed-progress.py <dir>` writes saved progress for a run: a level, an age, and items at
chosen stages and due times (and best stages, for a slip), for any language pair. For example, all of
level 1 just learned, so nothing counts and Tomo rests:

```bash
python3 mac-demo/scripts/seed-progress.py /tmp/tomo-test --through-level 1 --stage 1 --due 2
```

`--edge N` is one word short of finishing level N (the word due now), with Tomo at that level's age: with
`TOMO_AUTOPLAY=right`, the first answer levels up, so `--edge 15` shows the 2さい birthday and `--edge 60` the
3さい one and the first talking question. `--history` adds the logs of a learner who played since Tomo hatched
(`--days`), so Together has weeks and postcards; `--quiet A-B` leaves days A to B ago quiet. Its docstring has the
options. Snapshots of the real data are a copy away:
`sqlite3 -readonly "<Application Support>/com.zenbujapanese.tomo/learner.sqlite" ".backup '<dir>/learner.sqlite'"`.

## Known flake

After a force-quit, the launch visit sometimes doesn't open: the snapshots show small Tomo resting beside the
notch. Run it again.
