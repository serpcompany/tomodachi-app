# Verifying changes

How to check a change to the demo app, and what evidence each kind of change needs. Tomo lives in the
notch and test runs stay invisible, so computer-use can't drive it; debug environment variables do instead
([debug-flags.md](debug-flags.md), with seeded progress). Automated tests run without a human (below): TomoCore's
tests, and the iPhone's UI journeys on a simulator. macOS CI runs them, and builds both apps, once a PR is ready for
review; the Mac's island checks and the snapshots run locally.

## Levels

| Level | What to run | When |
|---|---|---|
| **Inner loop** | The incremental build (`xcodebuild … build` in [AGENTS.md](../AGENTS.md); `xcodegen` first only when files were added or removed). For rules, `swift test --filter <TestClass>` in `TomoCore`; for the island's, `TOMO_SELFTEST=1` with a temp `TOMO_DATA_DIR` (below) | While editing |
| **Push** | `cd TomoCore && swift test` (about 30 s), `node .github/scripts/check-docs.mjs` and `node .github/scripts/check-swift-text.mjs` | Before each push |
| **Finish gate** | `scripts/finish-gate.sh` (build, `scripts/check-privacy-manifests.sh` on it, `swift test`, self-test, repo checks; it stops non-zero at the first failure; CI checks both apps' manifests too), the UI journeys a change touches, and the evidence below. CI on the final commit runs the Pull Request plan; without it, run that plan once locally | Once, when the branch is done |

- **After a merge:** CI doesn't run `TOMO_SELFTEST` or the snapshots, so the agent that merges runs
  the self-test on main right after merging, unless main's tree is the one it already ran on
  (`git rev-parse HEAD^{tree}`). A failure there is the next task.
- **Xcode:** build with the version pinned in `.xcode-version`, which CI reads. With several
  installed, choose it through `DEVELOPER_DIR`, for example
  `DEVELOPER_DIR=/Applications/Xcode-27.0.app/Contents/Developer`. When the pinned version isn't
  installed, say so in the PR and treat CI's compile as the one that counts.

The self-test: `TOMO_SELFTEST=1 TOMO_DATA_DIR=$(mktemp -d) <app binary>` checks the word-stage, level,
store, sync-merge and look rules, the island's (which screen, where, Esc, opening and closing, the peek; a visit offered as a peek runs on the game itself, about 3 s, and logs as one), the stats (a learner simulated for three weeks, against its own tally: `TomoStatsCheck.swift`), who sees the first run, when reminders
come, and that every moment has a short, soft sound, lower for an older Tomo; it prints each
check and quits (exit code 1 on a failure). A new growth rule gets a new check in `TomoProgress.rulesSelfTest`, a new
merge rule one in `TomoSync.selfTest`, an island rule one in `TomoIslandSelfTest`. It also checks growth end to end
(`TomoGrowthCheck.swift`, about 20 s): every level of every pack can be finished (enough words a round can ask,
each item in one level, ages never going down, talking on the first 3さい level, the last level holding), and a
perfect and a realistic learner, simulated on a stopped clock with the real rules, grow from the first word to the
first talking question with nothing going backwards, every level-up and birthday logged and each birthday on the
pack's age boundary. Each run prints a `pace` line: the days to Lv 2, 5 and 10 and to each birthday.

## Automated tests

- **TomoCore's tests** (`TomoCore/Tests/TomoCoreTests`, `cd TomoCore && swift test`, about 30 s): every rule
  check as XCTest. Word stages, levels and the store; the stats against a simulated learner; every pack and the
  simulated learners; Tomo's drawing, look and the calendar; sync merges; the first run; reminders and the
  iPhone's one Lock Screen card; sounds; the moment's light; a visit that peeks first; the iPhone's Tomo and Words at
  the largest text on an SE (every word fits its row, every phrase of the Tomo screen its line: `TomoLargeTextCheck`). Each check is a function that reports to a `check` closure
  (`TomoCheck.swift`): the tests fail with the check's own words, and `TOMO_SELFTEST=1` prints the same checks
  plus the Mac's island rules (`TomoIslandSelfTest`, in the app). A new rule gets its check beside the others and
  runs in both. The tests set `TOMO_DATA_DIR` to a fresh temporary folder before anything opens a store. A check
  never rests on chance: random draws it looks at come from a seed (Tomo's particles: `TomoBlob.dice`, #203).
- **The iPhone's UI journeys** (`ios-demo/Tomodachi/UITests`, XCUITest): launch, a picture round answered wrong
  then right, the practice offer, Together (and, at the largest text, nothing on it wider than the phone and its range
  menu whole), Words at Tomo's level (opened, tapped from Play, and keeping your place when you come back), a long press
  on Tomo showing its love, and the build's own identity checks (`TOMO_SELFTEST=1` in the app). Each launches on a fresh
  folder in the test runner's temporary folder, silent, in English, without the first run, and starts once the app shows its tab with those settings (`launch` launches it again, once, and
  records why); progress a journey needs is written there through TomoCore's own store (`TomoSeed`), and the text
  they look for comes from `ui.en.json`. A journey waits on what the screen shows, and a state that shows for a
  moment must outlast XCUITest's own waits, which take seconds on a busy simulator (Tomo's love stays its VoiceOver
  value for 6 s, #203). A journey retries only what slowness explains, and records each retry.
- **Test plans** (`ios-demo/Tomodachi/TestPlans`): **Unit** is TomoCore's tests on the simulator; **Pull Request**
  adds the UI journeys. Run them on your own simulator (`ios-demo/scripts/simulator.sh delete` after; never
  Simulator.app):

  ```bash
  udid=$(ios-demo/scripts/simulator.sh udid)
  cd ios-demo/Tomodachi && xcodebuild test -scheme Tomodachi -testPlan PullRequest \
    -destination "platform=iOS Simulator,id=$udid" -derivedDataPath ../build
  ```

  One journey: `-only-testing:TomodachiUITests/TomodachiUITests/testThePracticeOffer`. Unsigned, as CI builds:
  add `CODE_SIGNING_ALLOWED=NO TOMO_ICLOUD_ENV=` (no iCloud: CloudKit stops an app without the entitlement).
- **CI** (`.github/workflows/apple.yml`, GitHub's `xcode-27` runners, Xcode pinned in `.xcode-version`): `swift test`,
  the Mac and iPhone apps built unsigned, and the Pull Request plan on a simulator of its own. Draft PRs skip it, and a
  change to docs alone (`**/*.md`, `docs/**`) skips its steps; a PR's passing UI run leaves a receipt, so main doesn't
  run the same tree again. No secrets.

What only a person (or an agent driving the owner's screen) can check, with each check's setup, steps and what
passes: [hand-checks.md](hand-checks.md).

## Evidence a change needs

- **The card, the header or anything else on the island:** the snapshot matrix. Look at every image:
  picture and talking stages; English and Japanese interface; a short and a long Tomo line; the hint
  (talking); Win, Practice, Miss and No score; resting and a level-up; and any new state the change adds. A change
  to how a visit starts or opens needs them with the peek on too (`TOMO_PEEK=1 TOMO_PEEK_OPEN=2`).
- **Growth rules:** the self-test, with a check for the new rule.
- **The screens (Tomo, Words, Together, Settings, About):** on the Mac, the window's snapshots with seeded progress
  (`TOMO_OPEN_WINDOW=tour`, [debug-flags.md](debug-flags.md)), in English and Japanese; on the iPhone, a simctl screenshot of each
  (`SIMCTL_CHILD_TOMO_OPEN_WINDOW=<screen>`), on a regular and an SE-size simulator. Stats need a seed with logs
  (`--history`): both sides of the postcard (`TOMO_POSTCARD_TURN`), a quiet week, a brand-new Tomo (no seed),
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
`defaults write com.zenbujapanese.tomo tomoTestingTools -bool true` (`com.zenbujapanese.tomo.debug` for a Debug build;
`defaults delete` to hide them again).
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

- Progress is saved, so **every test run gets `TOMO_DATA_DIR=<a temp dir>`**. Without it, a Debug run uses
  the Debug app's own folder, which every agent's runs share, and syncs it; a Release build changes the owner's Tomo.
- **Every test run gets `TOMO_HEADLESS=1`** too, so it never shows on the owner's screen: each window stays
  transparent and click-through, none takes the keyboard (the owner's typing would land in it), the app
  never activates and stays out of the Dock, the menu bar icon is hidden and Tomo is silent, without
  touching the saved sound setting. Snapshots still work: they draw the views, not the screen (`TomoHeadless.swift`).
- Debug builds are their own app, `com.zenbujapanese.tomo.debug` ("Tomodachi Debug"), with their own
  preferences, data folder, keychain items and, on the iPhone, App Group, and they never open at login
  ([#54](https://github.com/serpcompany/tomodachi-app/issues/54)). `TomoIdentity` checks it in the Mac's self-test and,
  on the iPhone, in the app itself (`TOMO_SELFTEST=1`, run by the `testThisBuildIsItsOwnApp` journey, with the widgets'
  ID and App Group); `TomoLoginItem.selfTest` checks the login item. Only Release builds, the owner's copy among
  them, are `com.zenbujapanese.tomo`.
  Both share the process name: launch test runs by their binary path and never `pkill` by name, which quits
  the owner's copy and other agents' runs. If one was quit, relaunch it with `mac-demo/run.sh`.
- iPhone: use your own simulator, from `ios-demo/scripts/simulator.sh udid`, and name it by that UDID
  in every command (never `booted` or another's name): `xcrun simctl boot <udid>`, `simctl io <udid>
  screenshot`, then `simulator.sh delete` when the work is done. Never open Simulator.app, which puts a
  window on the owner's screen.
- The owner may be watching or clicking the live app. A click shows up in snapshots as an unexpected
  answer or restart.

## Known flake

After a force-quit, the launch visit sometimes doesn't open: the snapshots show small Tomo resting beside the
notch. Run it again.
