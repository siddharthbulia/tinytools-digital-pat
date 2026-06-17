# PRD — Digital Pat v2: **Rooms** 🏠🐱  *(rev. 2 — post-review)*

*Working title for the social layer: **the Room**. The app stays "Digital Pat".*

> **One line:** Your friend's (or crew's) little pixel selves live on your desktop, and you
> **poke** each other to say hi — they hop onto your screen and bounce around. Presence is the
> cozy backdrop; **the poke is the point.**

> **What changed in rev. 2** (from the two-reviewer gate): (a) reframed around **poke + pet**, not
> "presence" — presence alone is the low-frequency trap that killed Sneek/Sqwiggle/Tandem;
> (b) **works for 2** (a couple / a duo) as well as a crew — a Room of 2 solves both cold-start and
> the frequency problem (the Locket lesson); (c) **no subscription** — generous free + **$14.99
> one-time + AI credit packs**; (d) **streaks & "who-missed-you" are FREE** (that's the retention
> loop); your one invite-coded Room is **free and private**; (e) split into a **thin, hardened
> v2.0** and a **v2.1 fast-follow**, with the engineering blockers promoted to hard requirements.

---

## 1. Problem

Far-apart friends, couples, and remote crews lose the **ambient "we're here together" feeling**.
The tools are too heavy (a Slack message is a *task*, a call is an *event*) or too cold (a green
dot, "last seen"). There's no warm, zero-effort way to feel a person nearby **and give them a
little nudge** that says "thinking of you" — no words, no pressure.

Digital Pat v1 already gives one person a companion that reacts to what they're doing. The insight:
**make it two-player.** Your buddy lives on your friend's desktop and theirs on yours; a glance
tells you they're around; and a **poke** is the lightest possible way to talk.

## 2. Target user

Two shapes of the **same** simple thing — a Room you share with people you already like:

- **A pair** (the cold-start-proof wedge): long-distance couple, best friends, a duo of co-founders.
  Two people is enough for the product to be magical *and* high-frequency. (This is the Locket move.)
