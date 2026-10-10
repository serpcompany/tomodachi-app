# Tomodachi beta: tester guide (Mac 0.0.2, iPhone 1.1)

Tomo is a little blob of jelly who lives next to your MacBook's notch and only speaks the language you're learning, at its own age. Every tester's Tomo looks different. It starts at age 1 (single baby words), and evolves into a new shape at each birthday as you understand it.

## Install

1. You need **macOS 15 or later** (Apple Silicon or Intel).
2. Unzip `Tomodachi-0.0.2-beta.zip` and move **Tomodachi.app** to Applications.
3. Open it. The first time, your Tomo hatches in a short welcome: answer its first word, pick how often it
   visits and its quiet hours, and whether Tomodachi opens when you log in (Tomo can only visit while it's
   open), then it pops out of the notch and waves. (If you already have a Tomo, it just pops out.)
   Tomodachi has a Dock icon and a small Tomo icon in the menu bar.

## What to try

- **Answer Tomo's visits.** Tomo drips down from the notch on its own (every 20 minutes by default, never in quiet hours: 9 PM to 8 AM unless you change them in Settings). Tap the right picture or meaning, or do what it asks: 🍙 feed, 😴 bed, 🤗 hug. The thin amber line under the card shows how long Tomo stays if you leave it; pointing at Tomo holds it.
- **Close it when it's in your way** with **×**, or Esc once you've clicked Tomo (Esc never leaves the app you're typing in). Tomo is pulled back up into the notch, and small Tomo waits beside it, glowing amber while a word is waiting; on its other side, あそぼ！ means a word is waiting, a dimmed time says when words are back, and the little ring is Tomo's level.
- **Play any time:** click small Tomo next to the notch.
- **Say hello:** when Tomodachi starts, and when your Mac wakes, Tomo says hello: a drop falls from the notch and gathers into Tomo. Poke Tomo and watch it wobble. Tell us if the jelly look or the hello gets tiresome.
- **Talk with Tomo:** hold **⌥** and click the menu bar icon → **Skip to talking (3さい)** (after that, a **Testing** menu is in Tomodachi's menu bar too). That's a test Tomo; yours comes back from **Back to my Tomo** in that menu, or when you relaunch. Tomo asks real questions; pick what it means, or later a reply that fits. Every answer shows **Win**, **Miss**, **No score**, or (when nothing counts) **Practice**. The card lights up with the moment: green for a Win, blue for Practice, gold for a level-up or a birthday; a Miss gets no light.
- **Open the Tomodachi window:** click the Dock icon, or Tomo's age at the top of the card. Its sidebar has **Tomo** (its level, what's left to grow, what each age brings, and today), **Words** (every level, locked ones too, with each word's stage and when it's due), **Settings** and **About**. **Tomo → Tomo's words** (⌘W) and **Drop in now** (⌘D) are in the menu bar while Tomodachi is in front.
- **Settings** (⌘,): how often Tomo visits, how a visit starts (**Open the card**, as before, or **Peek first**: Tomo peeks out beside the notch with its word, and the card opens when you point at it for a moment or click it; tell us which you prefer), quiet hours, how many new words a day, Tomo's voice and sounds, opening Tomodachi when you log in (what you picked in the welcome; Tomo only visits while the app is open), and the language of the app's text (English or Japanese). Tomo speaks Japanese in this version.

## Good to know

- **Progress is saved on this Mac and syncs through your iCloud.** Tomo grows over days, not minutes: a word only counts again when it's due (hours at first, then days), so a few short visits a day is the right pace. Clicking Tomo to play counts too, as long as some time has passed since you last saw a word. When nothing counts, Tomo rests and says when it's back; if you'd like to keep playing anyway, **Practice** is a button there (marked in blue; it doesn't move the bar). **Lv** in the header goes up when 9 of a level's 10 words are known; some levels are birthdays. The bar under the header moves a little with every answer that counts (a +1 flies into it from the result, and at a birthday it fills with your Tomo's colour); the short piece at its end fills only when the level is done, and the card says what's left ("1 more word to Lv 2 · ready now"). To start over: Settings, or **Tomo → Start Tomo over…** (it asks first).
- **The voice is the Mac's built-in Japanese voice at a higher pitch.** Better voices come later.
- **No AI setup in this version:** Tomodachi works offline, with no account. Word cards show the meaning from Tomo's words and the Mac's dictionary.
- **No microphone:** you answer by clicking, so Tomodachi doesn't ask for it.
- **Moving between displays:** Tomo follows the notch, or the main display's menu bar when the lid is closed.
- **Reduce Motion** (System Settings → Accessibility → Display on the Mac, Accessibility → Motion on the iPhone): Tomo
  stays put and shows how it feels with its face and a small puff instead of hopping and shaking, and fades in and out
  instead of dripping from the notch (its hello too). The card's coloured light stays, without its ripple, and the level bar moves with a glow instead of a flying +1. Widgets and the Lock Screen card still move.

## On the iPhone (TestFlight)

Install **TestFlight** from the App Store, then open the invite link we send you. Signed in to the same iCloud account on both, the iPhone and the Mac share one Tomo: play on either and the other catches up (iPhone 1.1 and Mac beta 0.0.2 or later). If both already had a Tomo, they merge.

- **The first time:** your Tomo hatches and asks its first word, then you pick how often Tomo may find you (hourly unless you change it), quiet hours (9 PM to 8 AM), whether Tomo may send notifications (it says why before iOS asks), how to add a widget (skip it if you like), and whether Tomo sits on your Lock Screen. If your Tomo is already on your Mac, it says "welcome back" instead of hatching. If you had the app before, you won't see this.
- **Reminders:** when words are ready, Tomo sends a notification at the rhythm you picked, never in quiet hours. If you don't come by for two days, it slows down to once a morning, and after a week it waits for you. Tap one to play.

- **Play in the app:** the same rounds as on the Mac. Tap a word in Tomo's line to look it up. Hold a finger on Tomo and it shows its love. When nothing counts, Tomo rests on the screen and says when it's back; Practice is there if you want it.
- **The tabs:** **Play**, **Tomo** and **Words** (the same as the Mac's window) and **Settings**: reminders (on or off, how often, quiet hours), Tomo on the Lock Screen, new words a day, sounds and the app's language, with **About** (the version, privacy policy, support and credits) at the bottom.
- **Small screens and accessibility:** it fits an iPhone SE, works with VoiceOver and larger text, and never asks for the microphone. The Ring/Silent switch mutes Tomo.
- **Add the widget:** long-press the Home Screen → **+** → Tomodachi (small or medium). It shows Tomo and how many words are waiting. On the Lock Screen: long-press it → Customize → the space under the time → Tomodachi.
- **Lock your phone:** if you said yes to it, Tomo's card is on the Lock Screen (allow Live Activities when asked). Tap the yellow **▶** to play one round right there, or tap the card to open the app. On iPhones with a Dynamic Island, Tomo sits there too.

## Feedback we want

- Did the welcome make clear what Tomo is and how to answer? Was it too long? On the iPhone: were the reminders too many, too few, or at bad times? Did you keep Tomo on your Lock Screen, or add a widget?
- Did visits feel like a nice nudge, or annoying? Was the frequency right?
- Was it clear what Tomo wanted? Were Win / Miss / No score clear? Did Tomo's sounds fit it, or get annoying?
- Did anything feel like studying instead of playing?
- Anything broken, confusing, or ugly. Screenshots help.
