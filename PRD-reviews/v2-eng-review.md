# Digital Pat v2 (Rooms) — Engineering Review

**Score:** 6 / 10
**One-sentence verdict:** The realtime + sprite-distribution mechanics are more tractable than the PRD fears (official supabase-swift has first-class Presence/Broadcast, and a full sprite bundle is only ~68KB), but the *honest* scope is a 3-4 week solo build, the anonymous-auth identity model and server-side abuse caps are underspecified BLOCKERS, and the focus-stealing poke overlay is a real AppKit landmine — ship a thin "presence + poke, predefined avatars only" v2 and defer custom-avatar sync.

## Architecture sanity check
- **Realtime is fine.** The official `supabase/supabase-swift` SDK (macOS 10.15+) ships `RealtimeChannelV2` with native `presenceChange()` / `track()` and `broadcastStream(event:)` / `broadcast(event:message:)`. No hand-rolled Phoenix websocket needed. This is the single biggest de-risk vs. what the PRD implies. Add it to `Package.swift` alongside Sparkle.
- **Sprite distribution is NOT heavy** — the PRD's scariest risk is overstated. A measured full bundle (`characters/cat`, 17 PNGs) is **68KB total**, ~2-3KB per frame. Even at 256px these are tiny. "Sprite atlas + compression + lazy load" is over-engineering; a zip of 17 PNGs to Supabase Storage is trivial. The real concern is *lifecycle* (orphan cleanup, who pays, cache invalidation), not size.
- **Presence model is sound** — publishing only `{uid, name, characterId, mood, lastActiveAt}` via Presence `track()` is exactly the right shape and keeps the privacy promise (§6.3). Good.
- **The Edge Function is image-gen only.** Everything realtime/auth/RLS/pokes/storage is net-new. The PRD's "backend = the Supabase project we already have" undersells this — you're reusing a project, not a backend. Anonymous Auth, 4 tables + RLS, Realtime authorization policies, a Storage bucket with policies, and per-user server-side caps are all greenfield.
- **Identity persistence is hand-waved.** "Anonymous account, persistent on the device" — supabase-swift anonymous auth issues a JWT whose refresh token must be persisted (Keychain, not UserDefaults). If lost, the user becomes a new ghost in the room with a duplicate avatar. This needs an explicit design, not a parenthetical.

## Top 5 weaknesses (severity: BLOCKER / MAJOR / MINOR)
1. **[BLOCKER] Server-side abuse/cost caps are named but not designed, and the trust model is broken.** The shared secret (`56aa1a7a...`) and anon key are both hardcoded in `Backend.swift` and trivially extractable. Today the Edge Function has *zero* rate limiting — any extracted secret = unlimited gpt-image-1 calls on the founder's OpenAI card. v2 *adds users* and *makes generation a product feature*, so this moves from "casual abuse" to "metered product with a known-leaked key." You need: (a) require a real Supabase auth JWT (`--verify-jwt`, drop `--no-verify-jwt`) so calls are attributable to a `uid`; (b) a `usage_counters` table with a per-uid daily generation cap enforced *inside* the function via service-role write; (c) the same JWT-derived `uid` gating poke broadcast rate. The shared secret is security theater once shipped — do not rely on it for anything that costs money.
2. **[BLOCKER] Poke = remote code path that spawns a window on someone else's machine; abuse + focus etiquette are underspecified.** A Broadcast event causing another client to spawn an NSPanel is a harassment vector and a focus landmine. Required: the receiver-side overlay MUST be a non-activating `NSPanel` (`.nonactivatingPanel` style mask, `level = .statusBar` or `.floating`, `becomesKeyOnlyIfNeeded = true`, `ignoresMouseEvents` except the dismiss target) so it never steals keyboard focus or interrupts typing. Server-side (not client-side) per-sender poke rate limiting, room-membership verification on every broadcast, and mute/block must exist day one — a client-side rate limit is bypassable by the same DevTools-equivalent (a patched binary / direct websocket). RLS-backed `room_members` check is the only real gate.
3. **[MAJOR] Custom-avatar distribution lifecycle, not size, is the unsolved problem.** Storage is cheap and bundles are 68KB, so just upload a zip to a `sprites/{characterId}/` bucket. But the PRD never answers: who can download whom (Storage RLS must scope to co-room-members), how peers discover a new `characterId` and lazy-fetch it, cache invalidation when someone regenerates, orphan cleanup when a user leaves (the IAM/cleanup gap is already a known factory wart — see notchpad/dropnest), and the free-tier "1 custom character" cap enforced server-side. This is ~1-1.5 days of fiddly work, not a checkbox. Recommend: **cut custom-avatar sync from v2 entirely** — ship predefined-22 only in the room, keep generation as a local-only solo feature, add cross-member custom avatars in v2.1 once the room loop is proven.
4. **[MAJOR] Reconnect / sleep-wake / stale-presence handling is one line ("reconnecting…") for the hardest realtime bug.** macOS sleep drops the websocket; on wake, supabase-swift must re-subscribe and re-`track()`, and ghosts (clients that slept without an untrack) must time out. Use `NSWorkspace.didWakeNotification` / `willSleepNotification` to tear down + rebuild the channel, and treat `lastActiveAt` older than ~90s as "away/grey" regardless of presence state. Without this the room fills with stale/duplicate avatars within a day — the exact thing that makes ambient-presence apps feel broken (and the PRD itself lists Sneek/Sqwiggle as the graveyard).
5. **[MINOR] RLS for room-scoped reads is non-trivial with Realtime, and the data model has gaps.** Realtime Broadcast/Presence now supports RLS authorization via `realtime.messages` policies — you must write these, not just table RLS, or any authenticated user can join any room's channel by name. The `pokes` table needs an index on `(room_id, to, created_at)` for the Pro "who missed you" view. `rooms.code` needs a uniqueness constraint + collision handling on invite-code generation. No `blocks`/`mutes` table exists in the model despite being promised in §6.4.