- **A small crew of 5–15** already online together: a remote startup team, a friend group, a Discord
  clique. (Literally the founder's own team — the 22 bundled characters are them.)

**Not for:** large public communities, strangers, serious chat. A **toy for people who already
like each other.**

## 3. The 30-second pitch

> Pick your pixel character (or make one from a selfie — or just *describe* one). Share a Room
> code with your person or your crew. Now their little buddies live in a cozy corner of your
> screen, quietly shifting as people code, vibe, or slip into meetings. Miss someone?
> **Poke them** — your character hops onto *their* screen and bounces around going "miss you 💕".
> Poke back. It's the lowest-effort, highest-cute way to say *hi, I'm thinking of you.*

## 4. Wedge & upgrade trigger

- **Wedge (install reason, free forever):** **"poke your person."** Their pixel self on your
  desktop + the ability to fling a cute poke at them. Works with **just two people**, so there's
  no "empty room" problem.
- **Upgrade trigger (Pro):** the moment you want to **make characters on demand** — *describe*
  "a grumpy wizard cat" and watch it appear (this is the irresistible, shareable part, **and** the
  part that costs us real OpenAI money). You get a taste free; volume is paid credits.

## 5. What's in the box

### 5.1 Free tier — generous, fun forever
- **Your Room, private & free** — create or join **one** invite-coded Room (great for a pair or a crew).
- **All 22 predefined characters** as your avatar.
- **1 custom character from a photo** + **1 free "describe-it" generation** (a taste of the magic).
- **Live presence**: your avatar auto-mirrors your activity mood; see everyone else's in real time.
- **Unlimited pokes** + preset micro-messages ("yo", "miss you", "wassuppp", "gm", "🫶", "👀", "🎉") + emoji.
- **Receive pokes** as the cute on-screen invasion (sender's avatar bounces in with a bubble).
- **Streaks & "who missed you"** — your poke history + day-streaks with each person. *(The retention loop — free.)*
- A **local library** of as many characters as you want; switch your active one anytime.

### 5.2 Pro — "Pat Pro": **$14.99 one-time** + **AI credit packs** (no subscription)
The paywall sits on our **real costs** (metered AI generation) and on power-user breadth — honest, defensible:
- **Describe-to-create at volume** + **unlimited custom characters** — via **credit packs**
  (e.g. $4.99 / 1,000 credits ≈ N character generations). *(Direct OpenAI COGS.)*
- **Extra / multiple Rooms** beyond your free one (different crews, couple + team).
- **Custom poke phrases & seasonal emoji packs** (write your own one-liners).
- **Cosmetics** — hats/accessories, Room backdrops/themes.

> v1's own (correct) reasoning was that recurring billing "feels gross and kills conversion" for a
> vibe purchase — so Pro is a **one-time unlock**, and the only recurring spend is **optional AI
> credits** that map 1:1 to our cost.

### 5.3 Out of scope (explicitly)
- Real chat: threads, DMs, long messages. **Pokes + micro-messages only.**
- Voice / video / screenshare. Mobile. Public discovery / strangers / global feed.
- File sharing, typing indicators, read receipts.
- **Any manager/surveillance/leaderboard framing** (see §9).

## 6. UX

### 6.1 The poke (the hero loop)
- **Default = poke.** One tap on a friend → their app spawns *your* character, which **hops in and
  bounces** around their screen with "👋" for a few seconds, then settles/leaves.
- **Or a micro-message**: preset ("miss you", "wassuppp") or emoji → same cute invasion with your
  line in the bubble. **Poke back** in one tap. Rapid back-and-forth feels like a giggle.
- Cute: poke combos ("👀👀👀"), a "poked!" confetti, a gentle (mutable) sound.
- **Etiquette (hard rule):** the invasion is a **non-activating overlay** that never steals
  keyboard focus or interrupts typing.

### 6.2 The Room (the cozy backdrop)
A small always-available pixel space (shelf / windowsill / clubhouse) where each member's companion
mills about in its **current mood pose** (coding/vibing/meeting/browsing/creating/idle…) with a name
tag. Glance → read the room. Lives as a draggable window + a peek in the menu-bar popover.

### 6.3 Joining & identity
- First launch → **display name + avatar** (predefined / photo / describe) → **create or join a Room
  by code.** Sharing a code is the whole onboarding.
- **Identity persistence (hard requirement):** Supabase **anonymous auth**; refresh token stored in
  **Keychain** so you keep your identity across launches; **email magic-link** to carry it across
  machines and to **merge** an anon identity. Define reinstall behavior explicitly.

### 6.4 Presence sync (passive, cute-not-creepy)
- The existing local mood engine publishes **only**: `{name, characterId, mood, lastActiveAt}`.
- **Never** the app name, window title, URL, or keystrokes — only the *category mood*. This is the
  privacy promise. Plus an **"appear away"/invisible** toggle. **No dashboards, ever.**
- Debounced (on mood change / heartbeat) — light, not jittery.
- **Reliability (hard requirement):** handle **reconnect, sleep/wake re-subscribe, and stale-ghost
  timeout** — the exact bugs that make presence apps feel broken.

### 6.5 Character creation
- **Predefined** (instant, free) · **From a photo** (free: 1) · **From a description** (free: 1 taste, then credits).
- All generation runs through the Supabase Edge Function (key server-side).

### 6.6 Unhappy paths
- Offline/server down → Room greys out, "reconnecting…"; solo pet features keep working; pokes fail gracefully.
- Poke spam → **server-side** per-sender rate limit, one-tap **mute/block** (a `blocks` table), room-scoped only.
- Generation fails / unsafe prompt → friendly retry + prompt safety filter on the function.

## 7. Tech sketch

- **Backend = existing Supabase project** `digital-pat` (ref `cpfbipbdsokoshzgqvsr`).
- **Swift client = official `supabase-swift` SDK** → native **Realtime Presence** (roster) +
  **Broadcast** (pokes). No hand-rolled websockets. (macOS 13+ already our floor.)
- **Presence channel per room**: each client tracks `{uid, name, characterId, mood, lastActiveAt}`.
- **Pokes**: Broadcast `{from, to, kind: poke|msg, body}`, **persisted** to a `pokes` table (powers
  free streaks / "who missed you").
- **Auth**: anonymous + optional magic-link; refresh token in Keychain.
- **Data model**: `profiles(uid,name,active_character)`, `rooms(id,code,name,owner)`,
  `room_members(room_id,uid)`, `pokes(id,room_id,from,to,kind,body,created_at)`,
  `blocks(uid,blocked_uid)`, `usage_counters(uid,day,generations)`. **RLS + Realtime authorization
  policies** so you only see/poke your room.
- **Generation hardening (BLOCKER — do before any social launch):** switch the function to
  **`--verify-jwt`** and enforce a **server-side per-uid daily generation cap** via
  `usage_counters`; the embedded shared secret is extractable and **must not** be the only guard on
  the OpenAI card.
- **Poke gating (BLOCKER):** server-side rate-limit + room-membership check + `blocks`; client overlay
  is a non-activating `NSPanel`.
- **Custom-avatar distribution:** a full 17-PNG bundle is **~68KB** → feasible via Supabase Storage;
  it's a **lifecycle** problem (RLS scoping, discovery, orphan cleanup), not size/latency. **Deferred
  to v2.1** to keep the first ship thin.

## 8. Scope & phasing  *(per eng review: ship thin first)*

### v2.0 — the shippable core (~10–11 dev-days)
Shared default Room (invite code) · predefined-22 avatars (+ your own custom shown **locally** to you)
· live presence (mood sync, with reconnect/sleep-wake/stale-ghost) · **pokes + micro-messages** ·
free **streaks / who-missed-you** · **hardened generation** (`--verify-jwt` + per-uid caps) · poke
overlay done right · anon-auth + Keychain persistence · mute/block + server-side poke rate-limit.

### v2.1 — fast-follow
**Cross-member custom-avatar sync** (others see your made-up character) · **extra/multiple Rooms (Pro)**
· cosmetics / Room themes · custom poke-phrase & emoji packs · magic-link cross-device merge.

## 9. Risks
- **Cold-start / network effect** — mitigated by the **pair wedge** (a Room of 2 is enough) + dead-simple
  invite codes + seeding the founder's own crew + "invite 1 person" onboarding.
- **Presence is low-frequency** (the graveyard's killer) — mitigated by making **the poke**, not
  presence, the daily loop, and by **streaks** that reward reciprocity.
- **Creepy vs cute** — *category mood only, never app/URL/keys*; "appear away"; framed as affection;
  **no manager dashboards.**
- **AI cost scales with users** — free = predefined + 1 photo + 1 taste generation; volume = paid
  credits; **server-side daily caps**; `--verify-jwt` (the shared secret is not a real guard).
- **Poke spam / harassment** — server-side rate-limit, mute/block/report, room-scoped from day one.
- **Reconnect / sleep-wake / stale ghosts** — explicit handling or the Room "feels broken."
- **macOS focus etiquette** — non-activating overlay, never steals focus.
- **Graveyard risk** — bet: the *cute desktop-pet* hook + the *poke toy* (not "presence") + working
  at **n=2** is differentiated and viral inside friend groups.

## 10. Success metrics
- **Activation**: % of installs that join a Room **and exchange a poke** in week 1.
- **Magic number**: a Room with **≥2 mutually-poking members** (reciprocity, not headcount).
- **Daily poke rate** + **poke-back rate**; **streak retention**.
- **W2 retention** of members in a reciprocating Room.
- **Pro/credit conversion** via describe-to-create after the free taste.

## 11. The freemium logic in one paragraph
You install to **poke your person** — free forever, works with just two of you, with predefined
avatars, presence, unlimited pokes, and streaks. You pay (once, $14.99) and buy **credits** the
moment you want to **conjure characters on demand by describing them** — the delightful, shareable
thing that also costs us OpenAI money — or run **extra Rooms**. The paywall sits exactly on our real
costs. No subscription.

---

## Reviewers
- [x] Product / GTM reviewer — `PRD-reviews/v2-product-review.md` — *verdict: REVISE → addressed in rev. 2*
- [x] Engineering reviewer — `PRD-reviews/v2-eng-review.md` — *verdict: 6/10 buildable → blockers promoted to requirements; scope split v2.0 / v2.1*
