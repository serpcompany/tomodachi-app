# iPhone demo

Tomodachi on the iPhone ([#52](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/52)): a shell around the `TomoCore` package, like the Mac app. Today it's one screen: Tomo, big and alive, with the same rounds as the notch card (pictures, needs, meanings, and answering in your own words at 3さい). Opening the app is free play; Tomo never times out while it's on screen. A Home Screen widget shows Tomo, its age and level, and what's waiting; a Live Activity puts Tomo on the Lock Screen and in the Dynamic Island.

| File | What |
|---|---|
| `Tomodachi/Sources/TomodachiApp.swift` | The app, and `TomoPhoneShell`: sets `TomoGame`'s closures (open = the app is active; `onBotState` → the chick) |
| `Tomodachi/Sources/TomoPhoneView.swift` | The screen: header and level bar, `TomoChickView`, what Tomo says, the result, the answers |
| `Tomodachi/Widgets/TomoWidgets.swift` | The Home Screen widget (small, medium): reads the `TomoGlance` the shell writes to the App Group, draws Tomo with `TomoChickStill` |
| `Tomodachi/Sources/TomoLiveVisit.swift`, `Shared/TomoVisitActivity.swift`, `Widgets/TomoVisitLiveActivity.swift` | Tomo's Lock Screen card and Dynamic Island (a Live Activity): "あそぼ！ · 3 words waiting", or asleep beside a live countdown to the next words |
| `Tomodachi/project.yml` | XcodeGen spec. iOS 18+, iPhone only, bundle ID `com.zenbujapanese.tomodachi` (same as the Mac app) |

## Build and run (simulator)

```bash
cd ios-demo/Tomodachi && xcodegen && xcodebuild -scheme Tomodachi -destination 'platform=iOS Simulator,name=tomodachi' -derivedDataPath ../build build
xcrun simctl install tomodachi ios-demo/build/Build/Products/Debug-iphonesimulator/Tomodachi.app
xcrun simctl launch tomodachi com.zenbujapanese.tomodachi
```

Debug builds are signed to run locally (`CODE_SIGN_IDENTITY: "-"`), so the App Group the app and widget share works in the simulator without a team. To try the widget: long-press the Home Screen → Edit → Add Widget → Tomodachi.

`tomodachi` is a simulator made for this app (`xcrun simctl create tomodachi com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0`), so test runs don't touch other projects' simulators. Its saved progress lives in the app's container on that simulator.

## Debug flags

The Mac's `TOMO_*` flags work when passed through `simctl` with a `SIMCTL_CHILD_` prefix, e.g. `SIMCTL_CHILD_TOMO_STAGE=3 xcrun simctl launch tomodachi com.zenbujapanese.tomodachi`. `TOMO_CARD_COUNTDOWN=<seconds>` fakes "nothing waiting, next words in that many seconds" for the Lock Screen card and the widget. Mute Tomo with `xcrun simctl spawn tomodachi defaults write com.zenbujapanese.tomodachi soundEnabled -bool false`.

Not yet on the iPhone: the mic (typing only), word cards, Explain, Settings, AI provider setup (keys from the environment only).
