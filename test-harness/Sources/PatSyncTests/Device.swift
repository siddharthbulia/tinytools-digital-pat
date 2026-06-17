import Foundation
import Supabase

// MARK: - In-memory auth storage (no Keychain → lets us run many independent
// "devices" in ONE process, which the GUI app can't do because the OS prompts
// per keychain item for unsigned multi-instance runs).
final class InMemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.lock(); store[key] = value; lock.unlock() }
    func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return store[key] }
    func remove(key: String) throws { lock.lock(); store[key] = nil; lock.unlock() }
}

// MARK: - Wire types (VERBATIM copies of FriendStore.swift / Friend) so the
// presence payload + decode behavior matches the shipped app exactly.
struct Friend: Codable, Identifiable, Hashable {
    let uid: String
    var name: String
    var character: String
    var mood: String
    var online: Bool
    var cursorMode: String = "neutral"
    var clingEpoch: Int = 0
    var chipkooScope: String = "global"
    var id: String { uid }
}

struct PresencePayload: Codable {
    let uid: String; let name: String; let character: String; let mood: String; let lastActive: Double
    let cursorMode: String?   // OPTIONAL — older clients omit it; nil decodes fine and means "neutral"
    let clingEpoch: Int?       // MY pet's current Chipkoo activation id (I advertise as owner)
    let chipkooScope: String?  // MY Chipkoo reset scope: "global" | "localViewer"
    let clearReq: Int?         // as VIEWER: clingEpoch I'm asking THIS friend (owner) to release
}

private struct FriendRow: Decodable { let uid: String; let name: String; let active_character: String }

// MARK: - Admin operations (service-role) used only to set up a few states that the
// public client genuinely cannot reach: an EXPIRED invite, and DELETING a user (to test
// the on-delete-cascade of friendships + the void of pending invites). Service-role
// bypasses RLS. Key comes from ENV (never hardcoded).
@MainActor
enum Admin {
    static let key = ProcessInfo.processInfo.environment["PAT_SERVICE_KEY"] ?? ""
    static var available: Bool { !key.isEmpty }
    static let client: SupabaseClient = {
        SupabaseClient(supabaseURL: URL(string: "https://cpfbipbdsokoshzgqvsr.supabase.co")!,
                       supabaseKey: key.isEmpty ? ANON_KEY : key,
                       options: SupabaseClientOptions(auth: .init(storage: InMemoryStorage(),
                                                                  storageKey: "pat.test.admin")))
    }()

    /// Backdate an invite so accept_invite() sees it as expired.
    static func expireInvite(token: String) async throws {
        let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400))
        _ = try await client.from("friend_invites").update(["expires_at": past]).eq("token", value: token).execute()
    }

    /// Delete an auth user (cascades to profiles, friendships, friend_invites via FKs).
    static func deleteUser(uid: String) async throws {
        guard let id = UUID(uuidString: uid) else { return }
        try await client.auth.admin.deleteUser(id: id)
    }
}

/// A single simulated device: a real SupabaseClient + a faithful re-implementation of FriendStore's
/// realtime/RPC logic. Methods marked "VERBATIM" mirror the shipped FriendStore.swift line-for-line so
/// proving the server delivers correctly under THIS logic proves the app's logic.
@MainActor
final class Device {
    let label: String
    let client: SupabaseClient
    private(set) var uid: String = ""

    var myName: String
    var myCharacter: String
    var myMood = "neutral"
    var myCursorMode = "neutral"
    private(set) var myClingEpoch = 0
    var myChipkooScope = "global"
    private var clearReqByFriend: [String: Int] = [:]        // ownerUid -> epoch I'm asking to release
    private var suppressedByOwner: [String: Int] = [:]       // ownerUid -> epoch I relaxed locally (viewer)

    // state mirrored from FriendStore
    private var channels: [String: RealtimeChannelV2] = [:]
    private var subs: [String: RealtimeSubscription] = [:]
    private var live: [String: PresencePayload] = [:]
    private var lastSeen: [String: Date] = [:]               // friendUid -> when WE last got their presence (our clock)
    private var profiles: [String: (name: String, character: String)] = [:]
    private var graphChannel: RealtimeChannelV2?
    private var graphSub: RealtimeSubscription?

    // observability for assertions
    private(set) var friends: [Friend] = []
    private(set) var graphEventCount = 0
    private(set) var graphInserts = 0
    private(set) var graphDeletes = 0

