# iPhone App Store listing

What the App Store listing says, where it lives, and how its screenshots are made. The owner pastes it into App
Store Connect and uploads the screenshots; nothing in the repo uploads them. Builds reach App Store Connect
through TestFlight ([README.md](README.md)).

## Version

The listing is for **version 1.1**, the build on TestFlight. Version 1.0 was rejected as incomplete; in App Store
Connect it becomes 1.1 and gets that build. It's still the app's first release, so **What's New** stays empty: App
Store Connect only asks for it from the second release on. Shipping is
[#80](https://github.com/serpcompany/tomodachi-app/issues/80); the privacy policy has to name Tomodachi first
([#105](https://github.com/serpcompany/tomodachi-app/issues/105)).

## The listing

| File | What |
|---|---|
| `metadata/app-info/en-US.json` | Name, subtitle, category, privacy policy, age rating and the privacy label. App Store Connect keeps these per app, not per version, so the Mac listing ([mac-demo/app-store.md](../mac-demo/app-store.md)) uses the same values |
| `metadata/version/1.1/en-US.json` | Description, keywords, promotional text, support URL, copyright, What's New and the review notes. One folder per version: the next version starts from a copy, and the old folder goes |
| `metadata/screenshots/6.9/`, `6.3/` | The screenshots (below) |

Limits: name and subtitle 30 characters, promotional text 170, keywords 100 (commas, no spaces; words already in
the name or subtitle are wasted there), description and review notes 4,000.

What the listing may say is what the build does:

- **Japanese only**, for English speakers. The name stays "Tomodachi: Language Companion".
- **No AI.** Meanings come from the pack, and the iPhone's dictionary is a tap away.
- **Progress stays in the learner's own iCloud** (CloudKit's private database), never "on your iPhone" alone, and
  there are no servers of ours. The privacy label stays **Data Not Collected**.
- **Honest pacing:** words come back over hours and days, and Tomo rests in between. Growing up takes months.
- **Tomo is a blob,** a different one for every learner ([docs/concepts.md](../docs/concepts.md)).

The review notes are for a reviewer with five minutes: no sign-in, what the first run asks (notifications and the
Lock Screen card are optional, each with its reason first), where the tabs are, that resting is spaced review and
not a dead end, how sync works, and where the widgets and the Live Activity are.

## Screenshots

App Store Connect asks for 6.9" (1320 × 2868) and 6.3" (1206 × 2622). Both come from the same raw captures:
`python3 ios-demo/scripts/make-screenshots.py <raw dir> ios-demo/metadata/screenshots` puts each under its
headline on the icon's sky blue and writes both sizes. The headlines are in the script's `SHOTS`.

The set is honest about the early game: Tomo at Lv 1–3, and one later age, as "watch it grow". There's no Home
Screen widget shot: a headless simulator can't add widgets, and a mock-up would be a fake.

| Raw file | Shows | Seed (`mac-demo/scripts/seed-progress.py <dir> …`) and flags |
|---|---|---|
| `1-hatch.png` | The first run: "This is your Tomo" | A fresh data folder, `TOMO_ONBOARDING=1 TOMO_AUTOPLAY=1`: the frame just after the egg cracks, with sparkles |
| `2-round.png` | A picture round at Lv 2 (ワンワン) | `--level 2 --through-level 1 --stage 5 --due 120 ja:wanwan=1=-0.2 ja:banana=2=3 ja:booru=1=1.5 ja:nyannyan=2=6 ja:te=1=2.5 ja:hai=1=3.5` |
| `3-win.png` | A Win, "1 more word to Lv 2" | `--level 1 --through-level 1 --stage 5 --due 120 ja:mama=4=-0.3 ja:papa=4=-0.1 ja:aita=4=9`, `TOMO_AUTOPLAY=right` |
| `4-tomo.png` | The Tomo tab, 2さい Lv 24, day 171 | `--level 24 --through-level 23 --stage 6 --due 200 --days 170 ja:hashi=5=150 ja:iru2=5=160 ja:jitensya=5=140 ja:mame=4=20 ja:nori2=3=6 ja:omoi=2=3 ja:onaji=1=1.5 ja:oshigoto=1=2`, `TOMO_OPEN_WINDOW=tomo` |
| `5-words.png` | The Words tab at Lv 3 | `--level 3 --through-level 1 --stage 5 --due 100 ja:hai=4=20 ja:wanwan=4=10 ja:banana=3=5 ja:dakko=3=6 ja:nenne=4=15 ja:nyannyan=2=3 ja:oichii=3=7 ja:te=2=2 ja:arigatou=3=4 ja:booru=4=12 ja:gohan=1=1 ja:kutsu=1=1.5 ja:ocha=1=1.8`, `TOMO_OPEN_WINDOW=words` |
| `6-comes-to-you.png` | The first run's "Tomo comes to you" | A fresh data folder, `TOMO_ONBOARDING=visits` |

Every run also gets `TOMO_SEED=variety-1` (the same blue Tomo in every shot) and `TZ=` a zone where it's mid-morning
(`America/Denver` while it's night in Japan), so no time on screen falls in quiet hours. Capture on an iPhone 17 Pro
Max simulator of your own, headless ([debug-flags.md](debug-flags.md)):

```bash
xcrun simctl create tomodachi-shots com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-27-0
xcrun simctl boot tomodachi-shots
xcrun simctl spawn tomodachi-shots defaults write -g AppleICUForce24HourTime -bool false   # then shut down and boot again
xcrun simctl status_bar tomodachi-shots override --time 9:41 --batteryState discharging --batteryLevel 100 \
  --dataNetwork wifi --wifiBars 3 --cellularBars 4
xcrun simctl install tomodachi-shots ios-demo/build/Build/Products/Debug-iphonesimulator/Tomodachi.app
xcrun simctl spawn tomodachi-shots defaults write com.zenbujapanese.tomo soundEnabled -bool false
SIMCTL_CHILD_TOMO_DATA_DIR=<dir> SIMCTL_CHILD_TOMO_SEED=variety-1 SIMCTL_CHILD_TZ=America/Denver \
  SIMCTL_CHILD_TOMO_OPEN_WINDOW=tomo xcrun simctl launch --terminate-running-process tomodachi-shots com.zenbujapanese.tomo
xcrun simctl io tomodachi-shots screenshot <raw dir>/4-tomo.png
```

The simulator copies the Mac's 24-hour setting, which turns the status bar's 9:41 into 09:41; the `defaults` line
undoes that. For a moment that passes (the hatch, a Win), take screenshots in a loop and pick one, skipping frames
where the Dynamic Island shows. Tomo is muted for test runs, so the Play screen's speaker button shows as off.
Delete the simulator afterwards (`xcrun simctl delete tomodachi-shots`).
