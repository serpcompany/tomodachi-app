# Tomodachi: user journey feature ideas

## 1. Tomo drops in once in a while (no study sessions)

**The rule:** Tomo comes to you every so often for a tiny moment, then goes away. You never have to sit down to "do a lesson." Learning happens in many small moments spread across your day, the way a kid picks up language from the people around them.

**Always there, if you want more:** between visits, Tomo hangs out small beside the notch. Click it any time to play for as long as you like, with no time limit. The visits exist because people get lazy about learning; they're a nudge, not the only way in.

**Built in the demo (simple version):** visits come every 10 minutes and the first one is at launch. Tomo opens on its own. If you don't click, type, or hover for 10 seconds (20 seconds at the talking stage), it yawns and tucks back in. A visit is 3 answers, then バイバイ. Visits wait while you're typing and skip when nobody's at the Mac. There are no settings yet: the constants are in `DropIn` in `mac-demo/NotchBuddy/Sources/App/TomoGame.swift`.

**Visit timing**
- *Now (demo):* every 10 minutes plus one at launch. Waits while you're typing (retries in 20 s). Skips when you've been away 5+ minutes. The next visit is 10 minutes after the last one ended.
- *Proposed, not built:*
  - The base interval comes from a setting: chatty 20 min, normal 45 min, quiet 2 h, with ±20% randomness.
  - Each ignored or closed visit doubles the wait (up to 4 h); an answered visit resets it.
  - At most about 12 visits a day, and none at night.
  - Visits come only at natural breaks: stopped typing, switched apps, unlocked the Mac.
  - Visits come sooner when words are due for review.

**How a drop-in works**

1. Tomo peeks out of the notch and waves or calls out (まんま！, ワンワン！). It doesn't take over the screen.
2. If you hover or click, it opens for a **10–30 second moment**: 1–3 quick exchanges.
3. Then Tomo says バイバイ and goes back into the notch.
4. If you ignore it, after about 10 seconds it yawns and goes back on its own. If it's in your way, close it with **×** (or Esc). Either way there's **no penalty**: no lost streak and no guilt message.
5. **Gentle nudge back:** after an unfinished visit, small Tomo waits beside the notch with a **red dot** and does a little **bounce** now and then (every 60 s in the demo) until you click it or the next visit starts.

**Rules for the moments**

- **Short:** a few exchanges at most. You can always click Tomo to keep playing, but that's your choice, never required.
- **Good timing:** Tomo only drops in at natural breaks (you just stopped typing, switched apps, or came back to the Mac). It never interrupts while you're typing, presenting, on a call, screen sharing, watching something full screen, or in Do Not Disturb or Focus.
- **Adjustable frequency:** set "how chatty Tomo is" (quiet / normal / chatty). Starting points to tune: a few times a day, about every hour, about every 20–30 minutes. If you keep ignoring it, Tomo backs off on its own.
- **Follows your day:** what Tomo needs matches the time of day, like a Tamagotchi. おはよう in the morning, まんま around lunch, ねんね at night.
- **Built-in review:** each moment shows words that are due for review, plus at most one new word. Short, spaced practice is how memory works best anyway.
- **Grows over days, not minutes:** a word only counts as known after you've understood it on more than one day. You can't cram Tomo into growing up; it grows as you keep it company.
- **Never guilt-trips you:** if you've been away, Tomo can be sleepy or happy to see you, but never sad or disappointed in you.

**Why:** "I need to find time to study" is what makes people quit language apps. Tomo is a friend who shows up, not a course you have to start.

**Already in the demo to build on:** the Coucou base already has the notch behaviors (hidden → peek → compact → open), mouse-idle detection, and auto-collapse. A drop-in is a scheduler that triggers a peek and wave, then plays 1–3 rounds.

**Open questions**

- Should Tomo open by itself (the demo does), or only peek and wait for a hover or click?
- Which "busy" signals can macOS give us without scary permission prompts? Idle time and full-screen apps look easy. Calls and Focus mode may be harder.
- What should the default frequency be for a brand-new user?

## 2. Start with multiple choice (built in the demo)

At 1さい, Tomo says single baby words and you answer by tapping: pick the right picture (ワンワン → 🐶), or do what it asks (まんま → feed, ねんね → bed, だっこ → hug). You don't need to produce any Japanese yet. Understanding is enough.

## 3. New ways to answer as Tomo gets older

Each age adds a harder way to answer. The easier ways stay available as a fallback.

| Tomo's age | You answer by |
|---|---|
| 1さい | Tapping pictures or actions |
| 2さい | Tapping Japanese reply bubbles (すき！ / きらい); saying single words out loud (これ なに？ → いぬ) |
| 3さい | Speaking or typing short sentences in a real conversation; reply bubbles fade away over time |
| 4さい+ | Explaining things (the なんで？ phase); chatting while you watch a show together |

Grade whether Tomo understood you, not your pronunciation. If it didn't catch what you said, it tilts its head and says ん？

## 4. Tap any word for a dictionary card

Anything Tomo says (its line, hints, example answers) is shown as **linked words**, the same way the Zenbu iPhone app's Player shows captions. Words you don't know yet are lightly underlined; known words aren't, but can still be tapped.

Tapping a word opens a small **word card** next to the island:
- the word, with its reading (furigana for Japanese) and pitch accent
- the meaning in your language, and a 🔊 button
- for baby words, the grown-up word (ワンワン → 犬)
- a **✓ Known** toggle
- **Open in Zenbu**: the full Word Detail in the Zenbu app or website (permanent word URLs)

Rules:
- Looking at a card counts as activity, so Tomo doesn't leave while you read.
- A lookup is recorded as *exposure* (you saw the word), never as a Miss. If you look up a word from Tomo's question before answering, the answer still counts, but the leveling model learns that word needed help.
- Words you mark ✓ Known here and in the Zenbu apps should be the same list. Sync by Language Reference ID; see the learner-data research.