    init(label: String, name: String, character: String) {
        self.label = label
        self.myName = name
        self.myCharacter = character
        let options = SupabaseClientOptions(
            auth: .init(storage: InMemoryStorage(), storageKey: "pat.test.\(label).\(UUID().uuidString)")
        )
        self.client = SupabaseClient(
            supabaseURL: URL(string: "https://cpfbipbdsokoshzgqvsr.supabase.co")!,
            supabaseKey: ANON_KEY,
            options: options
        )
    }

    // MARK: lifecycle

    /// Anonymous sign-in (fresh identity) + profile upsert. Mirrors SupabaseService.ensureSession + start().
    /// Retries on transient 429 rate-limits so a burst of fresh test identities self-heals.
    func start() async throws {
        var attempt = 0
        let s: Session
        while true {
            do { s = try await client.auth.signInAnonymously(); break }
            catch {
                attempt += 1
                let msg = "\(error)"
                let transient = msg.contains("rate_limit") || msg.contains("429") || msg.contains("rate limit")
                if attempt >= 6 || !transient { throw error }
                try await Task.sleep(nanoseconds: UInt64(Double(attempt) * 2.5e9))   // 2.5s,5s,7.5s,…
            }
        }
        uid = s.user.id.uuidString.lowercased()
        _ = try await client.from("profiles")
            .upsert(["uid": uid, "name": myName, "active_character": myCharacter]).execute()
        await refreshFriends()
        await subscribeFriendGraph()
    }

    // MARK: presence channels (VERBATIM FriendStore)

    private func channelTopic(_ a: String, _ b: String) -> String {
        let lo = a.lowercased(), hi = b.lowercased()
        return "friend:\(min(lo, hi)):\(max(lo, hi))"
    }

    private func subscribeFriend(me: String, friend: String) async {
        let ch = client.channel(channelTopic(me, friend))
        let myUidLower = me.lowercased()
        let sub = ch.onPresenceChange { [weak self] action in
            let joins = (try? action.decodeJoins(as: PresencePayload.self)) ?? []
            let leaves = (try? action.decodeLeaves(as: PresencePayload.self)) ?? []
            Task { @MainActor [weak self] in
                guard let self else { return }
                if leaves.contains(where: { $0.uid.lowercased() != myUidLower }) {
                    self.live[friend] = nil; self.lastSeen[friend] = nil
                }
                if let theirs = joins.last(where: { $0.uid.lowercased() != myUidLower }) {
                    self.live[friend] = theirs
                    self.lastSeen[friend] = Date()
                    self.handleChipkooHandshake(friend: friend, theirs: theirs)
                }
                self.publish()
            }
        }
        subs[friend] = sub
        channels[friend] = ch
        await ch.subscribe()
        await track(on: ch, friend: friend)
    }

    /// Mirrors FriendStore.handleChipkooHandshake: owner-side honor a friend's clearReq for my current
    /// activation; viewer-side stop advertising a stale clearReq once the owner's epoch moves on.
    private func handleChipkooHandshake(friend: String, theirs: PresencePayload) {
        if let req = theirs.clearReq, req == myClingEpoch { clearChipkooLocally(epoch: req) }
        if let pending = clearReqByFriend[friend], theirs.clingEpoch != pending {
            clearReqByFriend[friend] = nil
            if let ch = channels[friend] { Task { await track(on: ch, friend: friend) } }
        }
    }

    private func track(on ch: RealtimeChannelV2, friend: String) async {
        try? await ch.track(PresencePayload(uid: uid, name: myName, character: myCharacter,
                                            mood: myMood, lastActive: Date().timeIntervalSince1970,
                                            cursorMode: myCursorMode, clingEpoch: myClingEpoch,
                                            chipkooScope: myChipkooScope, clearReq: clearReqByFriend[friend]))
    }
    func trackAll() async { for (f, ch) in channels { await track(on: ch, friend: f) } }

    /// Track a deliberately-stale payload (lastActive in the past) so the peer computes us OFFLINE
    /// without waiting the real 120s. Tests the staleness boundary.
    func trackStale(secondsAgo: Double) async {
        for (f, ch) in channels {
            try? await ch.track(PresencePayload(uid: uid, name: myName, character: myCharacter,
                                                mood: myMood, lastActive: Date().timeIntervalSince1970 - secondsAgo,
                                                cursorMode: myCursorMode, clingEpoch: myClingEpoch,
                                                chipkooScope: myChipkooScope, clearReq: clearReqByFriend[f]))
        }
    }

