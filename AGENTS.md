# AGENTS

**Tomodachi** (by Zenbu Japanese) is a language-learning app whose character, **Tomo**, lives in the
MacBook notch, comes to you through the day, and speaks at its age level. What it teaches comes from a
content source (the age track by default). Use "Tomodachi" for the app and "Tomo" for the character.
Bundle ID: `com.zenbujapanese.tomodachi`.

Stage: explore
Agents may merge: yes

The current goal is to prove each part works and map out clean extension points; polish comes later.
This file is a map: read only what the task needs, then check claims against the code. The repo follows
the [SERP engineering standards](https://github.com/serpcompany/serp/tree/main/docs/engineering/standards)
(git workflow, verification cadence, agent harness).

## Where to look

- **What Tomodachi is:** [README.md](README.md) has the pitch and the original idea notes. The owner
  wrote it; don't rewrite it.
- **What works, and the rules we've settled on:** [docs/concepts.md](docs/concepts.md). Read it before
  changing anything a learner sees.
- **How the code fits together:** [docs/architecture.md](docs/architecture.md) covers the systems, the
  seam each one keeps, and their invariants. Read it before changing code.
- **Language pairs:** [docs/languages.md](docs/languages.md) covers the pack format, the generated word
  levels, and adding a language.
- **Why things are the way they are:** [docs/decisions.md](docs/decisions.md), newest first. Read it
  before reopening a settled question.
- **Checking a change:** [docs/verification.md](docs/verification.md) covers the debug flags, the snapshot
  matrix, the self-test and seeded progress. Read it before you build or test.
- **Running the demo app:** [mac-demo/README.md](mac-demo/README.md) covers running, rebuilding, beta
  builds and icons. The iPhone app ([#52](https://github.com/serpcompany/tomodachi-app/issues/52)):
  [ios-demo/README.md](ios-demo/README.md).
- **The Coucou fork:** [docs/coucou-fork.md](docs/coucou-fork.md) says what we may ship, which Coucou
  files we changed, and what's switched off.
- **Research:** [docs/research/README.md](docs/research/README.md) holds the evidence behind the issues
  (levels, the data schema, word lists, voices, learning modes, answer checking, AI cost).
- **Beta testers:** [docs/beta-testing.md](docs/beta-testing.md) is what testers are told. Update it when
  something they see changes.
- **Plans, ideas and open questions:**
  [GitHub issues](https://github.com/serpcompany/tomodachi-app/issues), one each, labeled
  `next`, `idea`, `researched` or `question`.
- **The dictionary, Language Reference IDs and the word splitter (Sudachi):**
  `../zenbujapanese-monorepo`, read-only from here.

## Build and check

```bash
cd mac-demo/NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath ../build -allowProvisioningUpdates build
mac-demo/scripts/release-beta.sh --owner && mac-demo/run.sh    # rebuilds and relaunches the owner's copy
cd TomoCore && swift build    # the shared package alone; the iPhone build is in ios-demo/README.md
node .github/scripts/check-docs.mjs && node .github/scripts/check-swift-text.mjs
```

- **Inner loop:** the incremental build (seconds). Run `xcodegen` only when files were added or removed.
  For growth rules, run `TOMO_SELFTEST=1` with `TOMO_DATA_DIR=<a temp dir>`.
- **Finish gate:** the build, the self-test, the repo checks, and the evidence the change needs. A UI
  change needs the snapshot matrix; see [docs/verification.md](docs/verification.md). There's no macOS
  CI yet, so CI runs only the repo checks and the link check.
- **Test runs never touch the owner's Tomo or screen:** always pass `TOMO_DATA_DIR=<a temp dir>` and
  `TOMO_HEADLESS=1` (invisible, silent, never takes the keyboard), never `pkill` by name, and never open
  Simulator.app (`xcrun simctl` runs headless).

## Rules

Checks in `.github/scripts/` enforce what they can. These rules need judgment:

- **Docs are maps.** Maps (`AGENTS.md`, `README.md`) point to things. Leaves cover one topic each: its
  purpose, invariants, boundaries and reasons. The code and its comments hold the detail. Update a doc
  when a boundary, an invariant, a term or a decision changes, not for every implementation change; the
  PR description holds the rest. Docs describe what's real, and plans go in issues that the docs link
  to. Sizes and names are checked: split a doc by topic rather than squeezing it.
- **Put Tomo's code behind the seams** in [docs/architecture.md](docs/architecture.md), in `Tomo*.swift`
  files, not inside Coucou files. Code that isn't Mac-only goes in the `TomoCore` package, so the iPhone
  app gets it too. If a change has to go into a Coucou file, add the file to
  [docs/coucou-fork.md](docs/coucou-fork.md).
- **Text lives in data.** Tomo's words go in the target pack (`TomoCore/Sources/TomoCore/Resources/languages/<id>.json`) and
  interface text in `ui.<id>.json` ([docs/languages.md](docs/languages.md)). A check fails on Japanese in
  Swift strings. English in Swift is just as wrong, but no check catches it.
- **Tomo is always alive.** It's drawn and animated live in code, with no static images or sprite sheets.
  Every new look, state or reaction needs motion, and Tomo never sits frozen.
- **Tomo's card is a fixed grid** (`TomoGrid` in `TomoView.swift`). New UI goes into a slot, no row sizes
  itself, and text that can grow is capped. Help content goes in the panel under the card, never in the
  card.
- **Coucou's assets are reserved:** its name, the Mochi character and its sounds. Never ship them.
- **Secrets** live in `.env` (gitignored) or the Keychain. Never commit, print or log a key.
- **Don't invest in the offline keyword matcher** (`TomoBrain.offlineReply` and the packs'
  `offlineReplies`). The Zenbu dictionary replaces it.
- **PR titles are the changelog.** Use Conventional Commits (`feat:`, `fix:`, `docs:`…) and describe the
  outcome a user notices.