## Required changes before approval
- Define the **auth/identity spec**: anonymous JWT persisted in Keychain, refresh handling, the magic-link upgrade path that *merges* (not duplicates) the anonymous uid. Name what happens on reinstall.
- Switch the Edge Function to **`--verify-jwt`** and add a `usage_counters`-backed **server-side daily generation cap** keyed on `uid`. Stop treating `x-pat-secret` as a control.
- Specify the **poke overlay as a non-activating NSPanel** with explicit window level/flags, and move **poke rate-limit + room-membership + block/mute** enforcement server-side (RLS on `realtime.messages` + a `blocks` table).
- Add **sleep/wake re-subscribe** (`NSWorkspace` notifications) and a **stale-presence timeout** rule.
- Write the **Realtime RLS authorization policies** for room channels, not just table RLS.
- **Cut custom-avatar cross-member sync from v2** (keep local generation; defer distribution to v2.1).

## Optional improvements
- Persist pokes server-side from day one (cheap) even if "who missed you" is Pro-gated later — avoids a migration.
- Add an "appear away / invisible" toggle (already promised in §9 risks but absent from §5 feature list) — it's a 1-hour `untrack()` toggle and a major trust signal.
- Debounce presence `track()` to mood-change + a 30-60s heartbeat; don't publish on every frontmost-app flicker.
- Consider a single shared default room seeded server-side so the founder's crew has zero-config onboarding.

## Permissions / sandboxing assessment
No *new* TCC prompts: presence reuses v1's existing mood engine (NSWorkspace frontmost-app needs no permission; browser-domain AppleScript already prompts for Automation in v1). Realtime is just outbound websocket — no entitlement. The poke overlay needs **no Accessibility/Screen Recording** as long as it's a borderless non-activating panel you own (don't reach for `CGWindowList` or event taps). The one real first-launch UX cost is the **room-join + display-name + avatar-pick** flow, which is product onboarding, not OS permission. Sandboxing/notarization is unchanged from v1; outbound network is already implicitly allowed for the Edge Function.

## License gating: is it defensible enough at this price point?
At $4.99/mo or credit packs, the threat model is right: casual piracy is fine, but the bypasses that cost *real money* (AI generation) must be closed server-side — and currently they are NOT, because the function trusts an extractable shared secret and has no per-user cap. The fix is structural, not cosmetic: gate generation on an authenticated `uid` + server-side daily/credit counter (service-role enforced). Pro *features* (private rooms, custom phrases, history, cosmetics) can be locally licensed via the existing pattern, but anything with marginal cost (generation, extra rooms = extra realtime/storage) must verify entitlement server-side. Renderer-equivalent trust (a patched Swift binary flipping `isPro`) is acceptable for cosmetics; unacceptable for the OpenAI spend. **The paywall is honest and well-placed; the enforcement is the gap.**

## Estimated implementation time
Assumes solo dev, reusing v1's Sprites/Animator/Mood engine, supabase-swift SDK doing the websocket heavy lifting.

- **Free tier (presence + pokes, predefined avatars only):**
  - supabase-swift integration + anon auth + Keychain token persistence: 6h
  - Schema + RLS + Realtime authorization policies + invite codes: 8h
  - `RoomStore` (presence track/subscribe, sleep-wake, stale timeout): 10h
  - `RoomWindow` rendering roster via existing Animator: 8h
  - Poke broadcast + non-activating overlay panel + receive/animate: 12h
  - Server-side poke rate-limit + block/mute + room-membership checks: 6h
  - Onboarding (name/avatar/join) + offline/reconnect UX: 6h
  - **Subtotal: ~56h**
- **Pro tier (generation hardening + private rooms + history + cosmetics):**
  - Edge Function `--verify-jwt` + `usage_counters` daily cap: 6h
  - Create-by-description + unlimited custom (local) + entitlement checks: 6h
  - Private/multiple rooms (mostly schema + UI): 5h
  - "Who missed you" + streaks (persisted pokes view): 5h
  - Custom poke phrases/emoji packs + cosmetics: 6h
  - **Subtotal: ~28h**
- **If custom-avatar cross-member sync is kept (NOT recommended for v2):** +12h (Storage bucket + RLS + discovery + lazy fetch + cache + orphan cleanup).

- **Total: ~10.5 dev-days (84h) realistic for free+Pro as scoped-minus-avatar-sync; ~14 days if avatar sync is included.**
- **Optimistic: ~7 days** if private rooms, cosmetics, and streaks slip to v2.1 and the build is purely "shared default room + predefined avatars + pokes + hardened generation."
- **Schedule risk lives in:** (1) the poke overlay focus/etiquette tuning (iterative, easy to get subtly wrong), (2) realtime reconnect/stale-ghost edge cases (the bug that kills the product feel), and (3) Realtime RLS authorization policies (newer, under-documented, easy to leave a channel open). Budget buffer there, not on the sprite plumbing.

Sources:
- [supabase/supabase-swift](https://github.com/supabase/supabase-swift)
- [Supabase Realtime Presence](https://supabase.com/docs/guides/realtime/presence)
- [Supabase Realtime Broadcast](https://supabase.com/docs/guides/realtime/broadcast)
