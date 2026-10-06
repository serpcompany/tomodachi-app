# Decisions

Newest first. Add an entry when a direction is chosen. Keep the reason, so later sessions don't reopen it by accident.

### 2026-10-06: The iPhone app ships on the team Pedos uses
The iPhone app signs with team `W3GXL2NQQP` and is on App Store Connect as **Tomodachi: Language Companion** (bundle ID `com.zenbujapanese.tomodachi`; plain "Tomodachi" was taken). The Mac beta is still Developer ID–signed on team `847HR8U8D9`. **Why:** the owner chose the team that already ships Pedos, and it's the one Xcode is signed in to. Syncing Mac and iPhone through iCloud (#62) needs both apps on one team, so the Mac app will have to move to `W3GXL2NQQP` first.

### 2026-10-06: Looking up a word while it's asked counts as the hint
Opening a word card (Mac or iPhone) while Tomo is asking that word shows its meaning, so a right answer after it doesn't move the word up, like after the hint. **Why:** otherwise the word card is a free answer key.

### 2026-10-06: On widgets and Live Activities, Tomo moves through a font of its own frames
On the Home Screen, the Lock Screen and in the Dynamic Island, Tomo is a timer counting seconds, set in a font whose digits are ten frames of Tomo (`TomoMovingChick`). Only the last digit shows, so Tomo changes pose once a second and loops every ten seconds: asking (look around, blink, hop, smile, peep, wink) when something waits, asleep with drifting z's otherwise. The frames are rendered from Tomo's own drawing code (`TOMO_RENDER_CARD_FRAMES`) and packed into fonts by `ios-demo/scripts/make-frame-font.py`; nobody draws them by hand. This replaces the earlier "Tomo shown still" exception. **Why:** iOS widgets and Live Activities can't run their own animation, and only keep timer text ticking; the owner wanted Tomo visibly alive there. It bends "no sprite sheets" for these surfaces only, because the frames are generated from the same code. Tested on iOS 27: custom fonts need a PostScript name, a timer clips to its last digit only inside a wider right-aligned frame (`.fixedSize()` hides it), and bitmap (`sbix`) glyphs draw in color.

### 2026-10-06: Tomodachi stays its own iPhone app for now
Tomo on the iPhone is a separate app (`ios-demo/`, `com.zenbujapanese.tomodachi`), not a part of the Zenbu Japanese app. Its views live in `TomoCore` where they can, so moving it into the Zenbu app later stays cheap. **Why:** Tomo is still proving itself, and the Zenbu app is shipped; the owner chose to keep them apart and revisit (the Zenbu app has the dictionary, Sudachi and Known Words that #6, #9 and #28 want).

### 2026-10-06: 3さい questions are multiple choice for now
Tomo's talking questions are asked with three choices: what the line means (new questions), or a reply that fits (reviews, alternating with the meaning). Wrong replies come from other questions, never this question's own answers. Typing or saying an answer is switched off (`TomoGame.talkAsChoices`), not deleted. **Why:** the owner tried typing at 3さい and translated the question into English, which scored nothing; free answers need clear instructions, a Japanese keyboard and AI to judge them. Choices work offline and still check understanding.

### 2026-10-06: Romaji answers count as Japanese
An answer typed in romaji ("shigoto shiteru") is turned into hiragana before it's checked, and the card shows the kana Tomo read. It's converted only when every word is valid romaji, so English ("what are you doing") still gets No score. **Why:** a learner without a Japanese keyboard, or one who can't read kana yet, still knows the answer; typing it in romaji shouldn't be a dead end.

### 2026-10-06: Tomo's shared code is a Swift package, TomoCore
Everything that isn't Mac-only (the game, growth and store, languages and packs, AI, voice, sounds, the chick's drawing) moved from the Mac app into a local Swift package, `TomoCore/`, that builds for macOS and iOS. The Mac app and the iPhone app are shells around it and talk to `TomoGame` through closures, not Coucou's `AppState`. It was done before any iPhone code ([#52](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/52)). **Why:** the iPhone app, its widgets and Live Activities need the same Tomo, and a package boundary keeps Mac-only code (the notch, AppKit, Dictionary.app) out of it. The cost: the API the shells use is marked `public`.

