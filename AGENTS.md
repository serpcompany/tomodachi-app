# AGENTS

**Tomodachi** (by Zenbu Japanese): a language-learning app whose character, **Tomo**, lives in the MacBook notch and speaks at its age level. Tomo comes to you through the day; what it teaches comes from a content source (the age track by default). Use "Tomodachi" for the app and "Tomo" for the character. Bundle ID: `com.zenbujapanese.tomodachi`.

Current goal: prove that each part works and map out clean extension points. Polish comes later.

## Where things are

| Need | Open |
|---|---|
| The pitch and the original idea notes (user-owned; don't rewrite) | [README.md](README.md) |
| What works today and the settled rules | [docs/concepts.md](docs/concepts.md) |
| Systems, their seams, and links to planned work (read before changing code) | [docs/architecture.md](docs/architecture.md) |
| Language pairs, packs, and adding a language | [docs/languages.md](docs/languages.md) |
| Plans, ideas and open questions (one issue each; labels `next`, `idea`, `researched`, `question`) | [GitHub issues](https://github.com/serpcompany/zenbujapanese-tomo-app/issues) |
| Decisions made, and why | [docs/decisions.md](docs/decisions.md) |
| Deep dives (levels, voices, data schema, age vocabulary, answer checking, AI cost) | [docs/research/](docs/research/) |
| The demo app: run, rebuild, debug flags, beta builds, icons, files changed from Coucou | [mac-demo/README.md](mac-demo/README.md) |
| What beta testers get told | [docs/beta-testing.md](docs/beta-testing.md) |
| Dictionary, Language Reference IDs, word splitter (Sudachi) | `../zenbujapanese-monorepo` (read-only from here) |

## Build and run

```bash
cd mac-demo/NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath ../build build
mac-demo/run.sh    # relaunches the app with AI keys from .env
```

## Verifying changes

The app is menu-bar only, so computer-use can't target it. Use the debug flags instead (details in [mac-demo/README.md](mac-demo/README.md)):

- `TOMO_SNAPSHOT_DIR=<dir>` saves a PNG of the island every second.
- `TOMO_AUTOPLAY=1`, `TOMO_STAGE=3` and `TOMO_AUTOCHAT="…|…"` drive it without clicks.
- `TOMO_RENDER_SHEET=<dir>` renders every age and face of the character to one PNG; `TOMO_RENDER_ANIM=<dir>` renders a scripted scene frame by frame, to check motion.
- Mute Tomo for test runs with `defaults write com.zenbujapanese.tomodachi soundEnabled -bool false`, and run `defaults delete com.zenbujapanese.tomodachi soundEnabled` afterwards.
- The user may be watching or clicking the live app. A click shows up in snapshots as unexpected answers or restarts.
- After testing, relaunch the user's copy with `mac-demo/run.sh`.

## Rules

- **Docs describe what's real:** what's built and what's decided. Plans, proposals, ideas and open questions go in GitHub issues, and docs link to them. Research write-ups stay in `docs/research/` as evidence for the issues.
- **Keep the docs current in the same change:**
  - a seam moved → `architecture.md`
  - a planned feature or idea moved → its GitHub issue (close it when it's built)
  - a decision was made → `decisions.md`
  - something new works → `concepts.md`
  - run/debug steps or Coucou files touched → `mac-demo/README.md`
- **Add Tomo code behind the seams** in `architecture.md` (`Tomo*.swift`), not inside Coucou files. If you must touch a Coucou file, add it to the table in `mac-demo/README.md`.
- **Secrets** live in `.env` (gitignored) or the Keychain. Never commit, print or log a key.
- **Never commit** `mac-demo/build/`.
- **Coucou's code is MIT; its assets are not.** The name, the Mochi character and the sounds are reserved (`mac-demo/LICENSE-ASSETS.md`). Don't ship them. Tomo is our own chick (`TomoCharacter.swift`) with its own synthesized sounds (`TomoSounds.swift`); keep it that way.
- **Tomo is always alive.** It's drawn and animated live in code: no static images or sprite sheets. Every new look, state or reaction needs motion, and Tomo must never sit frozen (idle life: breathing, blinks, gaze, fidgets).
- **Tomo's card is a fixed grid** (`TomoGrid` in `TomoView.swift`): Tomo's column plus fixed-height rows that add up to the card. Put new UI into a slot. Never let a row size itself. Text that can grow must be capped (line limits, or a font fitted the way it's drawn). Help content (hints, explanations, word cards) goes in the help panel the notch grows underneath the card, never squeezed into the card. Before handing over a UI change, snapshot the matrix and look at it: picture and talking stages, English and Japanese interface, a short and a long Tomo line, hint shown, Win / Miss / No score.
- **No language-specific text in Swift.** Tomo's words go in the target pack (`Resources/languages/<id>.json`); interface text goes in `ui.<id>.json`. See `docs/languages.md`.
- **Don't invest in the offline keyword matcher** (`TomoBrain.offlineReply`, the packs' `offlineReplies`). The Zenbu dictionary system replaces it.
