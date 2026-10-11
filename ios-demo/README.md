# iPhone demo

Tomodachi on the iPhone ([#52](https://github.com/serpcompany/tomodachi-app/issues/52)): a shell around the `TomoCore` package, like the Mac app. It has five tabs: **Play**, Tomo big and alive with the same rounds as the notch card (pictures, needs, meanings, and at 3さい what Tomo means or a reply that fits), and **Tomo**, **Words**, **Together** and **Settings** (with About), the same screens as the Mac's Tomodachi window, from TomoCore. Opening the app is free play; Tomo never times out while it's on screen. A Home Screen widget shows Tomo, its age and level, and whether it wants to play (never how many words); a Live Activity puts Tomo on the Lock Screen and in the Dynamic Island.

A new learner's first launch shows the first run full screen over all of it: the hatch, the first word, how Tomo comes to you, the rhythm and quiet hours for reminders, the notification prompt, the widget how-to and the Lock Screen card, yes or not now (`TomoOnboarding`, `Shell.phone`).

Its files, and how the widgets and the Lock Screen card draw what the app writes:
[docs/iphone.md](../docs/iphone.md).

The play screen fits the Play tab from an iPhone SE (375 × 667) up: Tomo, its line and the answers share the height there is (`TomoPhoneView.fit`). Text follows Dynamic Type up to a cap, so it grows inside its row; VoiceOver reads the bar, Tomo, its line (in the Japanese voice, with each word's card as an action) and every choice. Tomo's voice and peeps use the `.ambient` audio session: the Ring/Silent switch mutes them, and they play over the learner's music. To check a short screen: an `iPhone SE (3rd generation)` simulator; for large text, `xcrun simctl ui <device> content_size accessibility-large`.

## Build and run (simulator)

```bash
udid=$(ios-demo/scripts/simulator.sh udid)   # your own simulator, made the first time
(cd ios-demo/Tomodachi && xcodegen && xcodebuild -scheme Tomodachi -destination "platform=iOS Simulator,id=$udid" -derivedDataPath ../build build)
xcrun simctl boot "$udid"
xcrun simctl install "$udid" ios-demo/build/Build/Products/Debug-iphonesimulator/Tomodachi.app
xcrun simctl launch "$udid" com.zenbujapanese.tomo
```

Signing is automatic with TSMC LLC's team `847HR8U8D9` (the Zenbu Japanese app's). The simulator needs nothing more. For a device, Xcode must be signed in to that team (Xcode → Settings → Accounts); the first device build with `-allowProvisioningUpdates` registers the App IDs, the App Group `group.com.zenbujapanese.tomo` and the iCloud container `iCloud.com.zenbujapanese.tomo` (sync with the Mac, `TomoSync`). Debug builds sync in CloudKit's Development environment, TestFlight and the App Store in Production; Xcode switches iCloud and push to Production when it exports. On the simulator, sync needs it signed in to an iCloud account (Settings). To try the widget: long-press the Home Screen → Edit → Add Widget → Tomodachi.

Every agent gets its own simulator, `tomodachi--<scope>`, from `scripts/simulator.sh` ([SERP's simulators standard](https://github.com/serpcompany/serp/blob/main/docs/engineering/technology/simulators.md)). The scope is the worktree's folder name, or the branch in the main checkout. `udid [scope]` finds or makes it (the newest iPhone Pro on the newest iOS installed; `TOMO_SIM_DEVICE` picks another model) and prints its UDID. `delete [scope]` removes it when the work is done. `prune` removes those whose worktree and branch are gone, never a booted one. Name every simctl and xcodebuild command by that UDID, never `booted` or another simulator. The long-lived `tomodachi` simulator is the owner's, and the script never deletes it. Saved progress lives in the app's container on each simulator.

## TestFlight

`ios-demo/scripts/testflight.sh` archives a Release build, numbers it by date and time (`YYMMDD.HHMM`, so every upload counts up), refuses it if its app or widgets carry another bundle ID, and uploads it to the app record **Tomodachi by Zenbu Japanese** (app ID `6821401516`, bundle ID `com.zenbujapanese.tomo`). Xcode signs it, so Xcode must be signed in to team `847HR8U8D9` (TSMC LLC). **The upload uses an App Store Connect API key** (role App Manager, made in App Store Connect → Users and Access → Integrations): its file is `~/.appstoreconnect/private_keys/AuthKey_<key ID>.p8` on the Mac that uploads, and its key ID and issuer ID are `ASC_KEY_ID` and `ASC_ISSUER_ID` in the repo's `.env` (gitignored). The key never goes in the repo; on another Mac, copy that one file securely or make a new key (App Store Connect can revoke any key). Without a key the script falls back to Xcode's own account (`scripts/ExportOptions.plist`). The script puts Apple's tools first in `PATH`: Homebrew's `rsync` breaks Xcode's packaging ("Copy failed"). The app icon is the mascot on a sky-blue gradient, rendered from Tomo's code: `TOMO_RENDER_ICON=<dir>` on the Mac app writes `icon-ios-1024.png`, copied to `Tomodachi/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.

## App Store

The listing is for version 1.1 (the rejected 1.0 becomes 1.1 in App Store Connect) and lives in `ios-demo/metadata/`: `app-info/en-US.json` (name, subtitle, category, privacy) and `version/1.1/en-US.json` (description, keywords, promotional text, URLs, review notes), in the same shape as the Zenbu iOS app's. Screenshots (`screenshots/6.9/`, `6.3/`) are real screens from a headless simulator under a headline: `ios-demo/scripts/make-screenshots.py`. What the listing may say, and how each screenshot is captured: [app-store.md](app-store.md).

## Debug flags

The flags, the first run and reminders in test runs, and the simulator rules: [debug-flags.md](debug-flags.md).

Not yet on the iPhone: the mic (answers are choices), Explain. AI provider setup is left out of the first release (keys from the environment only).
