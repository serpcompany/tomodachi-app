# Changelog

release-please writes this file from the squash commits on `main`, one entry per release, when its release PR
merges. Only `feat:`, `fix:`, `perf:` and `refactor:` titles show here. The Mac app's version is this version;
the iPhone's is the App Store's, set by hand ([docs/decisions.md](docs/decisions.md)).

## [0.2.2](https://github.com/serpcompany/tomodachi-app/compare/v0.2.1...v0.2.2) (2026-10-11)


### Fixes

* **ios:** at the largest text, the word in Words grows with it and the Tomo screen wraps between phrases, never inside one ([#241](https://github.com/serpcompany/tomodachi-app/issues/241)) ([912896a](https://github.com/serpcompany/tomodachi-app/commit/912896a8f61edf572bff9e29cfff18459a8f8037))
* **mac:** each Words stage looks different in light mode, stepping from a pale fill to a solid one ([#238](https://github.com/serpcompany/tomodachi-app/issues/238)) ([5d31e4d](https://github.com/serpcompany/tomodachi-app/commit/5d31e4da738b9bd6fedfcb785b18c4d5edcf4e70))
* **mac:** the window's snapshots show the selected sidebar row's label in light mode ([#243](https://github.com/serpcompany/tomodachi-app/issues/243)) ([e8a0cbe](https://github.com/serpcompany/tomodachi-app/commit/e8a0cbe13a34a36bc5deda41c092883da7058bb0))
* Tomodachi stays in English while you learn Japanese, and a Japanese setup from before keeps its Tomo ([#240](https://github.com/serpcompany/tomodachi-app/issues/240)) ([6b60c32](https://github.com/serpcompany/tomodachi-app/commit/6b60c320dfa368efe635c88b96df318ac1dbe465))

## [0.2.1](https://github.com/serpcompany/tomodachi-app/compare/v0.2.0...v0.2.1) (2026-10-11)


### Fixes

* a resting Tomo says what its second time is, the stats export follows your 12- or 24-hour clock, the pillar's coming ages match the reached ones, and the garden summary keeps numbers and dates whole ([#211](https://github.com/serpcompany/tomodachi-app/issues/211)) ([d428478](https://github.com/serpcompany/tomodachi-app/commit/d4284785a74b0987b6ea1f6cd7cfb3babb2cca64))
* Debug builds are their own app, "Tomodachi Debug", so a test run never touches the owner's Tomo ([#221](https://github.com/serpcompany/tomodachi-app/issues/221)) ([70e1cad](https://github.com/serpcompany/tomodachi-app/commit/70e1cadd6e72b564adc0221954aaf0b97290b376))
* **ios:** a Daily reminder comes at 8 AM when quiet hours are off, never at midnight ([#222](https://github.com/serpcompany/tomodachi-app/issues/222)) ([0488531](https://github.com/serpcompany/tomodachi-app/commit/0488531e6fcdf38797bec82e3d741feda064acfe))
* **ios:** the Lock Screen card and Dynamic Island say Tomo wants to play when the app does, and give the app's own "Back at" time on your 12- or 24-hour clock ([#202](https://github.com/serpcompany/tomodachi-app/issues/202)) ([ac48589](https://github.com/serpcompany/tomodachi-app/commit/ac48589d7c44457a3f48a3086047941e914f9dee))
* **ios:** the tabs' bar hides what scrolls under it, and Words opens with the current level's header and first word in view ([#206](https://github.com/serpcompany/tomodachi-app/issues/206)) ([7d22312](https://github.com/serpcompany/tomodachi-app/commit/7d22312ab6750c8c9a7cd63c974d713d3345e15d))
* **ios:** Together fits the phone at the largest text sizes, and its Today line wraps between phrases ([#229](https://github.com/serpcompany/tomodachi-app/issues/229)) ([0fcd6ee](https://github.com/serpcompany/tomodachi-app/commit/0fcd6eeb23418922687891782c088da5dd4d9ff9))
* **mac:** opening a word's help keeps the card in place, and its Mac dictionary is in your language ([#205](https://github.com/serpcompany/tomodachi-app/issues/205)) ([e1ac5d5](https://github.com/serpcompany/tomodachi-app/commit/e1ac5d5c40f16f1a653691d6774e01d83ddc1ce2))
* **mac:** run.sh quits only the owner's copy, never a Debug build or an agent's test run ([#181](https://github.com/serpcompany/tomodachi-app/issues/181)) ([f04ba20](https://github.com/serpcompany/tomodachi-app/commit/f04ba2018e74714a05e37927ec8f8285c46f06ca))
* **mac:** the folding card, Tomo's landing and small Tomo's sprout stay inside the island, and a gloss breaks between its reading and meaning ([#219](https://github.com/serpcompany/tomodachi-app/issues/219)) ([2e8cac3](https://github.com/serpcompany/tomodachi-app/commit/2e8cac322d9d95a012621e2f03f3f5bec12f611d))
* **mac:** the Words stage chips and badges read in light mode ([#217](https://github.com/serpcompany/tomodachi-app/issues/217)) ([34aa06e](https://github.com/serpcompany/tomodachi-app/commit/34aa06ed7c96fa8d54617deb3cdaefac5c47e936))
* the diary's page for today says the same "Day N together" as the Tomo tab ([#228](https://github.com/serpcompany/tomodachi-app/issues/228)) ([f29be0d](https://github.com/serpcompany/tomodachi-app/commit/f29be0d7f6f02ac73342629d5d4a1570dbef0d2f))
* the first run shows quiet hours that are off as off, on your own 12- or 24-hour clock, and stops promising no streaks ([#201](https://github.com/serpcompany/tomodachi-app/issues/201)) ([35f80fb](https://github.com/serpcompany/tomodachi-app/commit/35f80fb27e45ddba0b5c9b11ead410f3772c33eb))
* the iPhone app, its widgets and the Mac app declare their privacy manifests, so App Store uploads pass Apple's required-reason check ([#232](https://github.com/serpcompany/tomodachi-app/issues/232)) ([57eb68e](https://github.com/serpcompany/tomodachi-app/commit/57eb68edb00d79d464229aa6b51bb61d41333000))
* the iPhone's notifications step stops promising no streak guilt, Japanese headings break between phrases, and the widget says "Tomo" ([#226](https://github.com/serpcompany/tomodachi-app/issues/226)) ([8bb82b5](https://github.com/serpcompany/tomodachi-app/commit/8bb82b5b0b122c60483d7e4f1e87830b99f6378b))
* the Words badges, a dark picture and two controls read in light and dark mode ([#204](https://github.com/serpcompany/tomodachi-app/issues/204)) ([e90f9cf](https://github.com/serpcompany/tomodachi-app/commit/e90f9cf2b3936be333058ea959f138329fdd106e))
* VoiceOver hears Tomo's love for 6 s, and the long-press and confetti checks stop failing by chance ([#215](https://github.com/serpcompany/tomodachi-app/issues/215)) ([16e7954](https://github.com/serpcompany/tomodachi-app/commit/16e7954bd7c67d58e9998b9ed749f98164b1237c))
* Words lands on Tomo's level whenever it shows, even when you switch to it, and lets go at your first scroll ([#223](https://github.com/serpcompany/tomodachi-app/issues/223)) ([a33c0ba](https://github.com/serpcompany/tomodachi-app/commit/a33c0bade7b5d17aac22de596ad3fd60b79356b0))

## [0.2.0](https://github.com/serpcompany/tomodachi-app/releases/tag/v0.2.0) (2026-10-11)

The jelly and garden build, the first tagged version. It was tagged by hand, as release-please's starting point;
its notes are in [the v0.2.0 release](https://github.com/serpcompany/tomodachi-app/releases/tag/v0.2.0).
