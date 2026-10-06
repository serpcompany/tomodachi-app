# iPhone demo

Tomodachi on the iPhone ([#52](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/52)): a shell around the `TomoCore` package, like the Mac app. Today it's one screen: Tomo, big and alive, with the same rounds as the notch card (pictures, needs, meanings, and answering in your own words at 3さい). Opening the app is free play; Tomo never times out while it's on screen. A Home Screen widget shows Tomo, its age and level, and what's waiting; a Live Activity puts Tomo on the Lock Screen and in the Dynamic Island.

| File | What |
|---|---|
| `Tomodachi/Sources/TomodachiApp.swift` | The app, and `TomoPhoneShell`: sets `TomoGame`'s closures (open = the app is active; `onBotState` → the chick) |
| `Tomodachi/Sources/TomoPhoneView.swift` | The screen: header and level bar, `TomoChickView`, what Tomo says, the result, the answers |
| `Tomodachi/Sources/TomoWordSheet.swift` | Tap a word in Tomo's line: its word card, with Open in Zenbu and the iPhone's dictionary (`UIReferenceLibraryViewController`) |
| `Tomodachi/Widgets/TomoWidgets.swift` | The Home Screen widget (small, medium): reads the `TomoGlance` the shell writes to the App Group, draws Tomo with `TomoMovingChick` |
| `Tomodachi/Sources/TomoLiveVisit.swift`, `Shared/TomoVisitActivity.swift`, `Widgets/TomoVisitLiveActivity.swift` | Tomo's Lock Screen card and Dynamic Island (a Live Activity): "A new word is ready to learn" with the experience bar and a Play button that opens one round on the card (`TomoPlayIntent`, `TomoAnswerIntent`), or asleep, saying when the next words come |
| `Tomodachi/Widgets/TomoMovingChick.swift`, `Widgets/Fonts/` | Tomo moving on widgets and the Lock Screen: a seconds timer set in a font whose digits are frames of Tomo. Rebuild the fonts after changing Tomo's look: `TOMO_RENDER_CARD_FRAMES=<dir>` on the Mac app, then `python3 ios-demo/scripts/make-frame-font.py <dir> ios-demo/Tomodachi/Widgets/Fonts` (needs `pip install fonttools pillow`) |
| `Tomodachi/project.yml` | XcodeGen spec. iOS 18+, iPhone only, bundle ID `com.zenbujapanese.tomodachi` (same as the Mac app) |

## Build and run (simulator)

```bash
cd ios-demo/Tomodachi && xcodegen && xcodebuild -scheme Tomodachi -destination 'platform=iOS Simulator,name=tomodachi' -derivedDataPath ../build build
xcrun simctl install tomodachi ios-demo/build/Build/Products/Debug-iphonesimulator/Tomodachi.app
xcrun simctl launch tomodachi com.zenbujapanese.tomodachi
```

Signing is automatic with team `W3GXL2NQQP` (the one Pedos ships with). The simulator needs nothing more. For a device, Xcode must be signed in to that team (Xcode → Settings → Accounts); the first device build with `-allowProvisioningUpdates` registers the App IDs and the App Group `group.com.zenbujapanese.tomodachi`. To try the widget: long-press the Home Screen → Edit → Add Widget → Tomodachi.

`tomodachi` is a simulator made for this app (`xcrun simctl create tomodachi com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0`), so test runs don't touch other projects' simulators. Its saved progress lives in the app's container on that simulator.

## TestFlight

`ios-demo/scripts/testflight.sh` archives a Release build and uploads it (`scripts/ExportOptions.plist`: App Store Connect, automatic signing, Xcode picks the next build number). It needs Xcode signed in to team `W3GXL2NQQP` (the one Pedos ships with) and the app record **Tomodachi: Language Companion** ("Tomodachi" was taken; bundle ID `com.zenbujapanese.tomodachi`) in App Store Connect, and at least one device registered on the team (automatic signing archives with a development profile first). The script puts Apple's tools first in `PATH`: Homebrew's `rsync` breaks Xcode's packaging ("Copy failed"). The app icon is Tomo on a sky-blue gradient, rendered from Tomo's code: `TOMO_RENDER_ICON=<dir>` on the Mac app writes `icon-ios-1024.png`, copied to `Tomodachi/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.

## App Store

The listing lives in `ios-demo/metadata/`: `app-info/en-US.json` (name, subtitle, category, privacy) and `version/1.0/en-US.json` (description, keywords, promotional text, URLs, review notes), in the same shape as the Zenbu iOS app's. Screenshots are 6.9" (1320×2868): capture raw screens on a `tomodachi-max` simulator (iPhone 17 Pro Max, status bar set with `xcrun simctl status_bar … override --time 9:41`), then `python3 ios-demo/scripts/make-screenshots.py <raw dir> ios-demo/metadata/screenshots/6.9` puts each under its headline on the icon's sky blue; `6.3/` holds the same images at 1206×2622, the size App Store Connect asks for first ("iPhone with Dynamic Island, medium display").

## Debug flags

The Mac's `TOMO_*` flags work when passed through `simctl` with a `SIMCTL_CHILD_` prefix, e.g. `SIMCTL_CHILD_TOMO_STAGE=3 xcrun simctl launch tomodachi com.zenbujapanese.tomodachi`. `TOMO_CARD_COUNTDOWN=<seconds>` fakes "nothing waiting, next words in that many seconds" for the Lock Screen card and the widget. To see the card without running the app, open `Widgets/TomoVisitLiveActivity.swift` in Xcode and show the canvas (⌥⌘↩): its previews show the Lock Screen card and the expanded, compact and minimal Dynamic Island, ready and waiting. On a simulator or phone, play a round, then go Home to see the Dynamic Island (long-press it to expand) or lock the device (⌘L in Simulator) to see the card. Mute Tomo with `xcrun simctl spawn tomodachi defaults write com.zenbujapanese.tomodachi soundEnabled -bool false`. Right after installing, give iOS a few seconds before tapping Play or a choice on the card: until it has indexed the app's actions, the tap fails ("There is no metadata for TomoPlayIntent" in the system log).

Not yet on the iPhone: the mic (typing only), word cards, Explain, Settings, AI provider setup (keys from the environment only).
