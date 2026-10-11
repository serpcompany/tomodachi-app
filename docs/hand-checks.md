# Checks by hand

What test runs can't check, because they need real pointer, trackpad, keyboard or music: a headless run
(`TOMO_HEADLESS=1`) is invisible and click-through, and it never registers a hot key. Each check here says how
to set it up, what to do and what passes. Everything else is checked automatically
([verification.md](verification.md): the self-test, `swift test`, the iPhone UI journeys and CI).

Who runs them: the owner, or an agent driving the owner's screen with their go-ahead (it moves the real
pointer and can play music out loud). Which ones have passed lately is tracked as tick boxes in
[#146](https://github.com/serpcompany/tomodachi-app/issues/146), not here.

## Setup, for every check

They run on a throwaway Tomo, never the owner's:

1. Quit the owner's Tomo from its menu (Tomo → Quit), so only one Tomo is in the notch.
2. Build main's Debug app (AGENTS.md's build command), then start it from Terminal with the check's flags and a
   fresh data folder:

   ```bash
   <flags> TOMO_DATA_DIR=$(mktemp -d) ~/dev/repos/tomodachi-app/mac-demo/build/Build/Products/Debug/Tomodachi.app/Contents/MacOS/Tomodachi
   ```

3. Afterwards press Ctrl-C and reopen the owner's Tomo from the Dock.

Reduce Motion versions use `TOMO_REDUCE_MOTION=1` rather than System Settings. The flags are in
[debug-flags.md](debug-flags.md).

## The checks

| # | Check | Flags | Do | Passes when | Covers |
|---|---|---|---|---|---|
| 1 | Swipes reach the notch | `TOMO_SCROLL_PROBE=1 TOMO_PEEK=1 TOMO_DROPIN_EVERY=20` | Put another app in front. Without clicking, scroll down and up with two fingers on small Tomo, on a peek bar, then on the card. Optionally start a scroll on the menu bar and slide onto the notch, and try a mouse wheel | Terminal shows `scroll-probe tomodachi … window=island panelKey=false appActive=false` for each; then swipe to open can be built (#130). `scroll-probe another app …` or nothing means it can't | #162 |
| 2 | Desktop Tomo: drag out | `TOMO_DESKTOP=1 TOMO_DROPIN_EVERY=60` (build the `prototype-desktop-tomo` branch: #166 says how) | Press on small Tomo and drag it onto the desktop; let go | Tomo follows the pointer and stays where it's dropped, inside the screen | #166 |
| 3 | Desktop Tomo: company and home | as 2 | Move the pointer near Tomo, then leave it alone 8 s, come back, then wait for a visit or press ⌘D | Its eyes follow the pointer; it dozes after 8 s and wakes when the pointer returns; at a visit it flies home along an arc (about 1 s) | #166 |
| 4 | Desktop Tomo: drop on the notch | as 2 | Drag Tomo out, then drop it on the notch | It goes straight home beside the notch | #166 |
| 5 | Dancing to music | `TOMO_MUSIC_PROBE=1`, and in another Terminal `log stream --predicate 'eventMessage CONTAINS "Tomo music"'` | Play a song in Music (and Spotify, if installed), pause it, skip, quit the player | Small Tomo dances while it plays and stops on pause or quit; the log shows each state. During お盆 (Aug 13–16) it side-steps | #167 |
| 6 | Pointing at a peek; hovering after a close | `TOMO_PEEK=1 TOMO_DROPIN_EVERY=20` | Move the pointer onto a peek and rest it there. Then close the card with Esc while the pointer is still on it, and rest the pointer again | The peek opens after about 0.45 s. After the close, the card doesn't reopen until the pointer has left the island once | #139, #143 |
| 7 | The resting island grows | none | Move the pointer onto the resting island | It grows a little (+8 × +4 pt) and shrinks back when the pointer leaves | #142 |
| 8 | Flick and click | none | From far across the screen, flick the pointer to small Tomo and click at once, five times | It opens on the first click every time | #135 |
| 9 | The shortcut to play | none | In Settings → Shortcut to play, record ⌃⌥T. Put another app in front, press ⌃⌥T, press it again, press it once more, then press Esc. Clear the shortcut afterwards | It opens Tomo to play, closes it, opens it again, and Esc closes it; no Accessibility prompt | #160 |
| 10 | Tomo travels | none | Click small Tomo, then close the card; open a peek into its card | One Tomo moves on a spring from beside the notch into the card and back, smoothly, at full speed | #165 |

## iPhone

The iPhone's key journeys run automatically as UI tests, the long press on Tomo included (#133, #168).
Still by hand: a real device's Lock Screen card and widgets over a day, and iCloud sync between the
owner's Mac and phone ([verification.md](verification.md), Sync).

## Adding a check

Add a row when a change can only be checked by hand, with its flags, steps, what passes and its PR, and
add its tick box to #146. Remove the row once a test covers it.
