# PRD — Digital Pat

> Digital Pat is a tiny kitten that lives in the top-right corner of your Mac screen and quietly reacts to whatever you're doing. Open Chrome and it gets to work; jump on Zoom and it throws on a little blazer; fire up Claude or a terminal and it puts on glasses to "study." It never reads your content — it only knows *which app is in front* — and at the end of the day it shows you a cute breakdown of where your hours went. You can pat it anytime and it'll purr and smile back (you pat Pat). It's an ambient, low-stakes companion for people who spend all day at a laptop and want a friendlier screen.

---

## 1. Problem

People who work on a laptop all day stare at a focused, joyless screen for 8–10 hours. Two small, real pains stack up:

1. **The screen is lonely and sterile.** There's no warmth, no companion, nothing that makes the workday feel a little less like a void. Gen-Z especially decorates everything (phone, desktop, Notion) for *vibes* — the Mac desktop is the last un-decorated surface.
2. **Nobody actually knows where their day went.** "I was busy all day" but doing *what*? Time-tracking tools (RescueTime, Timing) exist but they feel like surveillance dashboards — heavy, guilt-inducing, enterprise-flavored. Nobody opens them for fun.

Concrete moment: It's 6pm. Aanya, a 24-year-old product designer, closes her laptop and has no idea whether she spent the day in Figma or doom-scrolling Slack. She'd never install a "productivity tracker" — that sounds like a chore — but she *would* keep a cute kitten on her screen that happened to tell her, at the end of the day, "you spent 4h in design mode 🎨 and 2h in meetings 👔."

## 2. Target user

**Aanya, 24, product designer at a startup.** Lives on her MacBook. Has a curated desktop wallpaper, Spotify always open, decorates her Notion with emojis. Uses Figma, Chrome, Slack, Zoom, Notion all day. She's tried a time tracker once, found it clinical and guilt-trippy, deleted it in a week. She likes Tamagotchi nostalgia, desktop pets, and lo-fi "study with me" streams. She wants her screen to feel *alive*, and she'd love a gentle, non-judgmental mirror of her day.

