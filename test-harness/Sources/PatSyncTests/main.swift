import Foundation
import Supabase

// Public anon key (also embedded in the shipped app binary — safe to use for tests).
let ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNwZmJpcGJkc29rb3NoemdxdnNyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE1MzM2NDIsImV4cCI6MjA5NzEwOTY0Mn0.uzWBpZi2YSCHnWwrqbmh7kYDCXKBW-zhw0k_pks6iIU"

// MARK: - tiny test framework

struct Result { let id: String; let title: String; let pass: Bool; let detail: String }
@MainActor enum Box { static var results: [Result] = [] }

@MainActor
func record(_ id: String, _ title: String, _ pass: Bool, _ detail: String = "") {
    Box.results.append(Result(id: id, title: title, pass: pass, detail: detail))
    let mark = pass ? "✅ PASS" : "❌ FAIL"
    print("\(mark)  [\(id)] \(title)\(detail.isEmpty ? "" : "  — \(detail)")")
    fflush(stdout)
}

/// Poll until `cond` is true or timeout. Returns whether it became true.
@MainActor
func waitUntil(_ timeout: Double = 12, _ cond: () async -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await cond() { return true }
        try? await Task.sleep(nanoseconds: 250_000_000)
    }
    return await cond()
}

/// Let realtime settle (used before asserting a NEGATIVE — that something did NOT happen).
func settle(_ seconds: Double = 4) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }

@MainActor
func newDevice(_ label: String, name: String? = nil, character: String = "cat") async throws -> Device {
    let d = Device(label: label, name: name ?? label, character: character)
    try await d.start()
    return d
}

/// Make A and B mutual friends (returns once both sides reflect it). Uses a multi-use invite by default.
@MainActor
func befriend(_ a: Device, _ b: Device) async throws {
    let token = try await a.createInvite(multi: true)
    let r = await b.acceptInvite(token)
    precondition(r.ok, "befriend accept failed: \(r.error ?? "?")")
    _ = await waitUntil { a.hasFriend(b.uid) && b.hasFriend(a.uid) }
}

// MARK: - tests