### 2026-10-06: Docs and checks follow SERP's agent-harness standard
Docs are maps and leaves, as in the [SERP agent-harness standard](https://github.com/serpcompany/serp/tree/main/docs/engineering/standards/agent-harness). `AGENTS.md` and READMEs point; each leaf covers one topic (purpose, invariants, boundaries, reasons); the code holds the detail. CI checks doc sizes (maps 120 lines, leaves 300), kebab-case names, internal links, and Japanese text in Swift strings. Debug flags and the snapshot matrix moved to `verification.md`; the Coucou license notes and changed files to `coucou-fork.md`; research got a map. The owner set `Stage: explore` and `Agents may merge: yes`. **Why:** our rule was "update architecture.md whenever a seam moves", which is how Keybumps' architecture doc grew to 4,500 words of per-PR detail. Our written rules weren't checked either: the dizzy card had Japanese in Swift despite the rule, and the new check found it.

### 2026-10-06: Practice is a mode you choose, like WaniKani's Extra Study
When nothing would count, Tomo doesn't slip into practice rounds that look like progress. It says so first (nothing counts until a time; practice won't move the bar) and waits for **Practice** or **Later**. While practicing, the header says "Practice until …", the bar dims, and a right answer gets a blue **Practice** badge, not the green Win. **Why:** a tester played for minutes, saw "Win" every time and a bar that didn't move, and missed the small note saying it was practice. WaniKani avoids this by keeping the two apart: reviews only when due (its dashboard says "0 reviews" and when the next ones come) and a separate Extra Study that never touches progress. Practice still isn't counted, so the spacing stays honest.

### 2026-10-06: Playing by choice counts: early reviews at half the wait, and new words a day is a setting
A word can be reviewed early once at least half its wait has passed, and the right answer moves it up like a due one. Free play brings due words, then new ones, then these early ones, and only then practice. New words a day is a setting (5, 10, 20 or 30; default 10). This loosens WaniKani's "only when due" rule. **Why:** opening Tomo by choice should feel worth it; answering the same word again within minutes still counts for nothing, so cramming still doesn't work.

