# The island

The Mac's shell: Coucou's notch window and its open and close rules, and Tomo's card and help panel
inside it. The other systems are mapped in [architecture.md](architecture.md); what a learner sees
is in [concepts.md](concepts.md) ("Lives in the notch", "Drop-in visits"); which Coucou files we
changed is in [coucou-fork.md](coucou-fork.md).

## The shell

Coucou's notch window and state machine (`IslandWindowController`, `IslandStateMachine`,
`IslandRootView`), cut down to what Tomo uses: it shows Tomo's card, the dizzy card or a visit's
peek (`TomoPeek.swift`: a bar Tomo calls from, which opens into the card with its word sliding into
place), and nothing of Coucou's agent features is left ([coucou-fork.md](coucou-fork.md)). Its open
and close rules (`IslandStateMachine`: hidden, resting, a peek, the card) are pure: each input takes
the time and returns when the rules next need the clock, and the controller sets one timer for that,
so `TomoIslandSelfTest` runs them on a stopped clock.

Tomo reaches the shell only through four closures on `TomoGame` (`openIsland`, `closeIsland`,
`isIslandOpen`, `focusInput`, plus `peeksFirst`, `peekIsland`, `isPointerInside`, `onBotState`,
`onHelpChange`, `onActivity` and `secondsSinceInput`), set in `AppDelegate`, and calls `acceptOffer`
whenever the card opens. Another shell sets the same closures: the iPhone app's `TomoPhoneShell`
([iphone.md](iphone.md)).

Invariants on the Mac:

- The island sits on the screen Settings picks (`TomoScreenChoice.pick`: the notch screen, else the
  main display, by default; the main display; a display by name; or the pointer's, moving only while
  closed) and moves when displays change.
- Without a notch it's a capsule 4 pt below the top of the screen, rounded all round, that never
  hides (`IslandScreenGeometry`, `shownMode`).
- It needs no permission. It follows the pointer through mouse event monitors (a sandboxed build
  gets them too), with no clock while the pointer is away from it.
- After a close, hovering doesn't reopen the island until the pointer has left it once. A peek
  counts as open.
- One Tomo travels between the island's states on a spring, never fading out in one place and in at
  another (`TomoTravel`: into the card on a click, from a peek into its card, back beside the notch
  as it tucks in; a visit still drips in), and the card or the peek waits for Tomo to be pulled up
  only when it folds away (hidden; `AppState.leaving`, closed for the game at once).
- The resting island and its click area grow together under the pointer (`islandSize`).
- It takes the keyboard only when the learner opens it (a click, the menu, their shortcut), so Esc
  works then and a visit or a peek never takes a keystroke
  ([decisions-2026-10-07.md](decisions-2026-10-07.md)). The shortcut (`TomoShortcut`) is a Carbon
  hot key, so no permission; there's none until the learner records one, and a test run never
  registers it.
- It's a non-activating panel that can't be hidden: Tomodachi is a regular app with a Dock icon, and
  the island never brings it to the front.

## The card and the help panel

`TomoView.swift`. The card is a fixed grid (`TomoGrid`): Tomo's column plus fixed rows, and new UI
goes into a slot: no row sizes itself, and text that can grow is capped. Its light tells the moment
(TomoCore's `TomoMoment`, drawn from Tomo across the card and the island by
`TomoMomentLight.swift`): never red, still between moments, and without its ripple under Reduce
Motion. The island's views read the game once each change has landed (`onGameSettled`): one drawn as
the island opens would miss a change made in the same moment.

Help (a hint, an explanation, a word card) never squeezes into the card: `TomoGame.help` grows the
island by a panel underneath, and the card keeps its place while it grows (the island's edge cuts
the panel until it fits). Word cards (`TomoWords.swift`) are a prototype, using an AI meaning and
the Mac's dictionary (only one in the learner's language, `TomoMacDictionaries`) until the Zenbu
dictionary provides lookups per target language
([#9](https://github.com/serpcompany/tomodachi-app/issues/9),
[#31](https://github.com/serpcompany/tomodachi-app/issues/31)).