    private func publish() {
        let now = Date()
        friends = profiles.map { (uid, prof) -> Friend in
            // Skew-immune liveness: judged by when WE last received their presence (our clock), not by
            // comparing their lastActive timestamp to ours.
            if let p = live[uid], let seen = lastSeen[uid], now.timeIntervalSince(seen) < 120 {
                return Friend(uid: uid, name: p.name, character: p.character, mood: p.mood,
                              online: true, cursorMode: p.cursorMode ?? "neutral",
                              clingEpoch: p.clingEpoch ?? 0, chipkooScope: p.chipkooScope ?? "global")
            }
            return Friend(uid: uid, name: prof.name, character: prof.character, mood: "idle",
                          online: false, cursorMode: "neutral", clingEpoch: 0, chipkooScope: "global")
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // MARK: Chipkoo (mirrors PetState.enterChipkoo/clearChipkoo + FriendStore.requestClear + FriendPet relax)

    /// OWNER: enter the latching cling (bump epoch, advertise via presence).
    func enterChipkoo(scope: String = "global") async {
        myChipkooScope = scope; myClingEpoch += 1; myCursorMode = "chipkoo"; await trackAll()
    }
    /// OWNER: release iff this matches the live activation (idempotent, skew-immune).
    func clearChipkooLocally(epoch: Int) {
        guard myCursorMode == "chipkoo", epoch == myClingEpoch else { return }
        myClingEpoch += 1; myCursorMode = "neutral"; Task { await trackAll() }
    }
    /// VIEWER: ask `ownerUid` to release activation `epoch` (stamped into MY presence — survives sleep).
    func requestClear(ownerUid: String, epoch: Int) async {
        clearReqByFriend[ownerUid] = epoch
        if let ch = channels[ownerUid] { await track(on: ch, friend: ownerUid) }
    }
    /// VIEWER: pat a friend's clinging pet — optimistic local relax (keyed to epoch) + global request.
    func viewerPat(owner: String) async {
        guard cursorModeOf(owner) == "chipkoo", suppressedByOwner[owner] != clingEpochOf(owner) else { return }
        suppressedByOwner[owner] = clingEpochOf(owner)
        if (chipkooScopeOf(owner) ?? "global") == "global" {
            await requestClear(ownerUid: owner, epoch: clingEpochOf(owner))
        }
    }
    /// VIEWER: the mode actually shown for `owner` after my local relax (mirrors FriendPet.applyMode).
    func effectiveModeOf(_ owner: String) -> String {
        let m = cursorModeOf(owner) ?? "neutral"
        return (m == "chipkoo" && suppressedByOwner[owner] == clingEpochOf(owner)) ? "neutral" : m
    }
    func clingEpochOf(_ uid: String) -> Int { friend(uid)?.clingEpoch ?? 0 }
    func chipkooScopeOf(_ uid: String) -> String? { friend(uid)?.chipkooScope }

    // MARK: refresh + graph watcher (VERBATIM FriendStore)

    func refreshFriends() async {
        guard !uid.isEmpty else { return }
        let rows: [FriendRow]
        do { rows = try await client.rpc("my_friends").execute().value }
        catch { return }   // transient → keep existing friends (do NOT wipe)
        profiles = Dictionary(uniqueKeysWithValues: rows.map { ($0.uid, ($0.name, $0.active_character)) })
        for r in rows where channels[r.uid] == nil { await subscribeFriend(me: uid, friend: r.uid) }
        for (fuid, ch) in channels where profiles[fuid] == nil {
            subs[fuid]?.cancel(); subs[fuid] = nil
            await ch.unsubscribe(); await client.removeChannel(ch)
            channels[fuid] = nil; live[fuid] = nil
        }
        publish()
    }

    private func subscribeFriendGraph() async {
        graphSub?.cancel(); graphSub = nil
        if let ch = graphChannel { await ch.unsubscribe(); await client.removeChannel(ch); graphChannel = nil }
        let ch = client.channel("friendships-watch")
        let sub = ch.onPostgresChange(AnyAction.self, schema: "public", table: "friendships") { [weak self] action in
            // Realtime applies RLS to INSERT but NOT to DELETE — a deleted row's old record is
            // broadcast to EVERY table subscriber. Guard on the payload so we only react to
            // friendships that involve US (no global refresh storm on unrelated unfriends).
            let rec: [String: AnyJSON]
            let isDelete: Bool
            switch action {
            case .insert(let a): rec = a.record; isDelete = false
            case .update(let a): rec = a.record; isDelete = false
            case .delete(let a): rec = a.oldRecord; isDelete = true
            }
            let parties = [rec["a_uid"]?.stringValue, rec["b_uid"]?.stringValue].compactMap { $0?.lowercased() }
            Task { @MainActor [weak self] in
                guard let self, parties.contains(self.uid.lowercased()) else { return }
                self.graphEventCount += 1
                if isDelete { self.graphDeletes += 1 } else { self.graphInserts += 1 }
                await self.refreshFriends()
            }
        }
        graphSub = sub
        graphChannel = ch
        await ch.subscribe()
    }

    /// Simulate sleep/wake: tear down everything and re-subscribe (mirrors didWake).
    func simulateWake() async {
        let fuids = Array(channels.keys)
        for f in fuids {
            subs[f]?.cancel(); subs[f] = nil
            if let ch = channels[f] { await ch.unsubscribe(); await client.removeChannel(ch) }
            channels[f] = nil
        }
        for f in fuids { await subscribeFriend(me: uid, friend: f) }
        await subscribeFriendGraph()
        await refreshFriends()
    }

    /// Tear down ONLY the graph watcher (simulate missing live friendship events — the heartbeat
    /// backstop must still reconcile via refreshFriends).
    func teardownGraphForTest() async {
        graphSub?.cancel(); graphSub = nil
        if let ch = graphChannel { await ch.unsubscribe(); await client.removeChannel(ch); graphChannel = nil }
    }

    /// Simulate going offline (leave all presence channels) without tearing down the graph watcher.
    func goOffline() async {
        for (f, ch) in channels {
            subs[f]?.cancel(); subs[f] = nil
            await ch.unsubscribe(); await client.removeChannel(ch)
        }
        channels.removeAll()
        // keep `profiles` so we still know who our friends are (they'll show offline)
        publish()
    }

    /// Re-establish presence after goOffline() (refreshFriends re-subscribes channels for known friends).
    func comeOnline() async { await refreshFriends() }

    // MARK: mutations (VERBATIM FriendStore)

    func updateMood(_ mood: String) async {
        guard myMood != mood else { return }
        myMood = mood
        await trackAll()
    }

    func updateCursorMode(_ mode: String) async {
        guard myCursorMode != mode else { return }
        myCursorMode = mode
        await trackAll()
    }

    func setCharacter(_ id: String) async {
        guard myCharacter != id else { return }
        myCharacter = id
        await trackAll()
        do { try await client.from("profiles").update(["active_character": id]).eq("uid", value: uid).execute() }
        catch {}
    }

    // MARK: friend management (VERBATIM FriendStore)

    func createInvite(multi: Bool = false) async throws -> String {
        try await client.rpc("create_invite", params: ["p_multi": multi]).execute().value
    }

    @discardableResult
    func acceptInvite(_ token: String) async -> (ok: Bool, error: String?) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "digital-pat://add?token=", with: "")
        do {
            _ = try await client.rpc("accept_invite", params: ["p_token": t]).execute()
            await refreshFriends()
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func removeFriend(_ uid: String) async {
        _ = try? await client.rpc("remove_friend", params: ["p_other": uid]).execute()
        await refreshFriends()
    }

    // MARK: assertion accessors

    func hasFriend(_ uid: String) -> Bool { friends.contains { $0.uid == uid } }
    var friendCount: Int { friends.count }
    func friend(_ uid: String) -> Friend? { friends.first { $0.uid == uid } }
    func moodOf(_ uid: String) -> String? { friend(uid)?.mood }
    func characterOf(_ uid: String) -> String? { friend(uid)?.character }
    func cursorModeOf(_ uid: String) -> String? { friend(uid)?.cursorMode }
    func isOnline(_ uid: String) -> Bool { friend(uid)?.online ?? false }

    /// Direct profile read (tests RLS): returns the row if visible, else nil.
    func canReadProfile(of otherUid: String) async -> Bool {
        struct P: Decodable { let uid: String }
        let rows: [P] = (try? await client.from("profiles").select("uid").eq("uid", value: otherUid).execute().value) ?? []
        return !rows.isEmpty
    }

    /// Attempt to directly forge a friendship row (should FAIL — no insert policy).
    func tryForgeFriendship(with otherUid: String) async -> Bool {
        let lo = min(uid, otherUid), hi = max(uid, otherUid)
        do { _ = try await client.from("friendships").insert(["a_uid": lo, "b_uid": hi]).execute(); return true }
        catch { return false }
    }
}
