# Mac App Store listing (draft)

The Mac App Store isn't set up yet. Testers get Developer ID betas ([README.md](README.md), "Beta builds for
testers"). This is the listing written as if it were, so it's ready when the app is.

## What isn't set up

- **The app:** it isn't sandboxed (`ENABLE_SANDBOX: NO` in `NotchBuddy/project.yml`), which the Mac App Store
  requires, and there's no upload script: `scripts/release-beta.sh` exports for Developer ID, and the iPhone's
  `ios-demo/scripts/testflight.sh` is the model for an App Store export.
- **App Store Connect:** one record, **Tomodachi by Zenbu Japanese** (app ID `6821401516`), has iOS and macOS
  versions. Same bundle ID (`com.zenbujapanese.tomo`), so one purchase covers both.
- **Two things App Review may question in today's build:** ⌥-clicking the menu bar icon shows the testing tools
  in every build (`TomoTestingTools`), and the first run's "Open Tomodachi when I log in" switch starts on (it's
  shown, and Settings turns it off).

## The listing

The same shape as the iPhone's ([ios-demo/app-store.md](../ios-demo/app-store.md)), with the same limits:

| File | What |
|---|---|
| `metadata/app-info/en-US.json` | Name, subtitle, category, privacy policy, age rating and privacy label. App Store Connect keeps these per app, so they must match `ios-demo/metadata/app-info/en-US.json` |
| `metadata/version/1.0/en-US.json` | Description, keywords, promotional text, support URL, copyright, What's New (empty for a first release) and the review notes |
| `metadata/screenshots/` | Five screenshots, 2880 × 1800 (below) |

It follows the iPhone listing's rules (Japanese only, no AI, progress in the learner's own iCloud, honest pacing,
Data Not Collected) and says what's the Mac's own: Tomo lives by the notch and drops in while you work, the
first run asks about open at login, and the Tomodachi window has Tomo, Words, Settings and About. The review
notes say where Tomo appears on Macs with and without a notch, and how to open the window.

## Screenshots

`python3 mac-demo/scripts/make-screenshots.py <raw dir> mac-demo/metadata/screenshots` draws a desktop (the icon's
sky blue, a menu bar and a notch), puts the app's own snapshots on it and adds a headline. The headlines, and
which raw files each shot uses, are in its `SHOTS`. The notch is a 16" MacBook Pro's, where the snapshots were
taken; the island snapshot is centred on the notch of the Mac that takes it.

Each raw file is a `TOMO_SNAPSHOT_DIR` image ([docs/verification.md](../docs/verification.md)) from a run with
`TOMO_HEADLESS=1`, its own `TOMO_DATA_DIR`, `TOMO_SEED=variety-1` and `TZ=` a mid-morning zone, launched by path.
The seeds are the iPhone's (`ios-demo/app-store.md`):

| Raw file | From | Seed and flags |
|---|---|---|
| `island-round.png` | `snap-NNN.png` once Tomo asks | The iPhone's `2-round` seed |
| `island-win.png` | `snap-NNN.png` showing the Win | The iPhone's `3-win` seed, `TOMO_AUTOPLAY=right` |
| `first-run.png`, `island-first-run.png` | `onboarding-NNN.png` with Tomo just hatched, and the `snap-NNN.png` of the same second | A fresh data folder, `TOMO_ONBOARDING=1 TOMO_AUTOPLAY=1` |
| `window-tomo.png`, `island-small.png` | `window-tomo-NNN.png`, and a `snap-NNN.png` with small Tomo by the notch | The iPhone's `4-tomo` seed, `TOMO_OPEN_WINDOW=tomo` |
| `window-words.png` | `window-words-NNN.png` | The iPhone's `5-words` seed, `TOMO_OPEN_WINDOW=words` |

Headless runs start silent, so the card's speaker button shows as off.
