# Debug flags

How to drive the Mac app in a test run: the environment flags, and saved progress to start from. Which evidence a change
needs, and the rules that keep the owner's Tomo safe (every run headless, with its own data folder), are in
[verification.md](verification.md). The iPhone's own flags and simulator rules are in
[ios-demo/debug-flags.md](../ios-demo/debug-flags.md).

## Driving the app

Set these in the app's environment (run the binary in `Tomodachi.app/Contents/MacOS/` directly):

- `TOMO_HEADLESS=1`: nothing shows, sounds or takes focus ([verification.md](verification.md), "Keep the owner's Tomo
  safe"). Use it on every test run.
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
- `TOMO_PILLAR=levels|ages`: the Tomo screen's height pillar at that scale (on the iPhone, the screen scrolls to it).
  `TOMO_PILLAR_BACK=<0…1>` slides back in time that share of the way; `TOMO_PILLAR_MARK=<level>` selects a mark (a
  negative level: the next birthday). On the Mac, `TOMO_WINDOW_HEIGHT=<points>` makes the Tomodachi window that tall,
  to see a long page (a test run's window is never on screen).
- `TOMO_GARDEN=today|week|all`: the garden's range. `TOMO_GARDEN_REPLAY=<seconds>`: that long after it shows, the
  replay starts. `TOMO_GARDEN_WORD=newest`: the newest word's card shows. With `TOMO_SNAPSHOT_DIR`, Together also
  writes its exports and recaps there (`export.md`, `export.json`, `recap-<range>.txt`).
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
  the icons, every age and face, every sound (WAV), or a 36-second scene (20 fps frames, with the hello at 25.2 s,
  small Tomo's badges from 27.6 s, drawn as the resting island draws them, 3 times as big, and the card's weather:
  snow from 32 s, petals from 34 s), then quit. The
  sheet shows one Tomo at every age and with every face, then a crowd of other seeds. The sounds are
  `<effect>-age<N>.wav` for 1さい to 6さい, and `all-sounds.wav` (every effect at 1さい, in order).
- `TOMO_SEED=<text>`: the seed Tomo's look is made from, in place of the saved Tomo's.
- `TOMO_SHORTCUT=<saved JSON>`: the shortcut to play, whatever Settings says, without saving it (a test run never
  registers a hot key). `TOMO_SHORTCUT_PRESS=<seconds,…>`: the shortcut pressed at those times after launch.
- `TOMO_SCROLL_PROBE=1`: logs every scroll over the island to stderr, and which window got it, to check whether
  swipes reach the panel without it taking the keyboard (#130). By hand only: a headless run can't swipe.
- `TOMO_SCREEN=<notch|main|mouse|display:name>`: which screen Tomo lives on, whatever Settings says, without saving it.
  A headless run has only this Mac's screens, so the choices between screens are checked in `TomoIslandSelfTest`.
- `TOMO_MATERIAL=classic|jelly`: the material of `TOMO_RENDER_ANIM` and the sheets (the learner's own, jelly, otherwise).
  The icons and the card frames are always classic.
- `TOMO_HELLO=<seconds>`: that long after Tomo first shows, it says hello as it does when the Mac wakes (a test run
  can't sleep the Mac). The hello at launch needs no flag: the launch visit's card shows it.
- `TOMO_DATE=YYYY-MM-DD`: the day the language's calendar reads (its seasons' weather in the card), whatever today is;
  Tomo's clock and progress don't move. For example `2026-04-02` for 桜 petals, `2027-01-01` for snow.
- `TOMO_BADGE=checking|dozing`: small Tomo wears that badge in the resting island. `checking` holds Tomo in its
  thinking state (nothing makes it check an answer while small today: answers are choices); `dozing` lets it doze 2 s
  after the pointer stops instead of 45 s (the real doze needs the owner's pointer to stay still).
- `TOMO_REDUCE_MOTION=1`: Tomo honours Reduce Motion whatever the system says, in snapshots, `TOMO_RENDER_ANIM` and
  the sheet (on the iPhone, `SIMCTL_CHILD_TOMO_REDUCE_MOTION=1`). Without it a test run (`TOMO_HEADLESS`) ignores this
  Mac's setting, and the renders always do, so none depends on the Mac it runs on. `TOMO_RENDER_CARD_FRAMES` ignores
  the flag too: its frames are the shipped font.
- `TOMO_NO_NOTCH=1`: the island a Mac without a notch gets (a 300 × 30 capsule 4 pt below the top, never hidden), on
  any screen.
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
(`--days`), with each word reviewed when its wait is up (now and then a miss sets it back), and leaves the words at
the stages that history gives them, so Together has weeks, postcards and a garden; `--quiet A-B` leaves days A to B
ago quiet. A longer one (`--through-level 30 --days 150`) grows flowers. Its docstring has the
options. Snapshots of the real data are a copy away:
`sqlite3 -readonly "<Application Support>/com.zenbujapanese.tomo/learner.sqlite" ".backup '<dir>/learner.sqlite'"`.
