# Research: how other notch apps present, and what Tomo's notch could borrow

Checked 2026-10-10 against Coucou at `c946650`, dotpals at `2ddc2ed`, boring.notch, Atoll,
DynamicNotchKit and NotchDrop (source), and Alcove and NotchNook (their sites). Question: beyond
Tomo's character ([character-ideas.md](character-ideas.md)), how do these apps use the notch, and what
would make Tomodachi's notch present better? ([#110](https://github.com/serpcompany/tomodachi-app/issues/110))

## Answer

Our notch has two states that matter: Tomo resting beside the notch, and the full card. Every other app
has a state in between and uses both sides of the notch. Ours leaves **the right side of the resting
island empty** and opens a visit **straight into the full card**. The biggest wins are filling that side
with what the iPhone's Dynamic Island already shows, and letting a visit peek before it opens. Several
pieces exist as MIT code in Coucou (added since our fork, or deleted by us with the agent features).

## How ours presents today

- **Sizes:** hidden (the notch alone), compact (the notch plus 160 pt, Tomo at x = 40 in the left side,
  the right side empty), expanded (640 × 208, plus the help panel). `IslandTypes`, `IslandWindowController`.
- **Shape and motion:** square top, bottom corners 14 pt closed and 22 pt open, no shadow; opens with a
  spring, closes with a 0.34 s ease, content fades. `IslandRootView`.
- **Waiting:** a 7 pt red dot by small Tomo and an occasional bounce.
- **Timers:** compact folds to hidden after 60 s, the open card to compact after 15 s; an ignored visit
  tucks back after 10 s (20 s at 3さい) with no visible countdown.
- **Screen:** the notch screen, else the first; an 80 × 24 strip on Macs without a notch.
- **Polling:** the pointer is checked 60 times a second, always.

## What the others do

| App | License | Worth noting |
|---|---|---|
| Coucou (since our fork) | MIT | Mini characters in the right side, sized to the notch; open on hover (opt-in); `isHeldOpen`; a 14 pt badge with an icon and glow; which screen, including "follow the mouse"; global shortcuts via Carbon (no Accessibility); a weekly recap on Monday mornings; a now-playing pill; adaptive polling (60 Hz near the island, 8 Hz away). The countdown bar we deleted in [#93](https://github.com/serpcompany/tomodachi-app/pull/93). |
| dotpals | MIT | Four modes (hidden strip, peek, bar, open) as a pure reducer with a next-check time; hover rules that stop accidental opens; one alert at a time, news held while you're away; a bar that summarizes without opening; a Today row with Copy; a light sweeping the bottom edge while working; a pal hanging under the island on a thread. Sits below the menu bar, so it looks the same on any screen. |
| boring.notch | GPL-3 (ideas only) | Music as a live activity either side of the notch, moving into the open view with `matchedGeometryEffect`; a 1.5 s "sneak peek" line; HUDs that widen sideways; swipe down to open, up to close. |
| Atoll | GPL-3 (ideas only) | A boring.notch fork: a minimal mode, a "Dynamic Island" capsule on external displays, an XPC kit for other apps' live activities. |
| DynamicNotchKit | MIT | hidden, compact (content either side) and expanded; sides enter with blur and a horizontal scale. Not worth adopting: its own panel can take the keyboard and its own state machine would duplicate Coucou's. |
| NotchDrop | MIT | A "popping" state: the notch grows 4 pt on hover as a cue. |
| Alcove, NotchNook | closed | Live activities, swipe gestures, custom HUDs, lock screen widgets. |

## What became issues

| Issue | Idea | Source | Size |
|---|---|---|---|
| [#121](https://github.com/serpcompany/tomodachi-app/issues/121) | The right side shows あそぼ！ and a count, or when words are back, and a level ring | Coucou, DynamicNotchKit, our Dynamic Island | small |
| [#122](https://github.com/serpcompany/tomodachi-app/issues/122) | A visit peeks as a bar first; the card opens on hover or click ([#19](https://github.com/serpcompany/tomodachi-app/issues/19)) | dotpals, Coucou, boring.notch | medium |
| [#117](https://github.com/serpcompany/tomodachi-app/issues/117) | Countdown line (restore Coucou's), glow, drip-in, small motion touches | Coucou, dotpals, NotchDrop | medium |
| [#123](https://github.com/serpcompany/tomodachi-app/issues/123) | Tomo appears on the screen you're using | Coucou | medium |
| [#124](https://github.com/serpcompany/tomodachi-app/issues/124) | A global shortcut to play with Tomo | Coucou | medium |
| [#125](https://github.com/serpcompany/tomodachi-app/issues/125) | A look back at today, and Tomo's week on Mondays ([#29](https://github.com/serpcompany/tomodachi-app/issues/29)) | dotpals, Coucou | medium |
| [#126](https://github.com/serpcompany/tomodachi-app/issues/126) | A capsule on Macs without a notch | Atoll, dotpals | medium |
| [#127](https://github.com/serpcompany/tomodachi-app/issues/127) | Swipe to open or tuck away (feasibility unverified) | boring.notch, Atoll | medium |
| [#128](https://github.com/serpcompany/tomodachi-app/issues/128) | Less battery: poll the pointer slowly while Tomo rests | Coucou | small |

Suggested order: #121 (small, seen all day), then #122 with #117, then #128. The state rules in #122
should be a pure, testable function ([#55](https://github.com/serpcompany/tomodachi-app/issues/55)).

## Rules these must keep

- **No guilt:** amber, never red; no red thresholds on a ring, no error shake, and nothing in the notch
  says what was missed.
- **Visits never take the keyboard:** a peek and the bar stay click-through outside the island.
- **Tomo is always alive:** every new state animates Tomo.
- **Coucou files** touched (`Island*`) get a row in [coucou-fork.md](../coucou-fork.md).

Not taken: DynamicNotchKit as a dependency (above), dotpals' red usage ring and error shake, and
showing Tomo inside Atoll (licence unclear, few users).

## Sources

- Coucou at `c946650`, `NotchBuddy/Sources/App/`: `IslandRootView`, `IslandStateMachine`,
  `IslandWindowController`, `IslandViewContent`, `IslandDisplayChoice`, `HotKeyCenter`,
  `ShortcutLogic`, `WeeklyRecapView`, `RecapStore`, `NowPlayingViews`, `SettingsView`; `CHANGELOG.md`
- dotpals at `2ddc2ed`: `bridge/notch.html`, `bridge/ui/notch-state.js`, `story.js`, `recap.js`,
  `desktop/main.js`
- github.com/TheBoredTeam/boring.notch, github.com/Ebullioscopic/Atoll,
  github.com/MrKai77/DynamicNotchKit, github.com/Lakr233/NotchDrop; the Alcove and NotchNook sites
- Not run: none of these apps was built or launched; behaviour comes from reading the source.
