# AGENTS

Tomodachi: a Japanese-learning pet (Tomo) that lives in the MacBook notch and speaks at its age level. Part of Zenbu Japanese.

Current goal: prove that each part works and map out clean extension points. Polish comes later.

## Where things are

| Need | Open |
|---|---|
| The pitch and the original idea notes (user-owned; don't rewrite) | [README.md](README.md) |
| What works today and the settled rules | [docs/concepts.md](docs/concepts.md) |
| Systems, their seams, and what plugs in later (read before changing code) | [docs/architecture.md](docs/architecture.md) |
| Features and ideas, with their status | [docs/backlog.md](docs/backlog.md) |
| Decisions made, and why | [docs/decisions.md](docs/decisions.md) |
| User-journey feature ideas | [docs/user-journey.md](docs/user-journey.md) |
| Deep dives (levels, voices, data schema, age vocabulary, answer checking, AI cost) | [docs/research/](docs/research/) |
| The demo app: run, rebuild, debug flags, files changed from Coucou | [mac-demo/README.md](mac-demo/README.md) |
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
- Mute Tomo for test runs with `defaults write co.zenbu.TomodachiDemo soundEnabled -bool false`, and run `defaults delete co.zenbu.TomodachiDemo soundEnabled` afterwards.
- The user may be watching or clicking the live app. A click shows up in snapshots as unexpected answers or restarts.
- After testing, relaunch the user's copy with `mac-demo/run.sh`.

## Rules

- **Keep the docs current in the same change:**
  - a seam moved → `architecture.md`
  - a feature changed status → `backlog.md`
  - a decision was made → `decisions.md`
  - something new works → `concepts.md`
  - run/debug steps or Coucou files touched → `mac-demo/README.md`
- **Add Tomo code behind the seams** in `architecture.md` (`Tomo*.swift`), not inside Coucou files. If you must touch a Coucou file, add it to the table in `mac-demo/README.md`.
- **Secrets** live in `.env` (gitignored) or the Keychain. Never commit, print or log a key.
- **Never commit** `mac-demo/build/`.
- **Coucou's code is MIT; its assets are not.** The name, the Mochi character and the sounds are reserved (`mac-demo/LICENSE-ASSETS.md`). Don't ship them, and don't make Tomo look more like Mochi.
- **Don't invest in the offline keyword matcher** (`TomoBrain.offlineReply`). The Zenbu dictionary system replaces it.
