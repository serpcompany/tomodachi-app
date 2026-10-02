# Decisions

Newest first. Add an entry when a direction is chosen. Keep the reason, so later sessions don't reopen it by accident.

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
