# Research: ideas for Tomo from Coucou and dotpals

Checked 2026-10-10 against Coucou at `c946650` (github.com/Louis-CFM/coucou) and dotpals at `2ddc2ed`
(github.com/Rikinshah787/dotpals). Question: what can make Tomo and the notch feel more alive, with
more animation and better moments, and what may we take?
([#110](https://github.com/serpcompany/tomodachi-app/issues/110), with
[#109](https://github.com/serpcompany/tomodachi-app/issues/109) and
[#111](https://github.com/serpcompany/tomodachi-app/issues/111))

## Answer

Take techniques, not characters. Both projects are MIT code, but neither gives us drawings to ship:
Mochi's look, expressions and animations are reserved, and dotpals' pals are its own designs (one is
named after a product). Tomo already does most of what they do, often better: springs with substeps,
three pokes to dizzy, fidgets, dozing, particles. The gaps are **dress-up**, **choreographed big
moments**, **leaving the notch** (to the desktop, or with an entrance), **music**, a few small touches,
and **Reduce Motion**, which Tomo ignores today. Each became an issue (below).

## What each one is

- **Coucou since our fork** (0.1.3–0.1.6; we forked before them): 12 outfits drawn in code that follow
  the head as it turns in 3D, outfits picked by date, hat and pompom springs, dancing while music plays,
  Mochi dragged out onto the desktop, and a new launch greeting. Swift, plus a TypeScript port for
  Windows that mirrors it one for one.
- **dotpals:** an Electron agent monitor (Claude Code, Codex, Cursor…) with a floating pal and a notch
  island. Nine pals drawn as inline SVG in a web component, with a looping idle by mood, one-shot moves
  (jump, squish, shake, spin, dizzy…), drawn eye expressions, particles and a glow per state. Young
  (created 2026-09-30, 39 stars). Not pixel art: "dot" is the name. No code drops into Swift.

## May we use it

| | Code | Character |
|---|---|---|
| Coucou | MIT (keep the notice): projection maths, clipping, easing, springs, the date windows, desktop geometry | Reserved: Mochi, its 12 outfit drawings, its dances and greeting choreography, `design/` ([coucou-fork.md](../coucou-fork.md)) |
| dotpals | MIT: small functions (`gazeFor`, `foreshorten`, particle curves) if copied, with the notice | MIT too, but don't borrow its pals or names: Tomo is a seeded blob nobody else has ([decisions.md](../decisions.md), 2026-10-07) |

On 2026-10-09 the owner asked Coucou's author whether outfit drawings could be adapted onto Tomo
(#109). Until he says yes in writing, every outfit is drawn by us.

## Techniques worth having

**Things that turn with the face** (Coucou, `MochiOutfitDrawing.swift`). The head is a solid of
revolution; points on it are rotated by yaw and pitch and projected, keeping depth, so a hat sits on the
head as it turns and glasses switch between in front and behind. A cap is clipped to the half of a ring
that faces the viewer. Tomo has no yaw: `drawFace` fakes turning by shifting the face (`fx`), and most
silhouettes (hexagon, sun, triangle) aren't solids of revolution. So the cheap path for Tomo is 2.5D:
anchor accessories where `drawTopper` and `drawFace` already put the topper and eyes, move them with
`fx`, and swing them with the `sway` and `jiggle` springs.

**Outfits by date** (Coucou, `MochiWardrobe.swift`). An ordered list of date windows, an "auto" choice,
Easter by computus, and tests at the window edges. For Japan: fixed dates for most events; 節分 moves
with 立春 (a small table); 月見 is the 15th of the 8th lunar month, and `Calendar(.chinese)` uses
China's time zone, so it can be a day off (unverified; test against a published list); 花見 is a
regional window.

**Springs on soft parts** (Coucou, `BotEngine.swift`). Hat tips and pompoms follow a spring driven by
head speed, and a slap kicks the spring directly. Tomo's `step()` already runs these springs, more
stably (120 Hz substeps). The missing piece: `poke()` never kicks `swayVel`/`jiggleVel`, so ears and
sprouts don't flop when tapped.

**Dancing** (Coucou). Play and pause come from the players' distributed notifications
(`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`), which need no permission;
AppleScript is used only to read the starting state and control playback (Automation permission). No
beat detection: a fixed 112 BPM, a bounce and sway blended into the pose with a level that fades in
and out. Left out of Coucou's App Store build; whether a sandboxed app still gets the notifications is
unverified ([#108](https://github.com/serpcompany/tomodachi-app/issues/108)).

**On the desktop** (Coucou, `DesktopMochi*.swift`, with tests). Dragging the head out of the notch
promotes a ghost panel to a floating, non-activating, all-Spaces panel; click-through except over the
character; gaze in one y-down space across all displays; sleeps when ignored, at a lower frame rate;
position saved and clamped to a screen; a phase machine for flying out, back home, and back to the
notch when something needs you. Ours measures gaze in the island screen's space
(`IslandWindowController`), fine in the notch but wrong for a Tomo on another display.

**Choreographed moments.** Coucou's greeting is a pose computed purely from time, out of eased
segments, so it can be scrubbed and cut short. dotpals runs a reaction as a script of timed cues on a
channel; a newer script cancels the old one and still closes what it opened. Tomo's level-up and
birthday are a few overlapping moves today.

**Small touches** (dotpals). Rest the pointer on the pal for 2 s and it falls in love (at most every
20 s). Eyes narrow as they turn sideways (Tomo narrows its cheeks, not its eyes). Star and heart eyes.
A glow per state, amber and pulsing while waiting. Every move honours `prefers-reduced-motion`: the
face still changes, the body doesn't move.

**The notch** (dotpals, `bridge/ui/notch-state.js`). Modes (hidden, peek, bar, open) as a pure reducer
with tests; a notch you opened closes 8 s after the pointer leaves, with a shrinking countdown line; a
spider pal drops out of the island on a thread when something needs you.

## The issues

| Issue | Where | Size |
|---|---|---|
| [#112](https://github.com/serpcompany/tomodachi-app/issues/112) Tomo moves gently when Reduce Motion is on | TomoCore | small |
| [#113](https://github.com/serpcompany/tomodachi-app/issues/113) Ears flop when poked, a blush when you rest the cursor, eyes that turn | TomoCore | small |
| [#114](https://github.com/serpcompany/tomodachi-app/issues/114) Tomo dresses up for Japanese holidays and seasons | TomoCore | medium |
| [#115](https://github.com/serpcompany/tomodachi-app/issues/115) Tomo earns something to wear as it levels up | TomoCore, sync | medium |
| [#116](https://github.com/serpcompany/tomodachi-app/issues/116) Level-ups and birthdays as one choreographed moment (helps [#87](https://github.com/serpcompany/tomodachi-app/issues/87)) | TomoCore | medium |
| [#117](https://github.com/serpcompany/tomodachi-app/issues/117) Visits drip out of the notch, with a countdown line and a glow | Mac, TomoCore | medium |
| [#118](https://github.com/serpcompany/tomodachi-app/issues/118) Drag Tomo out onto the desktop | Mac | large |
| [#119](https://github.com/serpcompany/tomodachi-app/issues/119) Tomo bops along when music plays | Mac, TomoCore | medium |

Suggested order: #112 and #113 first (small, every learner sees them), then #116 with #87, then #114.
Desktop mode is the biggest change to how Tomo lives on the Mac; prototype it before polishing.

Not taken: dotpals' build-your-own pal (Tomo is seeded, not chosen), a dot-matrix look (nothing to gain
over Tomo's own drawing), and the agent-monitoring features (Tomodachi isn't a dev tool). How these
apps (and others) use the notch itself is in [notch-ideas.md](notch-ideas.md).

## Sources

- Coucou at `c946650`: `CHANGELOG.md`, `LICENSE-ASSETS.md`, `NotchBuddy/Sources/CoucouKit/`
  (`MochiOutfitDrawing`, `MochiWardrobe`, `BotEngine`), `NotchBuddy/Sources/App/` (`DesktopMochi`,
  `DesktopMochiLogic`, `GreetingCanvasView`, `MusicController`, `SpotifyController`), `tests/`,
  `windows/src/` (the TypeScript port)
- dotpals at `2ddc2ed`: `LICENSE`, `THIRD_PARTY_NOTICES`, `src/element.js` (`gazeFor`, `foreshorten`,
  `#armStill`, `#getDizzy`, `#run`), `src/actions.js`, `src/characters.js`, `src/custom.js`,
  `bridge/ui/notch-state.js`
- Not run: neither app was built or launched; behaviour comes from reading the source.