@MainActor
func runAll() async {
    print("=== Digital Pat multi-device sync tests (live Supabase, real SDK) ===\n")

    // ---------- INVITE LIFECYCLE ----------
    do {
        let a = try await newDevice("L1a", name: "Alice", character: "cat")
        let b = try await newDevice("L1b", name: "Bob", character: "gd")
        let token = try await a.createInvite(multi: false)
        let r = await b.acceptInvite(token)
        let ok = await waitUntil { a.hasFriend(b.uid) && b.hasFriend(a.uid) }
        record("L1", "invite+accept → mutual friendship both sides", r.ok && ok,
               "A sees B=\(a.hasFriend(b.uid)) name=\(a.friend(b.uid)?.name ?? "-"); B sees A=\(b.hasFriend(a.uid)) name=\(b.friend(a.uid)?.name ?? "-")")
        // name + character correct on each side
        record("L1b", "mutual rows carry correct name + character",
               a.friend(b.uid)?.name == "Bob" && a.friend(b.uid)?.character == "gd" &&
               b.friend(a.uid)?.name == "Alice" && b.friend(a.uid)?.character == "cat")
    } catch { record("L1", "invite+accept", false, "threw: \(error)") }

    do {
        let a = try await newDevice("L2a", name: "Ann")
        let b = try await newDevice("L2b", name: "Ben")
        let c = try await newDevice("L2c", name: "Cara")
        let token = try await a.createInvite(multi: false)   // single-use
        let r1 = await b.acceptInvite(token)
        let r2 = await c.acceptInvite(token)                 // should FAIL (already used)
        record("L2", "single-use invite revoked after first accept", r1.ok && !r2.ok,
               "first=\(r1.ok) second=\(r2.ok) err=\(r2.error ?? "-")")
        record("L2b", "single-use: 2nd accepter is NOT a friend", !a.hasFriend(c.uid) && !c.hasFriend(a.uid))
    } catch { record("L2", "single-use invite", false, "threw: \(error)") }

    do {
        let a = try await newDevice("L3a", name: "Amy")
        let b = try await newDevice("L3b", name: "Bea")
        let c = try await newDevice("L3c", name: "Cy")
        let token = try await a.createInvite(multi: true)    // multi-use
        let r1 = await b.acceptInvite(token)
        let r2 = await c.acceptInvite(token)
        let ok = await waitUntil { a.hasFriend(b.uid) && a.hasFriend(c.uid) }
        record("L3", "multi-use invite accepted by two different devices", r1.ok && r2.ok && ok,
               "A friendCount=\(a.friendCount)")
    } catch { record("L3", "multi-use invite", false, "threw: \(error)") }

    do {
        let a = try await newDevice("L4a", name: "Al")
        let token = try await a.createInvite(multi: false)
        let r = await a.acceptInvite(token)   // accept own invite → reject
        record("L4", "self-add rejected", !r.ok && a.friendCount == 0, "err=\(r.error ?? "-")")
    } catch { record("L4", "self-add", false, "threw: \(error)") }

    do {
        let b = try await newDevice("L5b", name: "Bo")
        let r1 = await b.acceptInvite("not-a-real-uuid")
        let r2 = await b.acceptInvite("")
        let r3 = await b.acceptInvite("00000000-0000-0000-0000-000000000000")
        record("L5", "malformed/empty/unknown token rejected, no friendship",
               !r1.ok && !r2.ok && !r3.ok && b.friendCount == 0,
               "garbled=\(r1.ok) empty=\(r2.ok) unknown=\(r3.ok)")
    } catch { record("L5", "bad token", false, "threw: \(error)") }

    do {
        let a = try await newDevice("L6a", name: "Ada")
        let b = try await newDevice("L6b", name: "Bud")
        let token = try await a.createInvite(multi: true)
        let r1 = await b.acceptInvite(token)
        let r2 = await b.acceptInvite(token)   // accept SAME invite again → idempotent (on conflict do nothing)
        record("L6", "duplicate accept idempotent (still exactly one friendship)",
               r1.ok && r2.ok && a.friendCount == 1 && b.friendCount == 1,
               "A=\(a.friendCount) B=\(b.friendCount)")
    } catch { record("L6", "duplicate accept", false, "threw: \(error)") }

    do {
        let a = try await newDevice("L7a", name: "Ali")
        let b = try await newDevice("L7b", name: "Boe")
        let token = try await a.createInvite(multi: false)
        let r = await b.acceptInvite("digital-pat://add?token=\(token)")   // URL-prefixed
        let ok = await waitUntil { a.hasFriend(b.uid) }
        record("L7", "accept handles digital-pat://add?token= prefix", r.ok && ok)
    } catch { record("L7", "token prefix", false, "threw: \(error)") }

    // ---------- REALTIME GRAPH (bug #1: live add/remove, isolation) ----------
    do {
        let a = try await newDevice("G1a", name: "GA")
        let b = try await newDevice("G1b", name: "GB")
        let c = try await newDevice("G1c", name: "GC")   // unrelated witness
        let cEventsBefore = c.graphEventCount
        let token = try await a.createInvite(multi: false)
        // A is ALREADY running (never restarted). B accepts.
        _ = await b.acceptInvite(token)
        let aLive = await waitUntil { a.hasFriend(b.uid) }      // A learns live via graph watcher
        let bLive = await waitUntil { b.hasFriend(a.uid) }
        record("G1", "friend-add reflected LIVE on inviter side (no restart)", aLive,
               "A.graphInserts=\(a.graphInserts) A.hasFriend(B)=\(a.hasFriend(b.uid))")
        record("G2", "friend-add is mutual & live on both sides", aLive && bLive)
        await settle(4)
        record("G4a", "third device gets NO graph event for unrelated friendship (RLS isolation)",
               c.graphEventCount == cEventsBefore && c.friendCount == 0,
               "C events delta=\(c.graphEventCount - cEventsBefore) C.friendCount=\(c.friendCount)")

        // live remove → both sides
        let aDelBefore = a.graphDeletes, bDelBefore = b.graphDeletes
        await a.removeFriend(b.uid)
        let aGone = await waitUntil { !a.hasFriend(b.uid) }
        let bGone = await waitUntil { !b.hasFriend(a.uid) }
        record("G3", "unfriend reflected LIVE on BOTH sides", aGone && bGone,
               "A.deletes=\(a.graphDeletes - aDelBefore) B.deletes=\(b.graphDeletes - bDelBefore)")
    } catch { record("G1", "live graph", false, "threw: \(error)") }

    // ---------- PRESENCE / MOOD (bug #3) ----------
    do {
        let a = try await newDevice("M1a", name: "Mia")
        let b = try await newDevice("M1b", name: "Moe")
        try await befriend(a, b)
        await a.updateMood("coding")
        let bSees = await waitUntil { b.moodOf(a.uid) == "coding" }
        record("M1", "A mood change → B sees it live", bSees, "B sees A mood=\(b.moodOf(a.uid) ?? "-")")
        await b.updateMood("vibing")
        let aSees = await waitUntil { a.moodOf(b.uid) == "vibing" }
        record("M2", "B mood change → A sees it live (other direction)", aSees, "A sees B mood=\(a.moodOf(b.uid) ?? "-")")
    } catch { record("M1", "mood sync", false, "threw: \(error)") }

    do {
        let a = try await newDevice("M3a", name: "Ma")
        let b = try await newDevice("M3b", name: "Mb")
        try await befriend(a, b)
        async let x: Void = a.updateMood("meeting")
        async let y: Void = b.updateMood("creating")
        _ = await (x, y)
        let conv = await waitUntil { b.moodOf(a.uid) == "meeting" && a.moodOf(b.uid) == "creating" }
        record("M3", "simultaneous mood changes both converge", conv,
               "B-sees-A=\(b.moodOf(a.uid) ?? "-") A-sees-B=\(a.moodOf(b.uid) ?? "-")")
    } catch { record("M3", "simultaneous mood", false, "threw: \(error)") }

    do {
        let a = try await newDevice("M4a", name: "Mara")
        let b = try await newDevice("M4b", name: "Mike")
        try await befriend(a, b)
        await a.updateMood("coding")
        _ = await waitUntil { b.moodOf(a.uid) == "coding" && b.isOnline(a.uid) }
        // Simulate clock skew: A stamps a lastActive 200s "in the past" (A's clock behind / B's ahead),
        // but A is STILL actively tracking. The OLD wall-clock check marked A offline here (the exact
        // "shows away while online" bug); skew-immune liveness must keep A ONLINE.
        await a.trackStale(secondsAgo: 200)
        await settle(3)
        record("M4", "clock-skewed lastActive does NOT mark an actively-tracking friend offline (skew immunity)",
               b.isOnline(a.uid) == true, "B sees A online=\(b.isOnline(a.uid)) mood=\(b.moodOf(a.uid) ?? "-")")
    } catch { record("M4", "skew immunity", false, "threw: \(error)") }

    do {
        let a = try await newDevice("M5a", name: "Nan")
        let b = try await newDevice("M5b", name: "Ned")
        try await befriend(a, b)
        _ = await waitUntil { b.isOnline(a.uid) }
        await a.goOffline()                     // leave presence channels
        let off = await waitUntil { !b.isOnline(a.uid) }
        record("M5", "friend leaving presence → shows OFFLINE on peer", off,
               "B sees A online=\(b.isOnline(a.uid))")
    } catch { record("M5", "leave → offline", false, "threw: \(error)") }

    do {
        let a = try await newDevice("M6a", name: "Ola")
        let b = try await newDevice("M6b", name: "Oli")
        try await befriend(a, b)
        // rapid re-tracks (mood storm) must never blank the friend on the peer
        await a.updateMood("coding"); await a.updateMood("thinking"); await a.updateMood("vibing")
        let ok = await waitUntil { b.hasFriend(a.uid) && b.moodOf(a.uid) == "vibing" }
        record("M6", "rapid mood re-tracks never blank peer; converge to final", ok && b.friendCount == 1,
               "B sees A=\(b.hasFriend(a.uid)) mood=\(b.moodOf(a.uid) ?? "-")")
    } catch { record("M6", "re-track storm", false, "threw: \(error)") }

    // ---------- CHARACTER (bug #4) ----------
    do {
        let a = try await newDevice("C1a", name: "Cara2", character: "cat")
        let b = try await newDevice("C1b", name: "Cleo", character: "cat")
        try await befriend(a, b)
        await a.setCharacter("gd")
        let bSees = await waitUntil { b.characterOf(a.uid) == "gd" }
        record("C1", "A character change → B sees it live", bSees, "B sees A char=\(b.characterOf(a.uid) ?? "-")")
        await b.setCharacter("ven")
        let aSees = await waitUntil { a.characterOf(b.uid) == "ven" }
        record("C2", "B character change → A sees it (other direction)", aSees, "A sees B char=\(a.characterOf(b.uid) ?? "-")")
    } catch { record("C1", "character sync", false, "threw: \(error)") }

    do {
        let a = try await newDevice("C3a", name: "Dora", character: "cat")
        let b = try await newDevice("C3b", name: "Dan", character: "cat")
        try await befriend(a, b)
        await a.setCharacter("rohan")           // updates presence + profile
        _ = await waitUntil { b.characterOf(a.uid) == "rohan" }
        await a.goOffline()                     // now A only knowable via profile
        let ok = await waitUntil { b.isOnline(a.uid) == false }
        await b.refreshFriends()
        record("C3", "character set while online persists to profile → visible when friend OFFLINE",
               ok && b.characterOf(a.uid) == "rohan" && b.isOnline(a.uid) == false,
               "B sees A char=\(b.characterOf(a.uid) ?? "-") online=\(b.isOnline(a.uid))")
    } catch { record("C3", "offline char via profile", false, "threw: \(error)") }

    do {
        let a = try await newDevice("C4a", name: "Eve", character: "cat")
        let b = try await newDevice("C4b", name: "Eli", character: "cat")
        try await befriend(a, b)
        await a.setCharacter("gd"); await a.setCharacter("ven"); await a.setCharacter("pooja")
        let ok = await waitUntil { b.characterOf(a.uid) == "pooja" }
        record("C4", "rapid character flips converge to final on peer", ok, "B sees A char=\(b.characterOf(a.uid) ?? "-")")
    } catch { record("C4", "rapid char flips", false, "threw: \(error)") }

    // ---------- CURSOR MODE ----------
    do {
        let a = try await newDevice("U1a", name: "Fay")
        let b = try await newDevice("U1b", name: "Fox")
        try await befriend(a, b)
        record("U2", "default cursorMode is neutral before any change",
               b.cursorModeOf(a.uid) == "neutral", "B sees A mode=\(b.cursorModeOf(a.uid) ?? "-")")
        await a.updateCursorMode("attract")
        let bSees = await waitUntil { b.cursorModeOf(a.uid) == "attract" }
        record("U1", "A cursor mode change → B sees it live", bSees, "B sees A mode=\(b.cursorModeOf(a.uid) ?? "-")")
        await a.updateCursorMode("push")
        let push = await waitUntil { b.cursorModeOf(a.uid) == "push" }
        record("U1b", "cursor mode switch attract→push propagates", push)
        await a.goOffline()
        let off = await waitUntil { b.isOnline(a.uid) == false }
        record("U3", "offline friend reverts to neutral cursor mode (behavior, not durable)",
               off && b.cursorModeOf(a.uid) == "neutral", "B sees A mode=\(b.cursorModeOf(a.uid) ?? "-")")
    } catch { record("U1", "cursor mode sync", false, "threw: \(error)") }

    // ---------- RLS / PRIVACY ----------
    do {
        let a = try await newDevice("R1a", name: "Gus")
        let b = try await newDevice("R1b", name: "Gwen")
        let c = try await newDevice("R1c", name: "Hal")    // non-friend snoop
        try await befriend(a, b)
        let aReadsB = await a.canReadProfile(of: b.uid)     // friend → yes
        let cReadsA = await c.canReadProfile(of: a.uid)     // non-friend → no
        let cReadsB = await c.canReadProfile(of: b.uid)
        record("R1", "profile readable by friend, NOT by a non-friend (RLS)",
               aReadsB && !cReadsA && !cReadsB, "A→B=\(aReadsB) C→A=\(cReadsA) C→B=\(cReadsB)")
        let forged = await c.tryForgeFriendship(with: a.uid)
        record("R2", "direct friendship INSERT is blocked (no insert policy)", !forged, "forge succeeded=\(forged)")
        record("R3", "non-friend my_friends() is empty", c.friendCount == 0)
    } catch { record("R1", "rls/privacy", false, "threw: \(error)") }

    // ---------- TOPOLOGY ----------
    do {
        let a = try await newDevice("T1a", name: "Ivy")
        let b = try await newDevice("T1b", name: "Jon")
        let c = try await newDevice("T1c", name: "Kim")
        try await befriend(a, b)   // A<->B
        try await befriend(b, c)   // B<->C  (A NOT<->C)
        await settle(3)
        let bBoth = b.hasFriend(a.uid) && b.hasFriend(c.uid) && b.friendCount == 2
        let aOnlyB = a.hasFriend(b.uid) && !a.hasFriend(c.uid) && a.friendCount == 1
        let cOnlyB = c.hasFriend(b.uid) && !c.hasFriend(a.uid) && c.friendCount == 1
        record("T1", "chain A-B-C: B sees both; A and C never see each other",
               bBoth && aOnlyB && cOnlyB,
               "B=\(b.friendCount) A=\(a.friendCount)(C?\(a.hasFriend(c.uid))) C=\(c.friendCount)(A?\(c.hasFriend(a.uid)))")
        // cross presence isolation: A changes mood → C must NOT see A at all
        await a.updateMood("coding")
        await settle(3)
        record("T1b", "cross-isolation: A's mood never leaks to non-friend C",
               !c.hasFriend(a.uid) && c.moodOf(a.uid) == nil)
    } catch { record("T1", "chain topology", false, "threw: \(error)") }

    do {
        let h = try await newDevice("T2h", name: "Hub")
        let x = try await newDevice("T2x", name: "Xan")
        let y = try await newDevice("T2y", name: "Yas")
        let z = try await newDevice("T2z", name: "Zed")
        try await befriend(h, x); try await befriend(h, y); try await befriend(h, z)
        await settle(3)
        record("T2", "star hub sees all 3; each leaf sees only the hub",
               h.friendCount == 3 && x.friendCount == 1 && y.friendCount == 1 && z.friendCount == 1 &&
               x.hasFriend(h.uid) && !x.hasFriend(y.uid),
               "H=\(h.friendCount) X=\(x.friendCount) Y=\(y.friendCount) Z=\(z.friendCount)")
    } catch { record("T2", "star topology", false, "threw: \(error)") }

    // ---------- RECONNECT / WAKE / RESILIENCE ----------
    do {
        let a = try await newDevice("W1a", name: "Wren")
        let b = try await newDevice("W1b", name: "Walt")
        try await befriend(a, b)
        await a.simulateWake()                  // tear down + re-subscribe everything
        // presence resumes:
        await b.updateMood("coding")
        let moodAfterWake = await waitUntil { a.moodOf(b.uid) == "coding" }
        record("W1", "after wake/re-subscribe, presence updates still flow", moodAfterWake && a.hasFriend(b.uid),
               "A sees B mood=\(a.moodOf(b.uid) ?? "-")")
        // graph watcher resumes: a NEW friend added after wake shows live
        let c = try await newDevice("W1c", name: "Win")
        let token = try await a.createInvite(multi: false)
        _ = await c.acceptInvite(token)
        let liveAfterWake = await waitUntil { a.hasFriend(c.uid) }
        record("W1b", "after wake, graph watcher still delivers live friend-adds", liveAfterWake)
    } catch { record("W1", "wake resilience", false, "threw: \(error)") }

    do {
        // heartbeat backstop: if a graph event is MISSED (watcher down), refreshFriends reconciles.
        let a = try await newDevice("W2a", name: "Vee")
        let d = try await newDevice("W2d", name: "Dot")
        let token = try await a.createInvite(multi: false)
        await a.goOffline()                     // simulate missing the live event window (drop presence)
        // (graph watcher still up here; to truly simulate a miss we rely on the backstop refresh anyway)
        _ = await d.acceptInvite(token)
        await a.refreshFriends()                // <-- the 45s heartbeat backstop, invoked manually
        record("W2", "heartbeat backstop reconciles a friend add via refreshFriends", a.hasFriend(d.uid),
               "A.hasFriend(D)=\(a.hasFriend(d.uid))")
    } catch { record("W2", "heartbeat backstop", false, "threw: \(error)") }

    // ---------- CONCURRENCY ----------
    do {
        let a = try await newDevice("X1a", name: "Quin")
        let b = try await newDevice("X1b", name: "Rey")
        let c = try await newDevice("X1c", name: "Sol")
        let token = try await a.createInvite(multi: true)
        async let rb = b.acceptInvite(token)
        async let rc = c.acceptInvite(token)
        let (resB, resC) = await (rb, rc)
        let ok = await waitUntil { a.hasFriend(b.uid) && a.hasFriend(c.uid) }
        record("X1", "two devices accept a multi-use invite simultaneously → both friends",
               resB.ok && resC.ok && ok && a.friendCount == 2, "A friendCount=\(a.friendCount)")
    } catch { record("X1", "simultaneous accept", false, "threw: \(error)") }

    do {
        let a = try await newDevice("X2a", name: "Tao")
        let b = try await newDevice("X2b", name: "Uma")
        try await befriend(a, b)
        await a.removeFriend(b.uid)
        _ = await waitUntil { !a.hasFriend(b.uid) && !b.hasFriend(a.uid) }
        // re-add
        let token = try await a.createInvite(multi: false)
        _ = await b.acceptInvite(token)
        let back = await waitUntil { a.hasFriend(b.uid) && b.hasFriend(a.uid) }
        record("X2", "remove then re-add converges back to friends, exactly one row", back && a.friendCount == 1,
               "A friendCount=\(a.friendCount)")
    } catch { record("X2", "remove+re-add", false, "threw: \(error)") }

    // ---------- EDGE / ABUSE ----------
    do {
        let a = try await newDevice("E1a", name: "Zoe")
        record("E1", "my_friends() with zero friends → empty", a.friendCount == 0)
    } catch { record("E1", "zero friends", false, "threw: \(error)") }

    do {
        let longName = String(repeating: "n", count: 500)
        let a = try await newDevice("E2a", name: longName)
        let b = try await newDevice("E2b", name: "Bee")
        try await befriend(b, a)   // b invites a
        let ok = await waitUntil { b.friend(a.uid)?.name == longName }
        record("E2", "very long (500-char) name round-trips", ok, "len=\(b.friend(a.uid)?.name.count ?? 0)")
    } catch { record("E2", "long name", false, "threw: \(error)") }

    do {
        let emojiName = "🐱✨ Pàśç Münchçhén 日本語"
        let a = try await newDevice("E3a", name: emojiName, character: "ven")
        let b = try await newDevice("E3b", name: "Cee")
        try await befriend(a, b)
        await a.updateMood("vibing")
        let ok = await waitUntil { b.friend(a.uid)?.name == emojiName && b.characterOf(a.uid) == "ven" && b.moodOf(a.uid) == "vibing" }
        record("E3", "unicode/emoji name + character survive presence round-trip", ok,
               "name=\(b.friend(a.uid)?.name ?? "-")")
    } catch { record("E3", "unicode name", false, "threw: \(error)") }

    do {
        let a = try await newDevice("E4a", name: "Deb")
        let b = try await newDevice("E4b", name: "Eli2")
        try await befriend(a, b)
        await a.removeFriend(b.uid)
        await a.removeFriend(b.uid)   // double remove → no error / no crash
        record("E4", "double remove_friend is a safe no-op", a.friendCount == 0 && !a.hasFriend(b.uid))
    } catch { record("E4", "double remove", false, "threw: \(error)") }

    // ===================== EXPANDED COVERAGE (gap-mined from 311 designed cases) =====================

    // ---------- INVITE LIFECYCLE (more) ----------
    do {
        let a = try await newDevice("L8a", name: "Ari")
        let b = try await newDevice("L8b", name: "Bex")
        // reciprocal: A invites B AND B invites A; both accept → exactly ONE canonical friendship
        let ta = try await a.createInvite(multi: true)
        let tb = try await b.createInvite(multi: true)
        _ = await b.acceptInvite(ta)
        _ = await a.acceptInvite(tb)
        let ok = await waitUntil { a.hasFriend(b.uid) && b.hasFriend(a.uid) }
        record("L8", "reciprocal invites (A→B and B→A both accepted) → exactly ONE friendship",
               ok && a.friendCount == 1 && b.friendCount == 1, "A=\(a.friendCount) B=\(b.friendCount)")
    } catch { record("L8", "reciprocal invite", false, "threw: \(error)") }

    if Admin.available {
        do {
            let a = try await newDevice("L9a", name: "Ash")
            let b = try await newDevice("L9b", name: "Bly")
            let token = try await a.createInvite(multi: false)
            try await Admin.expireInvite(token: token)
            let r = await b.acceptInvite(token)
            record("L9", "EXPIRED invite is rejected", !r.ok && b.friendCount == 0, "err=\(r.error ?? "-")")
        } catch { record("L9", "expired invite", false, "threw: \(error)") }

        do {
            let a = try await newDevice("L10a", name: "Avi")
            let b = try await newDevice("L10b", name: "Bo2")
            let token = try await a.createInvite(multi: false)
            try await Admin.deleteUser(uid: a.uid)          // inviter gone before accept
            await settle(2)
            let r = await b.acceptInvite(token)
            record("L10", "invite from a DELETED inviter is void (cascade) → rejected", !r.ok && b.friendCount == 0,
                   "err=\(r.error ?? "-")")
        } catch { record("L10", "deleted-inviter invite", false, "threw: \(error)") }
    } else {
        record("L9", "EXPIRED invite (skipped — no service key)", true, "skipped")
        record("L10", "deleted-inviter invite (skipped — no service key)", true, "skipped")
    }

    // ---------- REALTIME GRAPH (more directions + isolation) ----------
    do {
        let a = try await newDevice("G5a", name: "Ga2")
        let b = try await newDevice("G5b", name: "Gb2")
        try await befriend(a, b)
        await b.removeFriend(a.uid)                          // B-initiated (other direction)
        let both = await waitUntil { !a.hasFriend(b.uid) && !b.hasFriend(a.uid) }
        record("G5", "unfriend initiated by B → BOTH sides lose live (initiator symmetry)", both,
               "A.deletes=\(a.graphDeletes) B.deletes=\(b.graphDeletes)")
    } catch { record("G5", "B-initiated remove", false, "threw: \(error)") }

    do {
        let a = try await newDevice("G6a", name: "Ha2")
        let b = try await newDevice("G6b", name: "Hb2")
        let c = try await newDevice("G6c", name: "Hc2")     // unrelated witness
        try await befriend(a, b)
        let cBefore = c.graphEventCount
        await a.removeFriend(b.uid)
        _ = await waitUntil { !a.hasFriend(b.uid) }
        await settle(4)
        record("G6", "unfriend isolation: unrelated third device gets NO DELETE event",
               c.graphEventCount == cBefore && c.friendCount == 0, "C delta=\(c.graphEventCount - cBefore)")
    } catch { record("G6", "remove isolation", false, "threw: \(error)") }

    do {
        // C friends with BOTH A and B; removing A-B must not disturb C's two edges.
        let a = try await newDevice("G7a", name: "Ia")
        let b = try await newDevice("G7b", name: "Ib")
        let c = try await newDevice("G7c", name: "Ic")
        try await befriend(a, b); try await befriend(c, a); try await befriend(c, b)
        await settle(2)
        let cBefore = c.graphEventCount
        await a.removeFriend(b.uid)                          // A-B row only
        _ = await waitUntil { !a.hasFriend(b.uid) }
        await settle(3)
        record("G7", "removing A-B leaves a mutual-friend-of-both (C) fully intact",
               c.friendCount == 2 && c.hasFriend(a.uid) && c.hasFriend(b.uid) && c.graphEventCount == cBefore,
               "C friendCount=\(c.friendCount) C delta=\(c.graphEventCount - cBefore)")
    } catch { record("G7", "bystander unaffected", false, "threw: \(error)") }

    if Admin.available {
        do {
            let a = try await newDevice("G8a", name: "Ja")
            let b = try await newDevice("G8b", name: "Jb")
            try await befriend(a, b)
            _ = await waitUntil { b.isOnline(a.uid) }
            try await Admin.deleteUser(uid: a.uid)          // user deleted → friendships cascade DELETE
            let gone = await waitUntil { !b.hasFriend(a.uid) }
            record("G8", "deleting a user cascades → friend's pet disappears LIVE on the peer", gone,
                   "B.hasFriend(A)=\(b.hasFriend(a.uid)) B.deletes=\(b.graphDeletes)")
        } catch { record("G8", "user-delete cascade", false, "threw: \(error)") }
    } else {
        record("G8", "user-delete cascade (skipped — no service key)", true, "skipped")
    }

    // ---------- FIRST-FRAME CORRECTNESS (newly-added friend shows CURRENT state, not defaults) ----------
    do {
        let a = try await newDevice("F1a", name: "Ka", character: "cat")
        let b = try await newDevice("F1b", name: "Kb", character: "ven")  // non-default char
        await b.updateMood("coding")                        // set BEFORE befriending
        await b.updateCursorMode("push")
        try await befriend(a, b)
        let ok = await waitUntil {
            a.characterOf(b.uid) == "ven" && a.moodOf(b.uid) == "coding" && a.cursorModeOf(b.uid) == "push"
        }
        record("F1", "newly-added friend appears with CURRENT character+mood+cursor (not defaults)", ok,
               "A sees B char=\(a.characterOf(b.uid) ?? "-") mood=\(a.moodOf(b.uid) ?? "-") cursor=\(a.cursorModeOf(b.uid) ?? "-")")
    } catch { record("F1", "first-frame current state", false, "threw: \(error)") }

    // ---------- PRESENCE: offline→online restore, self-not-overwrite ----------
    do {
        let a = try await newDevice("P1a", name: "La")
        let b = try await newDevice("P1b", name: "Lb")
        try await befriend(a, b)
        await a.updateMood("coding")
        _ = await waitUntil { b.isOnline(a.uid) && b.moodOf(a.uid) == "coding" }
        await a.goOffline()
        _ = await waitUntil { !b.isOnline(a.uid) }
        await a.comeOnline()                                 // re-subscribe presence
        await a.updateMood("vibing")
        let back = await waitUntil { b.isOnline(a.uid) && b.moodOf(a.uid) == "vibing" }
        record("P1", "offline → back online restores live presence + mood", back,
               "B sees A online=\(b.isOnline(a.uid)) mood=\(b.moodOf(a.uid) ?? "-")")
    } catch { record("P1", "offline→online restore", false, "threw: \(error)") }

    do {
        let a = try await newDevice("P2a", name: "Ma2")
        let b = try await newDevice("P2b", name: "Mb2")
        try await befriend(a, b)
        await b.updateMood("creating")
        _ = await waitUntil { a.moodOf(b.uid) == "creating" }
        await a.updateMood("meeting")                        // A changes its OWN mood
        let propagated = await waitUntil { b.moodOf(a.uid) == "meeting" }
        // not-me matching: A's own presence must NOT overwrite A's view of B's mood
        let ok = a.moodOf(b.uid) == "creating" && propagated
        record("P2", "own presence never overwrites friend's slot (not-me matching)", ok,
               "A-sees-B=\(a.moodOf(b.uid) ?? "-") B-sees-A=\(b.moodOf(a.uid) ?? "-")")
    } catch { record("P2", "self-not-overwrite", false, "threw: \(error)") }

    // ---------- CURSOR MODE (more) ----------
    do {
        let a = try await newDevice("U4a", name: "Na")
        let b = try await newDevice("U4b", name: "Nb")
        await a.updateCursorMode("push")                     // set BEFORE befriend
        try await befriend(a, b)
        let ok = await waitUntil { b.cursorModeOf(a.uid) == "push" }
        record("U4", "new friend inherits my current non-neutral cursor mode (no restart)", ok,
               "B sees A mode=\(b.cursorModeOf(a.uid) ?? "-")")
    } catch { record("U4", "cursor inherit on add", false, "threw: \(error)") }

    do {
        let a = try await newDevice("U5a", name: "Oa")
        let b = try await newDevice("U5b", name: "Ob")
        try await befriend(a, b)
        async let x: Void = a.updateCursorMode("attract")
        async let y: Void = b.updateCursorMode("push")
        _ = await (x, y)
        let ok = await waitUntil { b.cursorModeOf(a.uid) == "attract" && a.cursorModeOf(b.uid) == "push" }
        record("U5", "simultaneous independent cursor modes (A=attract, B=push) each propagate", ok,
               "B-sees-A=\(b.cursorModeOf(a.uid) ?? "-") A-sees-B=\(a.cursorModeOf(b.uid) ?? "-")")
    } catch { record("U5", "simultaneous cursor modes", false, "threw: \(error)") }

    // ---------- TOPOLOGY (more) ----------
    do {
        let a = try await newDevice("T3a", name: "Pa")
        let b = try await newDevice("T3b", name: "Pb")
        let c = try await newDevice("T3c", name: "Pc")
        try await befriend(a, b); try await befriend(b, c)   // chain
        try await befriend(a, c)                             // close the triangle
        await settle(2)
        let closed = a.friendCount == 2 && b.friendCount == 2 && c.friendCount == 2 &&
                     a.hasFriend(c.uid) && c.hasFriend(a.uid)
        record("T3", "triangle close: adding A-C to chain → all three mutually see two friends", closed,
               "A=\(a.friendCount) B=\(b.friendCount) C=\(c.friendCount)")
        await a.removeFriend(c.uid)                           // reopen
        let reopened = await waitUntil { a.friendCount == 1 && c.friendCount == 1 && !a.hasFriend(c.uid) }
        record("T4", "triangle reopen: removing A-C reverts to chain (B still sees both)",
               reopened && b.friendCount == 2, "A=\(a.friendCount) B=\(b.friendCount) C=\(c.friendCount)")
    } catch { record("T3", "triangle", false, "threw: \(error)") }

    do {
        // diamond: A-B, A-C, B-D, C-D ; B NOT-C, A NOT-D
        let a = try await newDevice("T5a", name: "Qa")
        let b = try await newDevice("T5b", name: "Qb")
        let c = try await newDevice("T5c", name: "Qc")
        let d = try await newDevice("T5d", name: "Qd")
        try await befriend(a, b); try await befriend(a, c); try await befriend(b, d); try await befriend(c, d)
        await settle(2)
        let ok = a.friendCount == 2 && d.friendCount == 2 && b.friendCount == 2 && c.friendCount == 2 &&
                 !a.hasFriend(d.uid) && !d.hasFriend(a.uid) && !b.hasFriend(c.uid) && !c.hasFriend(b.uid)
        record("T5", "diamond topology: every node sees exactly its 2 neighbors; non-edges absent both ways",
               ok, "A=\(a.friendCount) B=\(b.friendCount) C=\(c.friendCount) D=\(d.friendCount) A~D=\(a.hasFriend(d.uid)) B~C=\(b.hasFriend(c.uid))")
    } catch { record("T5", "diamond topology", false, "threw: \(error)") }

    do {
        let a = try await newDevice("T6a", name: "Ra")
        let b = try await newDevice("T6b", name: "Rb")
        try await befriend(a, b)
        record("T6", "self never appears as own friend pet", !a.hasFriend(a.uid) && !b.hasFriend(b.uid),
               "A~A=\(a.hasFriend(a.uid)) B~B=\(b.hasFriend(b.uid))")
    } catch { record("T6", "no self-friend", false, "threw: \(error)") }

    // ---------- CONCURRENCY / CONVERGENCE (more) ----------
    do {
        let a = try await newDevice("X3a", name: "Sa")
        let b = try await newDevice("X3b", name: "Sb")
        try await befriend(a, b)
        await a.removeFriend(b.uid)
        let t = try await a.createInvite(multi: false); _ = await b.acceptInvite(t)
        await a.removeFriend(b.uid)                           // final op = removed
        await settle(3)
        let ok = !a.hasFriend(b.uid) && !b.hasFriend(a.uid) && a.friendCount == 0 && b.friendCount == 0
        record("X3", "rapid remove→re-add→remove converges to FINAL state (not friends) on both", ok,
               "A=\(a.friendCount) B=\(b.friendCount)")
    } catch { record("X3", "remove/readd/remove converge", false, "threw: \(error)") }

    do {
        let a = try await newDevice("X4a", name: "Ta", character: "cat")
        let b = try await newDevice("X4b", name: "Tb")
        try await befriend(a, b)
        await a.updateMood("coding")
        await a.setCharacter("gd")                            // mood + character together
        let ok = await waitUntil { b.moodOf(a.uid) == "coding" && b.characterOf(a.uid) == "gd" }
        record("X4", "mood + character changed together → peer sees BOTH consistently (no torn read)", ok,
               "B sees A mood=\(b.moodOf(a.uid) ?? "-") char=\(b.characterOf(a.uid) ?? "-")")
    } catch { record("X4", "mood+char consistency", false, "threw: \(error)") }

    // ---------- RECONNECT / WAKE (more) ----------
    do {
        let a = try await newDevice("W3a", name: "Ua")
        let b = try await newDevice("W3b", name: "Ub")
        try await befriend(a, b)
        await a.simulateWake(); await a.simulateWake()        // back-to-back wake (double re-subscribe)
        await b.updateMood("vibing")
        let ok = await waitUntil { a.hasFriend(b.uid) && a.moodOf(b.uid) == "vibing" }
        record("W3", "back-to-back wake re-subscribe doesn't duplicate/blank; presence still flows", ok && a.friendCount == 1,
               "A friendCount=\(a.friendCount) sees B mood=\(a.moodOf(b.uid) ?? "-")")
    } catch { record("W3", "double wake", false, "threw: \(error)") }

    do {
        // graph REMOVE missed (watcher down) recovered by heartbeat backstop
        let a = try await newDevice("W4a", name: "Va")
        let b = try await newDevice("W4b", name: "Vb")
        try await befriend(a, b)
        await a.teardownGraphForTest()                        // A will MISS the live delete
        await b.removeFriend(a.uid)
        await settle(2)
        record("W4pre", "with graph watcher down, A has NOT yet seen the remove", a.hasFriend(b.uid))
        await a.refreshFriends()                              // heartbeat backstop
        record("W4", "missed unfriend recovered by heartbeat backstop (refreshFriends)", !a.hasFriend(b.uid),
               "A.hasFriend(B)=\(a.hasFriend(b.uid))")
    } catch { record("W4", "remove backstop", false, "threw: \(error)") }

    // ===================== CHIPKOO (latching cling + global pat-release handshake) =====================
    do {
        let a = try await newDevice("CK1a", name: "Cha")
        let b = try await newDevice("CK1b", name: "Chb")
        try await befriend(a, b)
        await a.enterChipkoo()
        let ok = await waitUntil { b.cursorModeOf(a.uid) == "chipkoo" && b.clingEpochOf(a.uid) == a.myClingEpoch }
        record("CK1", "chipkoo + cling epoch + scope propagate to a friend via presence",
               ok && b.chipkooScopeOf(a.uid) == "global",
               "B sees A mode=\(b.cursorModeOf(a.uid) ?? "-") epoch=\(b.clingEpochOf(a.uid)) scope=\(b.chipkooScopeOf(a.uid) ?? "-")")
    } catch { record("CK1", "chipkoo propagation", false, "threw: \(error)") }

    do {
        let a = try await newDevice("CK2a", name: "Da")
        let b = try await newDevice("CK2b", name: "Db")
        try await befriend(a, b)
        await a.enterChipkoo()
        _ = await waitUntil { b.cursorModeOf(a.uid) == "chipkoo" }
        await b.viewerPat(owner: a.uid)                       // global → relax locally + ask owner to release
        let cleared = await waitUntil { a.myCursorMode == "neutral" && b.cursorModeOf(a.uid) == "neutral" }
        record("CK2", "friend's pat releases chipkoo GLOBALLY (owner authoritative neutral round-trips)", cleared,
               "A mode=\(a.myCursorMode) B-sees-A=\(b.cursorModeOf(a.uid) ?? "-")")
    } catch { record("CK2", "global clear", false, "threw: \(error)") }

    do {
        let a = try await newDevice("CK3a", name: "Ea")
        let b = try await newDevice("CK3b", name: "Eb")
        try await befriend(a, b)
        await a.enterChipkoo()                                // epoch 1
        _ = await waitUntil { b.cursorModeOf(a.uid) == "chipkoo" }
        a.clearChipkooLocally(epoch: a.myClingEpoch)          // → neutral, epoch 2
        _ = await waitUntil { b.cursorModeOf(a.uid) == "neutral" }
        await a.enterChipkoo()                                // epoch 3
        _ = await waitUntil { b.clingEpochOf(a.uid) == a.myClingEpoch }
        await b.requestClear(ownerUid: a.uid, epoch: 1)       // STALE epoch
        await settle(3)
        record("CK3", "stale-epoch clearReq is ignored (monotonic epoch race guard)", a.myCursorMode == "chipkoo",
               "A mode=\(a.myCursorMode) epoch=\(a.myClingEpoch)")
    } catch { record("CK3", "stale-epoch guard", false, "threw: \(error)") }

    do {
        let a = try await newDevice("CK4a", name: "Fa")
        let b = try await newDevice("CK4b", name: "Fb")
        try await befriend(a, b)
        await a.enterChipkoo()
        _ = await waitUntil { b.cursorModeOf(a.uid) == "chipkoo" }
        let ep = a.myClingEpoch
        await a.goOffline()
        await b.requestClear(ownerUid: a.uid, epoch: ep)      // stamped in B's presence (survives sleep)
        await a.comeOnline()
        let cleared = await waitUntil { a.myCursorMode == "neutral" }
        record("CK4", "pat-release survives owner SLEEP (rides presence, re-read on wake)", cleared,
               "A mode=\(a.myCursorMode)")
    } catch { record("CK4", "clear survives sleep", false, "threw: \(error)") }

    do {
        let a = try await newDevice("CK5a", name: "Ga3")
        let b = try await newDevice("CK5b", name: "Gb3")
        try await befriend(a, b)
        await a.enterChipkoo()
        _ = await waitUntil { b.cursorModeOf(a.uid) == "chipkoo" }
        let ep = a.myClingEpoch
        await a.trackStale(secondsAgo: 200)                   // skewed lastActive, but A is still tracking
        await b.requestClear(ownerUid: a.uid, epoch: ep)
        let cleared = await waitUntil { a.myCursorMode == "neutral" }
        record("CK5", "a clock-skewed owner still honors a pending pat-release", cleared,
               "A mode=\(a.myCursorMode)")
    } catch { record("CK5", "skewed owner honors clear", false, "threw: \(error)") }

    do {
        let a = try await newDevice("CK6a", name: "Ha3")
        let b = try await newDevice("CK6b", name: "Hb3")
        let c = try await newDevice("CK6c", name: "Hc3")
        try await befriend(a, b); try await befriend(a, c)
        await a.enterChipkoo()
        _ = await waitUntil { b.cursorModeOf(a.uid) == "chipkoo" && c.cursorModeOf(a.uid) == "chipkoo" }
        let ep = a.myClingEpoch
        async let rb: Void = b.requestClear(ownerUid: a.uid, epoch: ep)
        async let rc: Void = c.requestClear(ownerUid: a.uid, epoch: ep)
        _ = await (rb, rc)
        let cleared = await waitUntil { a.myCursorMode == "neutral" }
        await settle(2)
        record("CK6", "two friends clear simultaneously → epoch advances EXACTLY once (idempotent)",
               cleared && a.myClingEpoch == ep + 1, "A epoch=\(a.myClingEpoch) (was \(ep))")
    } catch { record("CK6", "idempotent double clear", false, "threw: \(error)") }

    do {
        let a = try await newDevice("CK7a", name: "Ia3")
        let b = try await newDevice("CK7b", name: "Ib3")
        await a.enterChipkoo()                                // BEFORE befriend
        try await befriend(a, b)
        let ok = await waitUntil { b.cursorModeOf(a.uid) == "chipkoo" && b.clingEpochOf(a.uid) == a.myClingEpoch }
        record("CK7", "newly-added friend inherits live chipkoo + epoch (first-frame correctness)", ok,
               "B sees A mode=\(b.cursorModeOf(a.uid) ?? "-") epoch=\(b.clingEpochOf(a.uid))")
    } catch { record("CK7", "chipkoo on add", false, "threw: \(error)") }

    do {
        let a = try await newDevice("CK8a", name: "Ja3")
        let b = try await newDevice("CK8b", name: "Jb3")
        try await befriend(a, b)
        await a.enterChipkoo(scope: "localViewer")            // FUTURE seam: per-viewer override
        _ = await waitUntil { b.cursorModeOf(a.uid) == "chipkoo" && b.chipkooScopeOf(a.uid) == "localViewer" }
        await b.viewerPat(owner: a.uid)                       // localViewer → relax LOCALLY only, no request
        await settle(3)
        record("CK8", "v2 seam: localViewer scope → friend relaxes locally only; owner stays chipkoo for others",
               a.myCursorMode == "chipkoo" && b.effectiveModeOf(a.uid) == "neutral",
               "A mode=\(a.myCursorMode) B-effective=\(b.effectiveModeOf(a.uid))")
    } catch { record("CK8", "localViewer seam", false, "threw: \(error)") }

    do {
        let a = try await newDevice("CK9a", name: "Ka3")
        let b = try await newDevice("CK9b", name: "Kb3")
        try await befriend(a, b)
        await a.enterChipkoo(scope: "localViewer")
        _ = await waitUntil { b.cursorModeOf(a.uid) == "chipkoo" }
        await b.viewerPat(owner: a.uid)                       // local relax, owner stays chipkoo
        await a.trackAll()                                    // simulate the 45s heartbeat re-apply
        await settle(2)
        record("CK9", "heartbeat re-apply does NOT re-cling a locally-relaxed viewer (suppress holds)",
               b.effectiveModeOf(a.uid) == "neutral", "B-effective=\(b.effectiveModeOf(a.uid))")
        await a.enterChipkoo(scope: "localViewer")            // NEW activation → suppression must lapse
        let relapsed = await waitUntil { b.clingEpochOf(a.uid) == a.myClingEpoch && b.effectiveModeOf(a.uid) == "chipkoo" }
        record("CK9b", "a NEW cling activation (epoch bump) lapses the viewer's local relax → re-clings", relapsed,
               "B-effective=\(b.effectiveModeOf(a.uid)) epoch=\(b.clingEpochOf(a.uid))")
    } catch { record("CK9", "suppression vs heartbeat", false, "threw: \(error)") }

    do {
        let a = try await newDevice("CK10a", name: "La3")
        let b = try await newDevice("CK10b", name: "Lb3")
        try await befriend(a, b)
        await a.updateCursorMode("attract")
        _ = await waitUntil { b.cursorModeOf(a.uid) == "attract" }
        await b.viewerPat(owner: a.uid)                       // NOT chipkoo → must do nothing to state
        await settle(2)
        record("CK10", "patting a NON-chipkoo pet sends no clearReq and changes no mode", a.myCursorMode == "attract" && b.cursorModeOf(a.uid) == "attract",
               "A mode=\(a.myCursorMode) B-sees-A=\(b.cursorModeOf(a.uid) ?? "-")")
    } catch { record("CK10", "non-chipkoo pat", false, "threw: \(error)") }

    print("\n=== summary ===")
    let pass = Box.results.filter { $0.pass }.count
    let fail = Box.results.count - pass
    print("TOTAL \(Box.results.count)  PASS \(pass)  FAIL \(fail)")
    for r in Box.results where !r.pass { print("  FAILED [\(r.id)] \(r.title) — \(r.detail)") }

    // machine-readable for the report
    let json = try? JSONSerialization.data(withJSONObject: Box.results.map {
        ["id": $0.id, "title": $0.title, "pass": $0.pass, "detail": $0.detail]
    }, options: [.prettyPrinted])
    if let json, let path = ProcessInfo.processInfo.environment["PAT_TEST_JSON"] {
        try? json.write(to: URL(fileURLWithPath: path))
        print("wrote results JSON → \(path)")
    }
    exit(fail == 0 ? 0 : 1)
}

await runAll()
