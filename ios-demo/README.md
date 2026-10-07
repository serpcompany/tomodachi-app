# iPhone demo

Tomodachi on the iPhone ([#52](https://github.com/serpcompany/tomodachi-app/issues/52)): a shell around the `TomoCore` package, like the Mac app. It has four tabs: **Play**, Tomo big and alive with the same rounds as the notch card (pictures, needs, meanings, and at 3さい what Tomo means or a reply that fits), and **Tomo**, **Words** and **Settings** (with About), the same screens as the Mac's Tomodachi window, from TomoCore. Opening the app is free play; Tomo never times out while it's on screen. A Home Screen widget shows Tomo, its age and level, and what's waiting; a Live Activity puts Tomo on the Lock Screen and in the Dynamic Island.

| File | What |
|---|---|
| `Tomodachi/Sources/TomodachiApp.swift` | The app, and `TomoPhoneShell`: sets `TomoGame`'s closures (open = the app is active; `onBotState` → Tomo) |
| `Tomodachi/Sources/TomoPhoneHome.swift` | The tabs: Play (`TomoPhoneView`) and TomoCore's Tomo, Words and Settings screens, with About in Settings. Settings has a marked slot for the reminder settings ([#88](https://github.com/serpcompany/tomodachi-app/issues/88)) |
| `Tomodachi/Sources/TomoPhoneView.swift` | The play screen: header and level bar, `TomoBlobView`, what Tomo says, the result, the answers |
| `Tomodachi/Sources/TomoWordSheet.swift` | Tap a word in Tomo's line: its word card, with Open in Zenbu and the iPhone's dictionary (`UIReferenceLibraryViewController`) |
| `Tomodachi/Widgets/TomoWidgets.swift` | The Home Screen widget (small, medium): reads the `TomoGlance` the shell writes to the App Group, draws the mascot with `TomoMovingMascot` |
| `Tomodachi/Sources/TomoLiveVisit.swift`, `Shared/TomoVisitActivity.swift`, `Widgets/TomoVisitLiveActivity.swift` | Tomo's Lock Screen card and Dynamic Island (a Live Activity): "A new word is ready to learn" with the experience bar and a Play button that opens one round on the card (`TomoPlayIntent`, `TomoAnswerIntent`), or asleep, saying when the next words come |
| `Tomodachi/Widgets/TomoMovingMascot.swift`, `Widgets/Fonts/` | The mascot moving on widgets and the Lock Screen: a seconds timer set in a font whose digits are frames of the mascot (`TomoLook.mascot`). Rebuild the fonts after changing the mascot or Tomo's drawing: `TOMO_RENDER_CARD_FRAMES=<dir>` on the Mac app, then `python3 ios-demo/scripts/make-frame-font.py <dir> ios-demo/Tomodachi/Widgets/Fonts` (needs `pip install fonttools pillow`) |
| `Tomodachi/project.yml` | XcodeGen spec. iOS 18+, iPhone only, bundle ID `com.zenbujapanese.tomodachi` (same as the Mac app). No microphone or speech-recognition permission: answers are choices, and TomoCore leaves its listener out of iOS builds. The last build phase of the app and the widget runs `scripts/strip-packs.sh`, which leaves the Spanish draft pack out (the iPhone has no way to pick it) |

## Build and run (simulator)

```bash
cd ios-demo/Tomodachi && xcodegen && xcodebuild -scheme Tomodachi -destination 'platform=iOS Simulator,name=tomodachi' -derivedDataPath ../build build
xcrun simctl install tomodachi ios-demo/build/Build/Products/Debug-iphonesimulator/Tomodachi.app
xcrun simctl launch tomodachi com.zenbujapanese.tomodachi
```

Signing is automatic with team `W3GXL2NQQP` (the one Pedos ships with). The simulator needs nothing more. For a device, Xcode must be signed in to that team (Xcode → Settings → Accounts); the first device build with `-allowProvisioningUpdates` registers the App IDs, the App Group `group.com.zenbujapanese.tomodachi` and the iCloud container `iCloud.com.zenbujapanese.tomodachi` (sync with the Mac, `TomoSync`). Debug builds sync in CloudKit's Development environment, TestFlight and the App Store in Production; Xcode switches iCloud and push to Production when it exports. On the simulator, sync needs it signed in to an iCloud account (Settings). To try the widget: long-press the Home Screen → Edit → Add Widget → Tomodachi.

`tomodachi` is a simulator made for this app (`xcrun simctl create tomodachi com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0`), so test runs don't touch other projects' simulators. Its saved progress lives in the app's container on that simulator.

## TestFlight

`ios-demo/scripts/testflight.sh` archives a Release build and uploads it (`scripts/ExportOptions.plist`: App Store Connect, automatic signing, Xcode picks the next build number). It needs Xcode signed in to team `W3GXL2NQQP` (the one Pedos ships with) and the app record **Tomodachi: Language Companion** ("Tomodachi" was taken; bundle ID `com.zenbujapanese.tomodachi`) in App Store Connect, and at least one device registered on the team (automatic signing archives with a development profile first). The script puts Apple's tools first in `PATH`: Homebrew's `rsync` breaks Xcode's packaging ("Copy failed"). The app icon is the mascot on a sky-blue gradient, rendered from Tomo's code: `TOMO_RENDER_ICON=<dir>` on the Mac app writes `icon-ios-1024.png`, copied to `Tomodachi/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.

## App Store

The listing lives in `ios-demo/metadata/`: `app-info/en-US.json` (name, subtitle, category, privacy) and `version/1.0/en-US.json` (description, keywords, promotional text, URLs, review notes), in the same shape as the Zenbu iOS app's. Screenshots are 6.9" (1320×2868): capture raw screens on a `tomodachi-max` simulator (iPhone 17 Pro Max, status bar set with `xcrun simctl status_bar … override --time 9:41`), then `python3 ios-demo/scripts/make-screenshots.py <raw dir> ios-demo/metadata/screenshots/6.9` puts each under its headline on the icon's sky blue; `6.3/` holds the same images at 1206×2622, the size App Store Connect asks for first ("iPhone with Dynamic Island, medium display").

## Debug flags

The Mac's `TOMO_*` flags work when passed through `simctl` with a `SIMCTL_CHILD_` prefix, e.g. `SIMCTL_CHILD_TOMO_STAGE=3 xcrun simctl launch tomodachi com.zenbujapanese.tomodachi`. `TOMO_CARD_COUNTDOWN=<seconds>` fakes "nothing waiting, next words in that many seconds" for the Lock Screen card and the widget. To see the card without running the app, open `Widgets/TomoVisitLiveActivity.swift` in Xcode and show the canvas (⌥⌘↩): its previews show the Lock Screen card and the expanded, compact and minimal Dynamic Island, ready and waiting. On a simulator or phone, play a round, then go Home to see the Dynamic Island (long-press it to expand) or lock the device (⌘L in Simulator) to see the card. Agents run the simulator headless (`xcrun simctl boot`, never Simulator.app) and mute Tomo with `xcrun simctl spawn tomodachi defaults write com.zenbujapanese.tomodachi soundEnabled -bool false`. Right after installing, give iOS a few seconds before tapping Play or a choice on the card: until it has indexed the app's actions, the tap fails ("There is no metadata for TomoPlayIntent" in the system log). `TOMO_OPEN_WINDOW=<screen>` (tomo, words, settings, about, startOver) opens a tab; launch with `simctl launch --terminate-running-process`, or a copy the system already started keeps running without your flags.

The play screen fits the Play tab from an iPhone SE (375 × 667) up: Tomo, its line and the answers share the height there is (`TomoPhoneView.fit`). Text follows Dynamic Type up to a cap, so it grows inside its row; VoiceOver reads the bar, Tomo, its line (in the Japanese voice, with each word's card as an action) and every choice. Tomo's voice and peeps use the `.ambient` audio session: the Ring/Silent switch mutes them, and they play over the learner's music. To check a short screen: an `iPhone SE (3rd generation)` simulator; for large text, `xcrun simctl ui <device> content_size accessibility-large`.

Not yet on the iPhone: the mic (answers are choices), Explain, reminders ([#88](https://github.com/serpcompany/tomodachi-app/issues/88)). AI provider setup is left out of the first release (keys from the environment only).
