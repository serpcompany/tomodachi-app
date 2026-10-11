# The iPhone app

How the iPhone app hosts the game: its shell, its files, and the widgets and Lock Screen card that
draw what the app writes. Building it is only in [ios-demo/README.md](../ios-demo/README.md);
what a learner sees is in [concepts.md](concepts.md) ("On the iPhone", "Reminders (iPhone)"); the
other systems are mapped in [architecture.md](architecture.md).

## The shell

The iPhone app in `ios-demo/` is a shell around `TomoCore`, with its widget extension. Its
`TomoPhoneShell` sets the same closures on `TomoGame` as the Mac's `AppDelegate`
([island.md](island.md)): it treats the app being on screen as open, so Tomo never times out while
you look at it, and so is a round open on the Lock Screen card (`TomoLiveVisit.isPlaying`).

## Widgets and the Lock Screen card

Widgets can't run the game: the app writes a `TomoGlance` (age, level, bar, what Tomo's doing and
the `TomoMoment` it's lit in, never a count, in the learner's language) to the App Group
`group.com.zenbujapanese.tomo`, and the widget draws it, with the mascot moving through a font of
its own frames (`TomoMovingMascot`; [decisions-2026-10-06.md](decisions-2026-10-06.md)). The same
glance drives Tomo's Lock Screen card, a Live Activity (`TomoLiveVisit` in the app,
`TomoVisitLiveActivity` in the extension), once the learner said yes to it; it takes the app's rule,
time and words (`TomoGlance.follow`, times via `tomoClockLocale`), and its stale date is when
something counts again, so it turns to "ready" without the app running.

The card's Play and choice buttons are `LiveActivityIntent`s (`TomoPlayIntent`, `TomoAnswerIntent`)
that iOS runs in the app's process, launching it in the background if needed; they reach the game
through `TomoVisitHook`, set in the app's `init`
([#52](https://github.com/serpcompany/tomodachi-app/issues/52)). There's one card: a launch updates
the one on the Lock Screen, stale or not, and ends any others (`TomoLockCard`).

## Files

| File | What |
|---|---|
| `Tomodachi/Sources/TomodachiApp.swift` | The app, and `TomoPhoneShell`: sets `TomoGame`'s closures (open = the app is active; `onBotState` → Tomo). The app follows Reduce Motion for every live Tomo (`TomoMotion`) |
| `Tomodachi/Sources/TomoPhoneHome.swift` | The tabs: Play (`TomoPhoneView`) and TomoCore's Tomo, Words, Together and Settings screens, with About in Settings. Settings shows the reminders' settings (`TomoReminderSettingsView`, from TomoCore) |
| `Tomodachi/Sources/TomoPhoneFirstRun.swift` | The first run, full screen over the tabs; `TomoPhoneShell` holds the game, the Lock Screen card and the reminders until it's done (`endFirstRun`) |
| `Tomodachi/Sources/TomoPhoneView.swift` | The play screen: header and level bar, `TomoBlobView` (tap: a poke; long press: love, `TomoLoveCooldown`), what Tomo says, the result, the answers |
| `Tomodachi/Sources/TomoWordSheet.swift` | Tap a word in Tomo's line: its word card, with Open in Zenbu and the iPhone's dictionary (`UIReferenceLibraryViewController`) |
| `Tomodachi/Widgets/TomoWidgets.swift` | The Home Screen widget (small, medium) and the Lock Screen widget (rectangular, circular, inline): reads the `TomoGlance` the shell writes to the App Group, draws the mascot with `TomoMovingMascot` (Lock Screen: text and a gauge) |
| `Tomodachi/Sources/TomoLiveVisit.swift`, `Shared/TomoVisitActivity.swift`, `Widgets/TomoVisitLiveActivity.swift` | Tomo's Lock Screen card and Dynamic Island (a Live Activity, only once the learner said yes): "Tomo wants to play" with the experience bar and a Play button that opens one round on the card (`TomoPlayIntent`, `TomoAnswerIntent`), or asleep, saying when it's back in the app's own line ("Back at 10:12", `TomoGlance.back`) |
| `Tomodachi/Widgets/TomoMovingMascot.swift`, `Widgets/Fonts/` | The mascot moving on widgets and the Lock Screen: a seconds timer set in a font whose digits are frames of the mascot (`TomoLook.mascot`). Rebuild the fonts after changing the mascot or Tomo's drawing: `TOMO_RENDER_CARD_FRAMES=<dir>` on the Mac app, then `python3 ios-demo/scripts/make-frame-font.py <dir> ios-demo/Tomodachi/Widgets/Fonts` (needs `pip install fonttools pillow`) |
| `Tomodachi/project.yml` | XcodeGen spec. iOS 18+, iPhone only, bundle ID `com.zenbujapanese.tomo` (same as the Mac app); a Debug build is its own app, `com.zenbujapanese.tomo.debug` ("Tomodachi Debug", widgets `….debug.widgets`, App Group `group.com.zenbujapanese.tomo.debug`, [#54](https://github.com/serpcompany/tomodachi-app/issues/54)). No microphone or speech-recognition permission: answers are choices, and TomoCore leaves its listener out of iOS builds. The last build phase of the app and the widget runs `scripts/strip-packs.sh`, which leaves the Spanish draft pack out (the iPhone has no way to pick it) |

Paths are under `ios-demo/`.
