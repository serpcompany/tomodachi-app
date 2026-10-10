# Tomo's character

How Tomo the blob is drawn, moved and hosted: its look, what it's made of, its big moments, and the inputs its hosts
give it. The systems around it are in [architecture.md](architecture.md); what a learner sees is in
[concepts.md](concepts.md) ("Own character").

## The blob

`TomoBlob` in `TomoCharacter.swift` (TomoCore): a blob drawn every frame in code. Its time comes from a clock, so it can
be rendered offline. It's driven by notifications (`.botGrow`, `.botLevelUp`, `.triggerEmote` and others, in
`TomoSignals.swift`) and Tomo's state (`TomoGame.onBotState`), never called directly, so any screen can host it:
`TomoBlobView` on the iPhone, `TomoLiveAvatar` on the screens, `TomoCharacterView` in the island.

## Its look

A `TomoLook` (`TomoLook.swift`) hashed from a seed: a colour and eyes for life, and a form for each age (silhouette,
size, details) that changes at every birthday. The learner's look is `TomoLook.current`, which `TomoGame` sets from the
saved Tomo; the seed is the language pair and the second the Tomo first appeared, which is already synced, so every
device draws the same Tomo. Places that can't draw it live (widgets, Live Activities, the icons) show
`TomoLook.mascot`. Trait keys can be added freely, but changing a range, a band or a list changes every learner's Tomo
(`TomoLook.selfTest`). `TomoLook.variety` scales how different Tomos are.

## What it's made of

A `TomoMaterial` (`TomoMaterial.swift`): the pass over its body, its springs and its hello. The host passes it in with
the look, and TomoBlob keeps it for life.

- **Jelly** (`TomoMaterial.own`, the learner's own Tomo): wet, glossy and lit from inside (a light rising from its
  bottom, an inner rim and two highlights), on loose springs that overshoot and wobble. The amber call and a moment's
  light glow from inside it. Its hello is a drop that falls from the notch and gathers into Tomo.
- **Classic**: Tomo as it was before #137. The mascot and what ships as files (the widgets' and the Live Activity's
  frame font, `TomoBlobStill`, the icons) use it.
- **Later:** #137's other directions (lit clay, paper cut, lantern;
  [motion-directions.html](reference/tomo/motion-directions.html)) would each be a case, with its own pass, springs and
  hello, for other friends (decisions.md, 2026-10-11).

## Big moments, arrivals and the hello

Big moments (a level-up, a birthday, becoming another Tomo), arrivals (dripping in from the notch on a goo strand,
pulled back up into it) and the hello (`hello`) are **cue scripts** (`Cue`): one timeline each, as data, played on
Tomo's clock. While one plays it owns Tomo's body, face and particles, so what the game sends with it adds nothing; a
newer one replaces it, and first closes what the old one opened (its pending shape swap). A hello never plays over
another script, or while Tomo is away. Planned: evolution that reads as growing up, as cue scripts
([#87](https://github.com/serpcompany/tomodachi-app/issues/87)).

## What its hosts pass in

- Its look and its material, at creation.
- Where the notch is (`strandAnchor`), for the strand and the hello's drop, and how strongly small Tomo glows amber to
  ask to play (`callGlow`, 0…1).
- Whether it wears its badges (`showsBadges`): the island turns them on while Tomo rests small beside the notch
  (`TomoCharacterView.wearsBadges`), and its canvas reaches past its frame on the right, where the badge sits
  (`badgeRoom`, `TomoBlob.badgeFrame`). The badge is what Tomo is doing (`badge`): a "…" thought bubble while it checks
  an answer (`.thinking`), a tiny Zz while it dozes or sleeps; none while a script plays or Tomo is away. Wearing them,
  its z's don't drift. Elsewhere (the card, the peek, the iPhone) its face and drifting z's say it.
- When it says hello: the island the first time Tomo shows after launch, greeting the launch visit's card instead of
  dripping into it, and when the Mac wakes (`TomoCharacterView.saysHello`); the iPhone's play screen when it first
  appears.
- Reduce Motion (`TomoBlob.reduceMotion`): each shell sets `TomoMotion` from the system (`NSWorkspace` on the Mac,
  `UIAccessibility` on the iPhone) and follows changes, and every live host passes it on. Then hops, shakes and wiggles
  become a face and a small puff, a cue script plays its calm version (a glow, star eyes and a puff; an arrival fades in
  or out where Tomo sits; the hello fades in with its light), the call glow holds steady, badges show without bobbing,
  and particles are fewer and slower. Offline renders leave it off, so they never depend on the Mac that renders them (`TOMO_REDUCE_MOTION=1` turns
  it on); widgets and the Live Activity play their frame font regardless.

## Invariants

- Idle life never stops: under Reduce Motion it still breathes and blinks, and a birthday still changes its shape.
- A cue script's shape swap always happens, even when a newer script replaces it or nobody saw it play.
- TomoBlob never reads a system setting or the game, or picks its own material.
- A seed always gives the same Tomo.
- `classic` never changes, because the frame font is rendered from it: a new look is a new material.
- A material's pass is fixed fills: no blur or particles at rest, so a Tomo at rest costs what it did.
- No material moves Tomo under Reduce Motion (`TomoBlob.motionSelfTest` runs every material).
- A badge says what Tomo is doing, never how many of anything (`TomoBlob.Badge`).
