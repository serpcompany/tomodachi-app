# Tomo's character

How Tomo the blob is drawn, moved and hosted: its look, what it's made of, its big moments, and the inputs its hosts
give it. The systems around it are in [architecture.md](architecture.md); what a learner sees is in
[concepts.md](concepts.md) ("Own character").

## The blob

`TomoBlob` in `TomoCharacter.swift` (TomoCore): a blob drawn every frame in code. Its time comes from a clock, so it can
be rendered offline. It's driven by notifications (`.botGrow`, `.botLevelUp`, `.triggerEmote` and others, in
`TomoSignals.swift`) and Tomo's state (`TomoGame.onBotState`), never called directly, so any screen can host it:
`TomoBlobView` on the iPhone, `TomoLiveAvatar` on the screens, `TomoCharacterView` in the island. TomoBlobView and the
island draw on a canvas wider than their frame, so ears and toppers that reach past Tomo's sides (a droopy Tomo's flop
out) are never cut off; `TomoBlob.feelingSelfTest` renders every age to check they fit (`TomoBlobView.sideRoom`).

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
another script, or while Tomo is away. A moment's particles are its own steps: a level-up's sparkles and sparkle dust,
a birthday's drops and confetti in Tomo's own colours (`confettiColor`: its body, lighter top, markings and cheeks).
Each lives 2 s at most and all are gone when the moment ends; under Reduce Motion there are a third, slower.
At a birthday the new form comes at once and its outline flows out of the old one (`TomoFormMorph`, TomoMorph.swift):
a port of [flubber](https://github.com/veltman/flubber) on the states lab's Flubber timing (1.2 s, springing past the
new outline and settling), and under Reduce Motion a 0.9 s crossfade. Its function of two forms and a progress works
for any change of shape. The morph is Tomo's, not the script's: a newer script doesn't stop it. Planned: evolution that reads as growing up, as cue scripts
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
- A ceiling (`ceiling`): the island without a notch sets its top edge, a point inside. A form too tall to stand under
  it, with its topper, its idle stretch and a hop, is drawn smaller, standing and moving as it does.
- The season's weather (`weather`, from the target language's calendar, `TomoCalendar.weatherToday`): the island
  passes it only to Tomo's card (`TomoCharacterView.weather`), and the Mac's Tomo screen to its Tomo. A few flakes or
  petals fall behind Tomo, worked out from the clock, so nothing is emitted; under Reduce Motion, a third, slower.
- Dancing to music (`dance`): the island turns it on while Music or Spotify plays and small Tomo rests, outside quiet
  hours (`TomoCharacterView.dance`; the players' own notifications, `TomoMusic`). Tomo's own bounce and sway at 112
  BPM, or the 盆踊り side-step at half speed on the days the language's calendar says (`TomoCalendar.danceToday`). A
  loop on the clock, not a script: it fades in and out, a script takes over while one plays, and it's off under Reduce
  Motion.
- A feeling over its own look (`feeling`, `TomoFeeling.swift`): droopy (it sags wider and lower, its ears and topper
  flop, it looks at the floor, breathes slower and sighs every 5 to 7 s), sickly (a green-grey tint, a little smaller,
  heavy worried lids, a sweat drop, quick shallow breaths and a shiver) or mossy (asleep and curled up, breathing deep
  and slow with Zz drifting up, while moss grows over its top in about 3 s, in patches from its seed, crown first, and
  then a sprout that sways). Only the Testing menu sets it for now
  (`TomoGame.feeling`, or `TOMO_FEELING` at launch), and every live host passes it on; nothing ties it to progress yet
  ([#262](https://github.com/serpcompany/tomodachi-app/issues/262)). It eases in and out over about a second, and back
  to well Tomo gives a small happy hop; from mossy it shakes the moss off instead, in a puff of spores (`brushCue`, a
  cue script). Droopy slumps a birthday's morph too, frame by frame, so nothing pops as it starts or ends. Under
  Reduce Motion the sigh, the shiver and the brush-off's shake become a puff, and the sprout stands still. Its colour
  is a pass over the look, never a new look: its seed, age and form stay. The look the feeling copies is
  [the states lab](reference/tomo/states-lab.html) (Posture, Ill and Patches).
- Back in its egg (`inEgg`, `TomoEgg.swift`, [#258](https://github.com/serpcompany/tomodachi-app/issues/258)): Tomo
  curls up and the first run's egg, speckled in its colours, closes round it (`intoEggCue`); there it rests, rocking
  now and then and peeking out every 4 to 6.5 s, and a poke wobbles it and makes it peek. Set back to false, it hatches
  as the first run's egg does (`hatchCue`): the egg shakes as its crack runs across, the halves part behind Tomo in a
  few sparkles (solid, the top tumbling off to the side and both sinking into the floor, fading only in their last
  0.1 s, so no see-through shell greys a dark card), and Tomo springs out saying `hatchWord` (the target pack's hello, which the host passes in; ばあ！ in
  Japanese). It comes out as it went in: its seed, age, form and feeling stay. Under Reduce Motion Tomo fades into the
  egg and out of it with a glow and star eyes. In its egg it wears no badge or question mark and doesn't doze or say hello; a big moment
  that comes then plays behind the shell, only its particles showing. The halves stay in Tomo's room (`eggRoom`): its
  frame, under a ceiling. Only the Testing menu sets it for now (`TomoGame.inEgg`; `TOMO_EGG` and `TOMO_HATCH`), and
  the first run's hatch sounds play as the hatch starts (`onHatch`). The look is the states
  lab's Shell on the first run's egg, which `TomoEggView` draws with `TomoEgg` too.
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
- A birthday's morph always lands on the new form, whatever plays over it; jumping straight to an age ends it at once
  (`TomoBlob.morphSelfTest`). No morph between any two shapes tangles, flips or spins (`TomoFormMorph.selfTest`, and
  for all eight render seeds `TOMO_RENDER_EVOLUTION`).
- TomoBlob never reads a system setting or the game, or picks its own material.
- A seed always gives the same Tomo.
- `classic` never changes, because the frame font is rendered from it: a new look is a new material.
- A material's pass is fixed fills: no blur or particles at rest, so a Tomo at rest costs what it did.
- No material moves Tomo under Reduce Motion (`TomoBlob.motionSelfTest` runs every material).
- A badge says what Tomo is doing, never how many of anything (`TomoBlob.Badge`).
- Under a ceiling, nothing it draws at rest or in its idle moves reaches past it (`TomoBlob.ceilingSelfTest`, rendered on
  macOS, where the island is).
- Nothing emits at rest: particles come only with moments, and the weather never reaches the resting island
  (`TomoBlob.particleSelfTest`).
- A feeling never changes who Tomo is: its seed, age and form stay, it emits nothing (its sweat drop, moss and Zz are
  drawn from the clock), and well is drawn exactly as before (`TomoBlob.feelingSelfTest`, `TomoBlob.mossSelfTest`,
  `TomoFeeling.colourSelfTest`).
- Tomo comes out of its egg as it went in: its seed, age, form, colours and feeling, for every look, age and feeling,
  under Reduce Motion too. In its egg it emits nothing at rest, and the egg fits the island's sides and ceiling
  (`TomoBlob.eggSelfTest`).
