# Decisions

Newest first. Add an entry when a direction is chosen. Keep the reason, so later sessions don't reopen it by accident.

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
