# Verifying changes

How to check a change to the demo app, and what evidence each kind of change needs. The app lives in the
menu bar and the notch, so computer-use can't drive it; debug environment variables do instead. There's no
macOS CI yet: CI runs only the repo checks, so the build, the self-test and the snapshots run locally.

## Levels

| Level | What to run | When |
|---|---|---|
| **Inner loop** | The incremental build (`xcodebuild … build` in [AGENTS.md](../AGENTS.md); `xcodegen` first only when files were added or removed). For growth rules, the self-test | While editing |
| **Push** | `node .github/scripts/check-docs.mjs` and `node .github/scripts/check-swift-text.mjs` (CI runs both, plus the link check) | Before each push |
| **Finish gate** | Build, self-test, repo checks, and the evidence below | Once, when the branch is done |

The self-test: `TOMO_SELFTEST=1 TOMO_DATA_DIR=$(mktemp -d) <app binary>` checks the word-stage, level and
store rules, prints each check and quits (exit code 1 on a failure). A new growth rule gets a new check
in `TomoProgress.selfTest`.

## Evidence a change needs

- **The card, the header or anything else on the island:** the snapshot matrix. Look at every image:
  picture and talking stages; English and Japanese interface; a short and a long Tomo line; the hint
  (talking); Win, Practice, Miss and No score; and any new state the change adds.
- **Growth rules:** the self-test, with a check for the new rule.
- **Settings:** a snapshot of the page (`TOMO_OPEN_SETTINGS=<page>`).
- **Tomo's look or motion:** `TOMO_RENDER_SHEET` and `TOMO_RENDER_ANIM` frames.
- **Sounds:** `TOMO_RENDER_SOUNDS`, and listen.

## Keep the owner's Tomo safe

- Progress is saved, so **every test run gets `TOMO_DATA_DIR=<a temp dir>`**. Without it, the run changes
  the owner's own Tomo.
- Mute test runs: `defaults write com.zenbujapanese.tomodachi soundEnabled -bool false`, and afterwards
  `defaults delete com.zenbujapanese.tomodachi soundEnabled`.
- Debug builds share the owner's bundle ID and preferences, so starting a test run quits their copy.
  Relaunch it with `mac-demo/run.sh` when you're done.
- The owner may be watching or clicking the live app. A click shows up in snapshots as an unexpected
  answer or restart.

## Driving the app

Set these in the app's environment (run the binary in `Tomodachi.app/Contents/MacOS/` directly):

- `TOMO_SNAPSHOT_DIR=<dir>`: a PNG of the island every second. With `TOMO_OPEN_SETTINGS=<page>` (tomo,
  words, general, ai, testing, about) it opens Settings at that page and captures it too.
- `TOMO_AUTOPLAY=1`: answers picture rounds by itself (one miss, then right) and accepts the practice offer.
- `TOMO_STAGE=3 TOMO_AUTOCHAT="しごと してる|うん"`: a testing Tomo at that age, typing those answers. Testing
  ages run in memory; saved progress isn't touched.
- `TOMO_TARGET=es`, `TOMO_LEARNER=ja`: the language pair.
- `TOMO_TIME_TRAVEL=<hours>`: Tomo's clock starts that far ahead, so due words come back. Answers given
  while ahead are saved with those dates. Settings → Testing → "Skip ahead a day" does the same live.
- `TOMO_DROPIN_EVERY=8`, `TOMO_NUDGE_EVERY=5`: seconds between visits and between nudge bounces.
- `TOMO_RENDER_ICON`, `TOMO_RENDER_SHEET`, `TOMO_RENDER_SOUNDS`, `TOMO_RENDER_ANIM`, `TOMO_RENDER_CARD_FRAMES` (`=<dir>`): render
  the icons, every age and face, every sound (WAV), or a 16-second scene (20 fps frames), then quit.

## Starting from a known state

`mac-demo/scripts/seed-progress.py <dir>` writes saved progress for a run: a level, an age, and items at
chosen stages and due times, for any language pair. For example, all of level 1 just learned, so nothing
counts and Tomo offers practice:

```bash
python3 mac-demo/scripts/seed-progress.py /tmp/tomo-test --through-level 1 --stage 1 --due 2
```

Its docstring has the options. Snapshots of the real data are a copy away:
`sqlite3 "<Application Support>/com.zenbujapanese.tomodachi/learner.sqlite" ".backup '<dir>/learner.sqlite'"`.

## Known flake

After a force-quit, the launch visit sometimes doesn't open: the snapshots show small Tomo with a red
dot. Run it again.
