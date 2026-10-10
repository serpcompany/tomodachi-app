# Tomo's design pages

Our own prototype pages for Tomodachi's UI and UX, saved here so they last and any agent can open them.
Each is one HTML file: open it in a browser and play its flows. The live pages, where the owner comments,
are on claude.ai (linked below). The Comment buttons only work there.

They're prototypes, not specs. Tomo in them is a JavaScript port of `TomoLook.swift` and
`TomoCharacter.swift`; the real Tomo stays in Swift. Pick a direction with the owner before building, one
item per PR, and keep the rules: Tomo is always alive, no growing count of things to do (2026-10-11: guilt, red and
streaks are fine now, whatever a page says), the Mac card's fixed grid, text in the language packs, and room for several friends. Where each idea is tracked:
[#137](https://github.com/serpcompany/tomodachi-app/issues/137) ("Design references").

## Kept for later, not only the picks

Nothing here is thrown away when one direction is picked. What isn't built first stays a reference to
build on later, for example the other materials as other friends' materials.

| Page | What it holds | Status (2026-10-11) |
|---|---|---|
| [motion-directions.html](motion-directions.html) ([live](https://claude.ai/artifact/2yQ2egcHpdsBk2BFrKZaa2)) | Four materials for Tomo: jelly, lit clay, paper cut and lantern, each with its hello, travel into the card, win, level-up and Reduce Motion. #137 item 3 | Good. Jelly built first, as the learner's Tomo's material (`TomoMaterial`). The others wait, as other friends' materials |
| [stats-take-two.html](stats-take-two.html) ([live](https://claude.ai/artifact/D2Ux73JFUTqGfJNy5a4PsG)) | Four screens that aren't dashboards: Tomo's diary, the word garden, a height pillar for growing up, a weekly postcard. #137 item 2 | Good. All four, in stages: the weekly postcard is built first ([stats.md](../../stats.md)), then the garden, the pillar and the diary |
| [friends-take-two.html](friends-take-two.html) ([live](https://claude.ai/artifact/UuGM6u95BqPm71AW3Kvtus)) | Four ways several friends could work: the relay, playdates, little siblings, eyes in the dark, each answering the open friend questions | Good. The core rules come first, as a decision |
| [make-your-own-tomo-take-two.html](make-your-own-tomo-take-two.html) ([live](https://claude.ai/artifact/FWzSyBertikff6bwoXLx78)) | Four ways to make your own Tomo. #137 item 1 | Concept C chosen (pick an egg by ear); A, B and D rejected. An idea for later: not being built yet |
| [coucou-ideas-lab.html](coucou-ideas-lab.html) ([live](https://claude.ai/artifact/Pv7i26ZDGPixpRjTeM83b3)) | Eight ideas from Coucou's Mac and iPhone screens, each Today vs Proposed. [#144](https://github.com/serpcompany/tomodachi-app/issues/144) | Waiting for the owner's review |
| [decision-lab.html](decision-lab.html) ([live](https://claude.ai/artifact/H4Ecb2dVkpKH4jNPFuWq5J)) | The first designs for stats, the iPhone and friends | Rejected; kept so they aren't redone |

Earlier pages, linked only: the [Tomo Proposal Lab](https://claude.ai/artifact/BLWWHme5xiP98KBp2xqqqm)
(#130's prototype) and the [Tomo Motion Lab](https://claude.ai/artifact/PUvCqMaRixoNkaPfte3Fkf).

To add a page: save its HTML here under a kebab-case name, add its row, and link it from the issue it
serves. When the owner picks or rejects a direction, update its row.
