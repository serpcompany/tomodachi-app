# iPhone demo

Tomodachi on the iPhone ([#52](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/52)): a shell around the `TomoCore` package, like the Mac app. Today it's one screen: Tomo, big and alive, with the same rounds as the notch card (pictures, needs, meanings, and answering in your own words at 3さい). Opening the app is free play; Tomo never times out while it's on screen. Lock Screen visits (Live Activities) and widgets come next.

| File | What |
|---|---|
| `Tomodachi/Sources/TomodachiApp.swift` | The app, and `TomoPhoneShell`: sets `TomoGame`'s closures (open = the app is active; `onBotState` → the chick) |
| `Tomodachi/Sources/TomoPhoneView.swift` | The screen: header and level bar, `TomoChickView`, what Tomo says, the result, the answers |
| `Tomodachi/project.yml` | XcodeGen spec. iOS 18+, iPhone only, bundle ID `com.zenbujapanese.tomodachi` (same as the Mac app) |

## Build and run (simulator)

```bash
cd ios-demo/Tomodachi && xcodegen && xcodebuild -scheme Tomodachi -destination 'platform=iOS Simulator,name=tomodachi' -derivedDataPath ../build build
xcrun simctl install tomodachi ios-demo/build/Build/Products/Debug-iphonesimulator/Tomodachi.app
xcrun simctl launch tomodachi com.zenbujapanese.tomodachi
```

`tomodachi` is a simulator made for this app (`xcrun simctl create tomodachi com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0`), so test runs don't touch other projects' simulators. Its saved progress lives in the app's container on that simulator.

## Debug flags

The Mac's `TOMO_*` flags work when passed through `simctl` with a `SIMCTL_CHILD_` prefix, e.g. `SIMCTL_CHILD_TOMO_STAGE=3 xcrun simctl launch tomodachi com.zenbujapanese.tomodachi`. Mute Tomo with `xcrun simctl spawn tomodachi defaults write com.zenbujapanese.tomodachi soundEnabled -bool false`.

Not yet on the iPhone: the mic (typing only), word cards, Explain, Settings, AI provider setup (keys from the environment only).
