# Research: blobatar for a one-of-a-kind Tomo

Checked 2026-10-07 against blobatar 2.7.0 (`github.com/Alain00/blobatar`, last commit 2026-09-07) and two
Swift ports. Question: can [blobatar.dev](https://blobatar.dev) give each learner a Tomo that's unique to
them, and can it animate in the notch? ([#84](https://github.com/serpcompany/tomodachi-app/issues/84))

## Answer

**Outcome:** the owner chose to replace the chick with the blob after all, keeping our own faces and
moves, evolving at every birthday, and showing a fixed mascot on widgets
([decisions.md](../decisions.md), 2026-10-07). The research below is as it was written.

Blobatar can run in the notch technically, but it would replace Tomo rather than make Tomo unique. Don't
adopt its look. Take its **method** instead: hash a seed made once, at hatching, into a few traits of
our own chick's drawing, so every Tomo is still a chick but no two look alike.

- **What it is:** a small MIT library that turns any string into a "blob": one of 10 silhouettes (round,
  organic, boxy, nub, cloud, sun, capsule, triangle, hexagon, droplet), a colour, and two bar eyes. No
  mouth, beak, limbs or body parts. The same string always gives the same blob. It has 14 expressions
  (happy, sad, sleepy, love, thinking…), all made with the eyes, plus idle motion (breathe, bob, blink,
  glance) and eyes that follow the cursor.
- **Notch, technically:** yes, without a WebView. The JS version outputs SVG, and its motion is a CSS
  stylesheet, so that version would need a WebView. But two MIT Swift ports draw it natively in a SwiftUI
  `Canvas` driven by a `TimelineView`, the same way `TomoChick` is drawn:
  `jasonkneen/blobatarKit` (about 3,900 lines, macOS 14 / iOS 17, follows the cursor, honours Reduce
  Motion) and `RayZhao1998/BlobatarSwift` (about 1,250 lines). Both are a few weeks old, with 4 stars
  and 1 star, and one maintainer each.
- **Notch, as a product:** no. A blob is an avatar meant for a 32–48 px chat list. Our chick has a
  body, belly, wings, feet, beak, tuft and an eggshell, and 11 faces and 14 moves (hop, flap, peck,
  preen…). Those are the hatching story ([decisions.md](../decisions.md): "Tomo is a hiyoko"). A blob has
  nothing to hatch out of, no wings to flap, and no beak to talk with.

## What a blob looks like

Rendered from blobatar 2.7.0 for 16 short names, then one name with happy, sleepy, surprised and love:
flat single-colour shapes with two short eye bars. The expressions differ only in the eyes and are hard to
tell apart at notch size. The range is wide (shape × hue × tone), but every one reads as "a coloured
pebble with eyes."

## How it makes each one unique

This part is worth copying. The design is in `packages/blobatar/src/hash.ts` and `traits.ts`:

1. **One seed, normalised:** NFC, trimmed, lowercase.
2. **A hash with avalanche:** murmur3's finaliser, so "alain" and "alaim" look unrelated.
3. **Traits by name, not by order.** Each value is read by its own key (`"hue"`, `"eye.gap"`,
   `"body.r"`), so a new trait added later doesn't change existing ones. That's what lets the look grow
   without anyone's Tomo changing overnight. (Changing a choice list does change them; blobatar freezes
   those per "generation".)
4. **Bands for rarity:** a 0–1 value split into weighted ranges, so common shapes are common and a
   "sun" is a rare find.
5. **Overrides** (`traits: { hue: … }`): pin any trait. That's how we'd let the learner re-roll or
   choose, or keep a brand colour.
6. **Readability rules:** every colour meets 4.5:1 contrast, and eyes always stay inside the body.

About 40 trait keys drive the blob. A Swift version of steps 1–5 is around 100 lines.

## What a seeded Tomo would vary

Tomo's colours are fixed today (`Palette` in `TomoCharacter.swift`, all yellows). Candidates, each a
trait key with a range our drawing can stay cute across:

| Trait | Example range | Notes |
| --- | --- | --- |
| Body hue | a narrow warm band (yellow → peach → cream), plus a rare far hue | Stays a hiyoko; a rare blue or pink chick is the "sun" of our set |
| Tuft | 1–5 feathers, curl, lean | Already drawn in `drawTuft` |
| Cheeks | colour, size, freckles | |
| Eyes | size, spacing, highlight | Must keep every face (wink, dizzy, love) readable |
| Shell | spots, stripes, zig-zag crack | The 1さい look, so it's the first thing a learner sees |
| Body | squash and roundness | Small range, so the moves still fit |
| Motion | blink rate, idle phase, fidget mix | Blobatar seeds its motion too, so a room of blobs doesn't move in unison |

The rarity bands matter for the "hatching" moment: an egg that might hatch a rare chick gives the
learner a reason to look.

## What it would touch

- **The seed:** a random ID made once, the first time Tomo appears, saved with Tomo's state. It must sync
  through iCloud so the Mac and iPhone show the same Tomo
  ([#62](https://github.com/serpcompany/tomodachi-app/issues/62)). Don't seed from an email or Apple ID:
  that's personal data and it can't be re-rolled.
- **The drawing:** `Palette` and the shape constants become a value built from the seed and passed to
  `TomoChick`. Nothing else in the seam changes: notifications and `TomoGame.onBotState` still drive it.
- **Widgets and Live Activities:** the hard part. There Tomo moves through fonts of pre-rendered frames
  (`TomoMovingChick`, made at build time by `ios-demo/scripts/make-frame-font.py`; decisions.md
  2026-10-06). A font is bundled, so it can't be built per learner at run time. Options: a small fixed set
  of looks, each with its own font (for example 8 colours), with the widget using the nearest one; or the
  widget keeps the default chick. Decide this before building, because it limits how many traits are
  worth seeding.
- **The snapshot matrix** ([verification.md](../verification.md)) would need a few fixed seeds, so a
  change to the drawing shows up on known Tomos and not just the default.

## If we did want the blob itself

Not recommended, but here's what it would take: add `BlobatarKit` (Swift Package, MIT; keep its licence
and blobatar's in the credits), seed it with the hatch ID, and map Tomo's states to its expressions
(`.finished` → happy, `.question` → thinking/unsure, sleeping → sleepy, love → love). We'd lose the
eggshell, the hatching, wings, beak and most moves, and we'd depend on a port with one maintainer. It
also bends "Tomo is drawn and animated live in our own code" ([decisions-2026-10-05.md](../decisions-2026-10-05.md)): it's live, but
it isn't ours.

## Sources

- blobatar repo, README, `CONTEXT.md`, `packages/blobatar/src/{hash,traits}.ts`: github.com/Alain00/blobatar
- blobatar.dev (landing page, editor, `/avatar/<name>` endpoint)
- BlobatarKit: github.com/jasonkneen/blobatarKit; BlobatarSwift: github.com/RayZhao1998/BlobatarSwift
- Other ports found: Flutter (official, in the repo), Rust, Angular, a Tauri desktop pet ("winpet-blobatar")
