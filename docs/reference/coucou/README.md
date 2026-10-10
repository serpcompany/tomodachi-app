# Coucou design reference

Coucou's own screens, character states, prototypes and demo videos, kept as design reference for
Tomodachi's UI and UX. They are Coucou's, not ours: look, learn the technique, then draw Tomo's own
version. The prototype brief is [#144](https://github.com/serpcompany/tomodachi-app/issues/144).

## License boundary

Copied from [Louis-CFM/coucou](https://github.com/Louis-CFM/coucou) at commit
[`eaee949`](https://github.com/Louis-CFM/coucou/tree/eaee949bde4568b8b51514731ec10bc7c639a0d3)
(2026-10-10), plus the iPhone promo video the owner shared on
[Clipy](https://clipy.online/video/1g2demfyo4o3). Coucou's
[LICENSE-ASSETS.md](https://github.com/Louis-CFM/coucou/blob/main/LICENSE-ASSETS.md) reserves every
file here: the Mochi character, its expressions and animations, and the media in its `design/` and
`docs/media/`. It allows showing and reviewing them, which is all this folder is for.

- Never ship, trace or bundle these files, and never copy Mochi's look into Tomo.
- Adapting Mochi's outfits or animations waits on the author's written yes
  ([#109](https://github.com/serpcompany/tomodachi-app/issues/109)). Until then: technique only.
- What we already took from Coucou's code is in [coucou-fork.md](../../coucou-fork.md).

## What's here

| Folder | What it shows |
|---|---|
| [video/](video/) | `iphone-demo.mp4` (27 s): the iPhone companion app, approvals behind Face ID, messaging a session, widgets, Lock Screen and Live Activity. `mac-demo.mp4` (57 s): the notch from idle through work, a diff, a dashboard, chat, a file drop, upload, mail and the rate-limit card. |
| [iphone/](iphone/) | Stills of the iPhone app: approval, Live Activity, a session, widgets. |
| [captures/](captures/) | `01`–`16`: each notch screen (peek, compact, overview, approval, question, error, finished, confused, drag-over, uploading, choose, mail, prompt window, searching, result, empty). `char-state-*` and `char-emote-*`: one picture per character state and emote. `mac-*`: the README's Mac screenshots. `no-notch-*`: Macs without a notch. `outfits-sheet.png`: the outfit sheet. |
| [prototypes/](prototypes/) | Coucou's HTML prototypes: the whole notch (`notch-buddy.html`), the greeting and the upload sequence. Open them in a browser to see the motion. |