### 2026-10-06: Japanese goes to 6さい with NINJAL's preschool and picture-book words
The CDI stops at about 3, so Japanese ages 3–6 come from NINJAL's 幼児語彙 and 絵本語彙 (CC BY 4.0): about 2,000 more words, with readings and English meanings from JMdict. There are no per-age norms past 3, so the age comes from a rule: how many of the four preschoolers used a word, and in how many picture books it appears (more → earlier). It's an assumption to tune with real answers. JMdict senses are picked by frequency, and wrong ones are fixed by hand. Ages 4–6 keep the 3さい look for now ([#38](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/38)). **Why:** Tomo needs words past 3, and these are the openly licensed sources the research found.

### 2026-10-06: English levels from Wordbank too, for Japanese speakers
English uses the same pipeline on Wordbank's American English norming data (647 words, 66 levels). Every English word carries a Japanese meaning: matched by concept to the Japanese CDI word where possible, written by hand otherwise. English-only grammar words are left out. The English list is the MacArthur-Bates CDI, which its publisher holds the copyright to, so the same ask-before-a-beta rule applies ([#40](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/40)). **Why:** Japanese speakers learning English are the second pair we support, and the data and script were already there.

### 2026-10-06: Japanese levels come from Wordbank's toddler word data; every word can be asked by its meaning
Tomo's Japanese levels are the 699 words of the Japanese CDI, ordered by when half of children understand or say them (Wordbank, CC BY 4.0), built by a pinned, repeatable script with hand curation (pictures, meaning fixes). This replaces the placeholder content and changes the 2026-10-05 entry below: the child-vocabulary research is now the source of the word lists, while what Tomo does with them can still come from the Zenbu learning system. Rounds are separated from what a word comes with: a word always has a meaning and may have a picture or an action, and a round uses the best one it has; **pick the meaning** works for every word ([#14](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/14)). Pictures are emoji for now, swappable later. The J-CDI developers control the instrument's distribution, so we ask them before a beta ships the list ([#40](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/40)). English and Spanish follow with the same script later. **Why:** real age data beats a hand-written guess, and a universal round means no word is left out for lack of a picture.

### 2026-10-05: Tomo grows by WaniKani-style word stages and levels; ages are level markers
Every word has a stage on a fixed ladder (WaniKani's published rules, in our own code with our own names). A word only moves up when it's due, so growth takes days and can't be crammed. A level is a small set of words; Tomo levels up when 90% of them reach "knows it". Each level has an age, so some level-ups are birthdays, like a Pokémon evolving at set levels. A visit brings due words first, then at most one new word (10 a day); a scheduled visit with nothing to do is skipped. Progress is saved in SQLite on the Mac, one Tomo per language pair, with every answer logged. This refines "ages are the levels" (2026-10-03) and, for now, replaces the FSRS-lite proposal in [leveling-points.md](research/leveling-points.md). **Why:** a proven model that's simple to explain and show; frequent small level-ups with rare big birthdays; adaptive scheduling (swift-fsrs) can replace the fixed waits later behind the same stages ([#38](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/38)).

### 2026-10-05: Tomo comes to you; what it teaches is a pluggable content source
Tomodachi's core is delivery. Tomo drops in through the day for a short moment, so learning doesn't depend on the discipline to open an app every day. What Tomo brings comes from a **content source**. The age track (what a child knows at each age, the original idea) is the first and default source. Other sources can plug in later (ideas: an Anki deck, [#11](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/11); Zenbu words, word lists and more, [#12](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/12)). Visits, the character, the help panel, voice and answer checking are shared by every source. This widens the entry below: the Zenbu learning system feeds the age track, and can also be a source of its own. The seam is [#10](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/10). **Why:** the habit, not the material, is what learners lose. Many already have material they care about (Anki decks), and Tomo can bring it to them.

### 2026-10-05: What Tomo asks and does comes later, from the Zenbu learning system
The logic that picks Tomo's words, questions and activities is deferred. It won't be built only on "what children know at each age": it will tie into the other Zenbu Japanese apps (the dictionary, Language Reference IDs, what the learner already knows there). Until then, the hand-written pack content is a placeholder. The child-vocabulary research ([age-vocabulary-data.md](research/age-vocabulary-data.md)) is background only. We don't use that data, so no license requests are needed. **Why:** a richer, shared learner model beats a fixed age list, and it keeps Tomo in step with the other apps.

### 2026-10-05: Sound effects are synthesized in code
Tomo's peeps, chirps and the island's blips are generated by `TomoSounds.swift` (pitch sweeps, overtones, a little noise), not audio files. Coucou's sound files are deleted. Effects share the voice's on/off switch. **Why:** fully ours with no license to track, tiny, and they can follow Tomo's age (lower peeps as it grows).

### 2026-10-05: Tomo is drawn and animated live, and always feels alive
Like Coucou's character, Tomo is vector shapes drawn in code every frame, with our own animation system (moves, springs, particles). No static images or sprite sheets. Tomo never sits frozen: it breathes, blinks, follows the cursor, fidgets between events and dozes when ignored. **Why:** the character is the product; a pet that holds still feels dead.

### 2026-10-05: Tomo is a hiyoko (baby chick)
Picked from three sketches (onigiri, seedling, chick). Growth tells a hatching story: 1さい in the bottom half of its eggshell, 2さい hatched, 3さい bigger with a fan of head feathers. Built in `TomoCharacter.swift` from scratch; Coucou's character code is deleted. **Why:** cute, clearly ours, and hatching is a built-in "I grew up" moment.

### 2026-10-05: Replace Coucou's character instead of asking for permission
Coucou's asset license reserves the Mochi character's design, look, expressions and animations, not just its look. Rather than ask the author, Tomo gets its own character: our own drawing, expressions and animations, in our own code, replacing `BotEngine`. The notch shell (MIT code) stays. **Why:** no dependency on someone else's permission, and a character we fully own.

### 2026-10-05: Tomo calls itself わたし
In Japanese, Tomo says わたし, never ぼく, おれ or あたし. わたし is neutral, so Tomo has no set gender, and it's the word learners meet first. The rule is in `ja.json` (`ai.rules`); the Japanese translations in other packs use it too.

### 2026-10-05: The app is Tomodachi (by Zenbu Japanese); the character is Tomo
The app's name (menu, island header, About, bundle) is **Tomodachi**, credited "by Zenbu Japanese". **Tomo** stays the character's name in sentences ("Tomo understood you"). The bundle ID is `com.zenbujapanese.tomodachi`, matching the Zenbu iPhone app's `com.zenbujapanese.dictionary`. It was changed before any tester build shipped. **Why:** the product is Tomodachi; Tomo is the friend inside it.

### 2026-10-03: Beta 0.0.1 ships as a signed, notarized zip
Built by `mac-demo/scripts/release-beta.sh` with the team's Developer ID (847HR8U8D9): universal, hardened runtime, microphone permission only. Coucou's sounds and icons aren't bundled. The default visit frequency is 20 minutes, changeable in Settings. No AI key ships in the app: testers add their own or use offline replies. **Why:** testers can open it without macOS warnings, and nothing we can't legally or safely distribute is inside.

### 2026-10-03: Every answer is a Win, a Miss, or No score
**Win** (understood / right picture) counts toward growth. **Miss** (tried in the target language, Tomo didn't get it / wrong picture) gives no credit; later, the leveling model weakens the word. **No score** (wrong language, or asking for help) gives no credit and no penalty. **Why:** the learner should always know what an answer earned, and asking for help must never feel like failing.

### 2026-10-03: Language pairs from day one
Tomo supports any learner language × any target language. Target languages are data packs (`Resources/languages/<id>.json`: words, lines, voice and recognition locales, script check, AI persona). Learner languages are interface-string files plus translations inside the packs. No Swift code contains text in a specific language. One Tomo per target language. **Why:** anybody should be able to learn anything. A Spanish draft pack proves the swap works end to end (pictures, voice, language check, AI). See [languages.md](languages.md).

### 2026-10-03: The AI never decides credit alone
Code checks the answer first (it must contain Japanese, and later it must fit the question via the Zenbu dictionary). The AI's verdict is only an input that code double-checks. **Why:** `gpt-5.4-mini` accepted the English answer "car" as understood despite the prompt rules.

### 2026-10-03: Tomo can be dismissed but nudges you back
A × button (and Esc) closes an open visit at any time, because Tomo must never block what you're doing. An unfinished visit (closed or ignored) leaves a red dot on small Tomo and a bounce every 60 s until you check in. **Why:** people get lazy about learning, and a quiet nudge brings them back without guilt.

### 2026-10-03: Prove each part first; plug real systems in later
The current goal is proof that each part works, plus clean extension points ([architecture.md](architecture.md)). The offline keyword matcher is a placeholder: Zenbu's offline dictionary system will check answers. **Why:** that system already exists in the other Zenbu apps.

### 2026-10-03: AI through one provider adapter
`TomoAI` speaks Anthropic's own API plus the OpenAI-compatible format (OpenAI, Gemini, OpenRouter, Groq, Ollama, custom). The default is OpenAI `gpt-5.4-mini`, chosen after a test turn against `gpt-5.4-nano`: natural toddler Japanese, about 2 s, and it rejects English. **Why:** don't lock into one vendor. Keys come from `.env` (dev) or the Keychain.

### 2026-10-03: Speech recognition stays on the Mac
`TomoListener` requires on-device recognition, with no server fallback. **Why:** the concepts promise free, private voice input.

### 2026-10-03: Drop-in visits, with Tomo always available
Tomo opens on its own every so often (10 min in the demo) for 3 answers, and leaves quietly after 10 s with no interaction (20 s while talking). Between visits it sits small beside the notch for unlimited free play. **Why:** people get lazy about studying. Visits are the nudge, and free play is for when you want more.

### 2026-10-03: Ages are the levels; understanding comes before speaking
1さい: tap pictures or actions. 2さい: two-word phrases. 3さい: answer in your own words. Each age adds a harder way to answer. Grade whether Tomo understood you, not your pronunciation.

### 2026-10-03: Build on Coucou's code, not its character
Fork [Coucou](https://github.com/Louis-CFM/coucou) (MIT code) for the notch shell and character engine. Grok Bot isn't open source; its "reconstruction" repo is unlicensed. Coucou's name, Mochi character and sounds are reserved, so Tomo gets its own look, and the sound effects are off by default. **Why:** the fastest route to a native notch companion without license risk.

### 2026-10-03: Mac notch first
A native Swift app in `mac-demo/`. Phone and web come later.