**Anti-personas (NOT building for):**
- The serious productivity optimizer who wants billable-hour reports, Pomodoro enforcement, and CSV exports for their manager. (That's RescueTime. We are the opposite vibe.)
- Privacy-hostile use cases — we will never read screen content, keystrokes, or window titles. If a feature needs that, it's out.
- Windows/Linux users (v1 is Mac-only).

## 3. The 30-second pitch

A cute kitten lives in the corner of your screen and reacts to whatever app you're using — coding, in meetings, browsing, writing. Pat it when you need a friend, and at the end of the day it shows you a sweet little summary of where your time went.

## 4. Wedge feature

**The kitten reacts, live, to your active app — and it's adorable.** Within 30 seconds of installing, you switch from Chrome to Zoom and watch the kitten swap into a tiny blazer. That single "omg it noticed" moment is the entire hook. Everything else (summaries, history, skins) is bonus.

## 5. What's in the box

### 5.1 Free tier — fully usable forever

- **The pet itself.** A kitten that floats on top of all windows in the top-right corner. Frameless, transparent background, always-on-top, click-to-pat.
- **Live activity reactions.** Detects the frontmost app and switches the kitten into the matching *mood state* (sprite + outfit + animation + idle micro-caption). See §6.3 for the full sprite set.
- **Pat interaction.** Click/tap the kitten → it does a happy reaction (purr, smile, hearts float up, little wiggle) + a one-line caption ("hi!! ♡").
- **Today view.** Click the kitten's little speech bubble (or the tray icon) to open a small card showing *today only*: total active time, and a breakdown by mood category (e.g. Coding 3h, Meetings 1h, Browsing 2h) with cute labels and emoji. Resets at midnight.
- **Drag to reposition.** Drag the kitten anywhere; it remembers where you put it.
- **Launch at login.** On by default (the whole point is it's always there). One toggle to turn off.
- **Quiet/hide toggle.** Hotkey + tray item to hide the kitten (for screen-sharing or focus). It keeps logging quietly.
- **Zero permissions, zero network.** Works the second you open it. Nothing leaves your machine.

### 5.2 Pro tier — for the daily user ($14.99 one-time)

1. **History & recaps.** Free shows *today*; Pro persists every day and unlocks: a 7-day/30-day view, a weekly recap card ("this week: 18h coding, your most 🐱 day was Tuesday"), and a calendar heatmap. This is the natural upgrade trigger — you fall in love with the today view, then want to see yesterday.
2. **The wardrobe (extra skins + outfits).** Free ships one kitten with the core outfits. Pro unlocks alternate breeds/skins (e.g. orange tabby, calico, black cat, Siamese, and non-cat skins like a puppy or red panda) and seasonal/funky outfit packs (cozy hoodie, pixel/Y2K, sleep cap, party). Pure cosmetic delight — exactly what this audience pays for.
3. **Custom moods.** Map your own apps to moods and edit captions (e.g. "when Linear is open, kitten = 'shipping mode 🚢'"). Power users want their pet to *get* their specific stack.

**Why $14.99 one-time:** It's a delight/vibe purchase, not a utility ROI purchase, so a recurring subscription would feel gross and kill conversion. One-time and impulse-priced (cheaper than a phone-case skin pack) matches how the audience buys cosmetics. Sits in the same band as the rest of the tinytools Pro tiers.

### 5.3 Out of scope (explicitly)

- Reading screen content, window titles, URLs, or keystrokes — **ever**. Mood is derived purely from the frontmost app's identity.
- Meditation / breaks / wellness nudges / Pomodoro — the user explicitly does **not** want this in v1.
- Notifications, streaks, gamification pressure, "you've been browsing too long" guilt. Pat is a friend, not a nag.
- iCloud sync, multi-device, accounts, leaderboards, social sharing — v2+.
- AI-generated commentary / LLM captions — v2 maybe; v1 captions are a hand-written canned set per mood.
- Windows/Linux.

## 6. UX

### 6.1 Where it lives & how it behaves

- **Floating desktop pet**, not a menu-bar popup. This is the one intentional break from the factory's standard menu-bar shape. A small frameless, transparent, always-on-top window (~120×120pt) anchored top-right by default, draggable, position remembered.
- Also installs a **menu-bar tray icon** (a tiny 🐱 glyph) for the boring stuff: open Today/recap, hide/show pet, settings, quit, upgrade. The pet is the star; the tray is the utility belt.
- **Click-through everywhere except the kitten.** The transparent window doesn't block clicks on whatever is behind it — only the kitten's body is interactive (pat / drag).
- **First launch:** kitten fades in top-right, waves a paw, shows a one-time speech bubble: "hi! i'm Pat 🐱 i'll hang out while you work. pat me anytime!" Then it settles into its idle/current-app mood. No setup, no wizard, no permission prompts.

### 6.2 Interactions

- **Pat (single click):** happy animation (purr + ears perk) + floating hearts + canned caption ("♡", "hehe", "hi!!"). Tiny cooldown so mashing doesn't spam.
- **Drag:** reposition; snaps loosely to screen edges; remembers spot.
- **Hover:** shows the current-mood speech bubble for ~2s ("coding mode 👩‍💻").
- **Click speech bubble / tray → Today:** the small summary card.
- **Hide:** hotkey (default ⌥⌘P) or tray toggle → kitten fades out, keeps logging.

### 6.3 The sprites / mood states (the heart of the app)

Art direction: **soft, round, chibi kitten. Gen-Z / cozy-funky.** Big head, tiny body, huge sparkly eyes, little triangle ears, stubby paws, an expressive tail. Thick outlines, pastel accents, squishy proportions, subtle loop animations (breathing, blinking, ear-twitch, tail-flick) so it never looks frozen. Each mood = the base kitten + an outfit/prop + a looping micro-animation + a small rotating set of captions. (Exact look gets locked in the design session — this is the spec, not the final art.)

| # | Mood | Triggered by (frontmost app) | Look / outfit | Animation | Sample caption |
|---|------|------------------------------|---------------|-----------|----------------|
| 1 | **Coding** 👩‍💻 | VS Code, Xcode, Terminal, iTerm, Cursor, Zed | Tiny glasses, hoodie, sits at a tiny laptop | Typing paws, occasional head-bob, tail flick | "locked in 💻", "shipping…" |
| 2 | **Thinking / Studying** 🤔 | Claude, ChatGPT, Perplexity, Notion AI, PDFs/Preview | Round glasses + a little open book or thought-bubble lightbulb | Tilts head, taps chin, lightbulb blinks | "big brain time 💡", "hmm…" |
| 3 | **In a meeting** 👔 | Zoom, Google Meet, Teams, Slack huddle, FaceTime | Smart blazer over the fur (business-on-top vibe) | Sits up straight, ears perked, nods politely | "in a call 🎧", "looking professional" |
| 4 | **Communicating** 💬 | Slack, Mail, Messages, Discord, Gmail | Headphones + tiny speech bubbles | Paws "typing", bubbles float | "replying… 📨", "inbox grind" |
| 5 | **Browsing** 🌐 | Chrome, Safari, Arc, Firefox | Casual, holding a tiny phone/tablet | Lazy scroll-swipe, eyes drift, slow tail sway | "just browsing 👀", "ooh" |
| 6 | **Creating / Designing** 🎨 | Figma, Photoshop, Sketch, Canva, Final Cut | Beret + tiny paintbrush/stylus | Dabs a little canvas, ears twitch | "in the zone 🎨", "making things" |
| 7 | **Vibing / Media** 🎧 | Spotify, Apple Music, YouTube, Netflix | Big headphones, eyes closed, swaying | Head-bob to a beat, tail taps, music notes float | "vibing 🎶", "lo-fi hours" |
| 8 | **Idle / Away** 😴 | No input for N min, or screen locked | Curled into a loaf, nightcap, little "z z z" | Slow breathing, occasional snore bubble, ear twitch | "napping 💤", "brb dreaming" |
| 9 | **Pat reaction** ♡ | (any click on the kitten) | Sparkly eyes, blush, ears perked | Purr + hop + floating hearts | "♡", "hehe", "hi!!" |

Fallback: an **unmapped app** → a neutral "default kitten" (state 0): sitting, blinking, tail swaying, gently breathing, caption "👋". Unknown apps never break the pet.

> Implementation note: each mood is one sprite sheet (idle loop + transition-in). 8 moods + default + pat reaction ≈ 10 sprite sheets for v1. Animations are simple frame loops, not physics. Free tier = the base kitten across all moods; Pro skins re-skin the same sprite-sheet slots so we don't multiply art per skin × mood beyond reason.

### 6.4 Unhappy paths

- **Can't read frontmost app** (shouldn't happen — it's a standard API) → fall back to default kitten, keep running.
- **Multiple displays** → pet stays on its remembered display; if that display is gone, reset to primary top-right.
- **Fullscreen app / Space change** → pet follows to the active Space and stays on top (uses the join-all-Spaces window behavior).
- **Free user opens history** → friendly upsell card ("Pat only remembers today on the free plan — unlock history to see your week ✨").

## 7. Tech sketch

- **Stack:** Native Swift + AppKit (matches the rest of the factory's recent apps; best for a borderless always-on-top transparent window, sprite animation, low memory, tiny binary). Window-mode, not the menu-bar template — so this app overrides `LSUIElement` behavior: it shows a borderless floating panel **and** a menu-bar status item, but no Dock icon.
- **Activity detection:** `NSWorkspace.shared.frontmostApplication` + the `NSWorkspace.didActivateApplicationNotification` notification. Gives the active app's bundle identifier and localized name. **No Accessibility, no Screen Recording, no Full Disk Access** — this is the key privacy + zero-friction property. Idle detection via `CGEventSourceSecondsSinceLastEventType` (no input monitoring permission needed for the idle timer).
- **App → mood mapping:** a static bundle-ID → mood dictionary shipped in the app (e.g. `com.google.Chrome` → Browsing). Pro custom-mood overrides stored locally. Unknown bundle IDs → default kitten.
- **Sprite rendering:** sprite-sheet PNGs animated frame-by-frame in a layer-backed view (or tiny SpriteKit scene). No web view, no Electron — keep it small and battery-friendly. Throttle to a low FPS for idle loops.
- **Persistence:** local only. Today's tally in memory + a small JSON/SQLite file in `~/Library/Application Support/DigitalPat/`. Pro history is just retaining that file across days + an aggregation view. Window position + settings in `UserDefaults`.
- **Background work:** a lightweight always-running loop tracking the frontmost-app changes and accumulating seconds per mood. This runs whenever the app is open (which is "always," by design). Negligible CPU when idle (event-driven, not polling).
- **License-gating:** `lib/license.js`-equivalent — a locally-validated signed key (no network roundtrip), gating History/recaps, the wardrobe, and custom moods. Same pattern as the other Pro apps in the factory.
- **Permissions needed:** none beyond the default. (Big selling point: "no scary permission prompts.")

## 8. Success metrics

- **I keep Pat on my own screen for 3 weeks straight** and don't hide/uninstall it out of annoyance. (The real dummy test for an ambient app: does it survive the irritation threshold?)
- **The pat interaction gets used unprompted** — I (or a test user) pat it ≥ 3×/day without being told to. Signals it's a companion, not wallpaper.
- **5 friends install it; ≥ 2 still have it running after a week; ≥ 1 buys Pro** (almost certainly for the wardrobe).
- **Lands on r/macapps or design Twitter/TikTok with a "this is so cute" reaction** — virality is the GTM for a vibe product; a clip of the kitten swapping outfits is the ad.

## 9. Risks

1. **Annoyance / occlusion.** An always-on-top thing in the corner can cover UI and get irritating fast. → Mitigations: small footprint, click-through except the body, instant hide hotkey, draggable, edge-snapping, low-key idle animation (no loud motion). Kill criterion: if I personally reach for the hide key more than a couple times a day in week 1, the default behavior is wrong.
2. **"It's a toy, not worth paying for."** Cuteness alone may not convert to $15. → Mitigation: the wardrobe (skins/outfits) is a proven cosmetic-purchase pattern for this audience, and history/recaps add a real keep-reason. If conversion is dead, the lever is *more/better skins*, not more "productivity" features (which would betray the vibe).
3. **Art quality is the whole product.** If the kitten looks like generic AI slop or the animations are stiff, the wedge ("omg adorable") fails and nothing else matters. → Mitigation: treat sprite art as the #1 deliverable, not an afterthought; get the base kitten + 3 hero moods (coding, meeting, idle) genuinely charming before building breadth. Kill criterion: if the hero sprites don't make a test user smile on sight, stop and redo the art.

## 10. Non-goals & explicit cuts

- **No AI commentary in v1.** Captions are a curated canned set per mood. LLM-written quips are a tempting v2, but v1 must be fully local, offline, zero-cost, and instant — and canned lines are funnier when hand-written anyway.
- **No wellness/meditation/nudge layer.** Explicitly cut by the user. Pat observes and vibes; it does not coach.
- **No content awareness.** We will never look at *what's* on screen, only *which app*. This is a permanent product principle, not a v1 shortcut — it's the trust foundation.
- **No sync/accounts.** Local-only keeps it private, simple, and free of backend cost. Revisit only if multi-device demand is real.

---

## Reviewers

- Product reviewer (subagent): `PRD-reviews/product.md`
- Engineering reviewer (subagent): `PRD-reviews/engineering.md`
- Synthesis of feedback + changes made: `PRD-reviews/synthesis.md`
