import AppKit
import Combine
import Network
import Supabase

/// A friend and their live state. `mood` is "idle" when they're offline.
struct Friend: Codable, Identifiable, Hashable {
    let uid: String
    var name: String
    var character: String
    var mood: String
    var online: Bool
    var cursorMode: String = "neutral"   // attract/push/neutral/chipkoo, synced from the friend's presence
    var clingEpoch: Int = 0              // the owner's current Chipkoo activation id (for the pat-release handshake)
    var chipkooScope: String = "global"  // who may release a latched Chipkoo (v1 always "global")
    var id: String { uid }
}

/// What we publish about ourselves on each friendship channel. The Chipkoo fields are all OPTIONAL
/// so a friend running an older build (no field) decodes fine → nil → safe defaults.
private struct PresencePayload: Codable {
    let uid: String; let name: String; let character: String; let mood: String; let lastActive: Double
    let cursorMode: String?    // OPTIONAL — older clients omit it; nil decodes fine and means "neutral"
    let clingEpoch: Int?       // MY pet's current Chipkoo activation id (I advertise it as the owner)
    let chipkooScope: String?  // MY Chipkoo reset scope (owner-owned): "global" | "localViewer"
    let clearReq: Int?         // as a VIEWER: the clingEpoch I'm asking THIS friend (the owner) to release
}

/// A friendship-level (EDGE) attribute: a `global` default I publish to every friend, plus optional
/// PER-FRIEND overrides. `resolve(friend)` is the value stamped on THAT friend's presence frame —
/// `override ?? global`. This is the generic seam for *directed* state (A→B can differ from A→C):
/// because every frame is published on a single 1:1 channel, varying a field per friend makes it
/// directed, and it's invisible on the wire (the receiver just reads my frame on our edge — zero
/// receive-side change). NODE attributes (mood, character, name) stay plain scalars — there's no
/// product meaning to "happy toward Alice but sad toward Bob". Adding a future directed attribute =
/// one EdgeAttr + one optional PresencePayload field + one `resolve(friend)` in track().
/// (`clearReq` is the first instance; directed-Chipkoo and 1:1 messaging are designed to ride this.)
struct EdgeAttr<V> {
    var global: V
    var byFriend: [String: V] = [:]
    func resolve(_ friend: String) -> V { byFriend[friend] ?? global }
}

/// The friend graph (Model A): mutual 1:1 friendships, no rooms. Presence is per-friendship —
/// each friendship gets a private Realtime channel `friend:<loUid>:<hiUid>` that both parties
/// track on and read from. All friends are always "present" (online → live mood, offline → idle).
@MainActor
final class FriendStore: ObservableObject {
    static let shared = FriendStore()

    @Published private(set) var friends: [Friend] = []
    @Published private(set) var ready = false

    /// Set by AppDelegate to render friends as always-on desktop pets.
    var onFriendsChanged: (([Friend]) -> Void)?
    /// Set by AppDelegate: invoked with the epoch when a friend's presence asks ME to release my pet's
    /// Chipkoo (their clearReq == my current clingEpoch). The handler routes to PetState.clearChipkoo,
    /// which re-checks the epoch — so a stale/duplicate request is a harmless no-op.
    var onMyPetClearRequested: ((Int) -> Void)?

    private let client = SupabaseService.shared.client
    private var channels: [String: RealtimeChannelV2] = [:]              // friendUid -> channel
    private var subs: [String: RealtimeSubscription] = [:]
    private var live: [String: PresencePayload] = [:]                    // friendUid -> their presence
    private var lastSeen: [String: Date] = [:]                           // friendUid -> when WE last got their presence (our clock)
    private var profiles: [String: (name: String, character: String)] = [:]
    private var heartbeat: Timer?
    private var graphChannel: RealtimeChannelV2?                          // listens for friendship add/remove
    private var graphSub: RealtimeSubscription?
    private let netMonitor = NWPathMonitor()                             // self-heal presence after a network drop
    private var netSatisfied = true
    private var rtStatusSub: RealtimeSubscription?                       // self-heal after a SILENT socket drop
    private var rtWasDown = false                                        // saw a disconnect since arming
    private var rtArmed = false                                          // ignore the initial connect

    private var myUID: String?
    private var myName = UserDefaults.standard.string(forKey: "pat.me.name") ?? "friend"
    private var myCharacter = Characters.shared.currentId
    private var myMood = "neutral"
    private var myCursorMode = UserDefaults.standard.string(forKey: "pat.me.cursorMode") ?? "neutral"
    private var myClingEpoch = 0           // MY pet's current Chipkoo activation (advertised as owner)
    private var myChipkooScope = "global"
    // The one EDGE attribute today: a per-friend (directed) clear request. Pure-directed (no global),
    // so global = nil and absence of an override means "no request". Generalizes via EdgeAttr.
    private var edgeClearReq = EdgeAttr<Int?>(global: nil)   // ownerUid -> epoch I'm asking them to release

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        // Sleep/wake isn't the only thing that kills the Realtime socket — a plain network drop
        // (Wi-Fi blip, VPN flap) does too, and supabase-swift doesn't always cleanly re-establish
        // presence afterward. Watch the network path and, the moment it comes back, fully re-subscribe
        // + re-track (same path as didWake) so a clung/online friend isn't stranded as "napping" until
        // the next relaunch.
        netMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = (path.status == .satisfied)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let recovered = satisfied && !self.netSatisfied
                self.netSatisfied = satisfied
                if recovered, self.ready { await self.resubscribeAll() }
            }
        }
        netMonitor.start(queue: DispatchQueue(label: "ai.bulia.pat.net"))

        // The realtime socket can also drop SILENTLY (server idle-timeout, transient stall) without any
        // network-path change — supabase-swift auto-reconnects + re-joins channels, but presence track()
        // is a one-shot message that is NOT re-sent on rejoin, so MY mood/character/online state stops
        // reaching friends (they mark me offline → "napping", and my changes don't reflect). Observe the
        // connection status and, on a RE-connect (after a drop), re-establish + re-track everything.
        rtStatusSub = client.realtimeV2.onStatusChange { [weak self] status in
            Task { @MainActor [weak self] in self?.handleRealtimeStatus(status) }
        }
    }

    private func handleRealtimeStatus(_ status: RealtimeClientStatus) {
        guard rtArmed else { return }   // ignore the initial connect during start()
        switch status {
        case .disconnected: rtWasDown = true
        case .connected:
            if rtWasDown { rtWasDown = false; Task { await resubscribeAll() } }   // re-track presence after reconnect
        case .connecting: break
        @unknown default: break
        }
    }

    var myDisplayName: String { myName }
    var hasOnboarded: Bool { UserDefaults.standard.string(forKey: "pat.me.name") != nil }

    // MARK: lifecycle

    func start(name: String, character: String) async {
        myName = name; myCharacter = character
        guard let uid = await SupabaseService.shared.ensureSession() else { return }  // don't onboard if sign-in fails
        myUID = uid
        UserDefaults.standard.set(name, forKey: "pat.me.name")   // mark onboarded only after a real session
        _ = try? await client.from("profiles")
            .upsert(["uid": uid, "name": name, "active_character": character]).execute()
        ready = true
        await refreshFriends()
        await subscribeFriendGraph()   // live-add/remove → no restart needed on either side
        startHeartbeat()
        rtArmed = true                 // now react to realtime reconnects (not the initial connect)
    }

    private struct FriendRow: Decodable { let uid: String; let name: String; let active_character: String }

    func refreshFriends() async {
        guard let uid = myUID else { return }
        // Distinguish a transient RPC failure from a genuine "zero friends": a thrown error must
        // NOT be coalesced to [], or it would tear down every channel and wipe every pet.
        let rows: [FriendRow]
        do { rows = try await client.rpc("my_friends").execute().value }
        catch {
            NSLog("Digital Pat: my_friends refresh failed, keeping existing friends: \(error.localizedDescription)")
            return
        }
        profiles = Dictionary(uniqueKeysWithValues: rows.map { ($0.uid, ($0.name, $0.active_character)) })
        for r in rows where channels[r.uid] == nil { await subscribeFriend(me: uid, friend: r.uid) }
        for (fuid, ch) in channels where profiles[fuid] == nil {        // unfriended → drop channel
            subs[fuid]?.cancel(); subs[fuid] = nil
            await ch.unsubscribe(); await client.removeChannel(ch)
            channels[fuid] = nil; live[fuid] = nil
        }
        publish()
    }

    private func channelTopic(_ a: String, _ b: String) -> String {
        // Both parties MUST compute the identical topic, so normalize case before ordering.
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
                // This channel has exactly two members; anyone who isn't me IS the friend.
                // Matching on "not me" (rather than an exact uid) is robust to any uid formatting
                // drift between the presence payload and the my_friends row.
                // leaves before joins (a re-track is leave(old)+join(new)).
                if leaves.contains(where: { $0.uid.lowercased() != myUidLower }) {
                    self.live[friend] = nil; self.lastSeen[friend] = nil
                }
                if let theirs = joins.last(where: { $0.uid.lowercased() != myUidLower }) {
                    self.live[friend] = theirs
                    self.lastSeen[friend] = Date()   // stamp on OUR clock — liveness must not compare two machines' clocks
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

    /// The two halves of the pat-release handshake, evaluated from a friend's latest presence frame:
    /// 1. As OWNER: if the friend is asking me to release MY current activation (their clearReq == my
    ///    clingEpoch), fire the closure → PetState.clearChipkoo (which re-checks & bumps the epoch).
    /// 2. As VIEWER: once the friend's (owner's) epoch has moved past the clear I asked for, stop
    ///    advertising my stale clearReq (so it can never accidentally match a future activation,
    ///    e.g. after the owner restarts and the epoch resets).
    private func handleChipkooHandshake(friend: String, theirs: PresencePayload) {
        if let req = theirs.clearReq, req == myClingEpoch {
            onMyPetClearRequested?(req)
        }
        if let pending = (edgeClearReq.byFriend[friend] ?? nil), theirs.clingEpoch != pending {
            edgeClearReq.byFriend[friend] = nil
            if let ch = channels[friend] { Task { await track(on: ch, friend: friend) } }
        }
    }

    /// One channel watching the `friendships` table. When a friendship row is inserted (someone
    /// accepted my invite, or I accepted theirs) or deleted (an unfriend), re-pull the graph so the
    /// new friend's pet appears — or a removed one disappears — on BOTH desktops without a restart.
    private func subscribeFriendGraph() async {
        graphSub?.cancel(); graphSub = nil
        if let ch = graphChannel { await ch.unsubscribe(); await client.removeChannel(ch); graphChannel = nil }
        let ch = client.channel("friendships-watch")
        let sub = ch.onPostgresChange(AnyAction.self, schema: "public", table: "friendships") { [weak self] action in
            // Realtime applies RLS to INSERT but NOT to DELETE — a deleted row's old record is
            // broadcast to EVERY subscriber of this table. Guard on the payload so we only react to
            // friendships that involve US: otherwise every unrelated unfriend would trigger a global
            // refreshFriends() storm (and we'd be acting on another pair's data). INSERTs are already
            // RLS-scoped to the two parties; this makes DELETEs behave the same way client-side.
            let rec: [String: AnyJSON]
            switch action {
            case .insert(let a): rec = a.record
            case .update(let a): rec = a.record
            case .delete(let a): rec = a.oldRecord
            }
            let parties = [rec["a_uid"]?.stringValue, rec["b_uid"]?.stringValue].compactMap { $0?.lowercased() }
            Task { @MainActor [weak self] in
                guard let self, let me = self.myUID?.lowercased(), parties.contains(me) else { return }
                await self.refreshFriends()
            }
        }
        graphSub = sub
        graphChannel = ch
        await ch.subscribe()
    }

    /// `friend` selects the per-channel clearReq (a viewer-side request targets exactly one owner);
    /// the cling epoch + scope are about MY pet so they're identical on every channel.
    private func track(on ch: RealtimeChannelV2, friend: String) async {
        guard let uid = myUID else { return }
        try? await ch.track(PresencePayload(uid: uid, name: myName, character: myCharacter,
                                            mood: myMood, lastActive: Date().timeIntervalSince1970,
                                            cursorMode: myCursorMode, clingEpoch: myClingEpoch,
                                            chipkooScope: myChipkooScope, clearReq: edgeClearReq.resolve(friend)))
    }
    private func trackAll() async { for (f, ch) in channels { await track(on: ch, friend: f) } }

    private func publish() {
        let now = Date()
        friends = profiles.map { (uid, prof) -> Friend in
            // ONLINE = we currently hold their presence AND we've received a fresh frame from them.
            // The freshness window is measured against OUR OWN clock (lastSeen), NOT their lastActive
            // timestamp — comparing a friend's wall clock to ours marks an active friend "offline"
            // whenever the two Macs' clocks differ by more than the window (clock skew). They re-track
            // every ≤45s (heartbeat), so a live friend always lands inside the 120s window.
            if let p = live[uid], let seen = lastSeen[uid], now.timeIntervalSince(seen) < 120 {
                return Friend(uid: uid, name: p.name, character: p.character, mood: p.mood,
                              online: true, cursorMode: p.cursorMode ?? "neutral",
                              clingEpoch: p.clingEpoch ?? 0, chipkooScope: p.chipkooScope ?? "global")
            }
            // Offline → idle + neutral: an offline owner's pet must not keep clinging on my desktop.
            return Friend(uid: uid, name: prof.name, character: prof.character, mood: "idle",
                          online: false, cursorMode: "neutral", clingEpoch: 0, chipkooScope: "global")
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        onFriendsChanged?(friends)
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.trackAll()
                await self.refreshFriends()   // backstop: catches any add/remove the realtime feed dropped
                self.publish()
            }
        }
    }

    @objc private func didWake() {
        guard ready, myUID != nil else { return }
        Task { await resubscribeAll() }
    }

    /// Tear down every presence channel + the graph watcher and re-establish them from scratch, then
    /// reconcile the friend list. Invoked on wake-from-sleep AND on network recovery — both kill the
    /// Realtime socket, and a clean re-subscribe + re-track is the reliable way to get presence flowing
    /// again (so an online friend stops looking like they're "napping").
    private func resubscribeAll() async {
        guard let uid = myUID else { return }
        let fuids = Array(channels.keys)
        for f in fuids {
            subs[f]?.cancel(); subs[f] = nil
            if let ch = channels[f] { await ch.unsubscribe(); await client.removeChannel(ch) }
            channels[f] = nil; lastSeen[f] = nil
        }
        for f in fuids { await subscribeFriend(me: uid, friend: f) }
        await subscribeFriendGraph()
        await refreshFriends()
    }

    /// Manual "Refresh" (Friends window button): same full re-establish as wake / network-recovery —
    /// re-subscribe every presence channel + the graph watcher and reconcile the friend list. The
    /// user's own escape hatch if presence ever looks stuck (a friend wrongly showing "napping").
    func refreshNow() async {
        guard ready, myUID != nil else { await refreshFriends(); return }
        await resubscribeAll()
    }

    // MARK: mutations published by the local pet

    func updateMood(_ mood: String) {
        guard myMood != mood else { return }
        myMood = mood
        if ready { Task { await trackAll() } }
    }

    /// My cursor mode changed → persist locally + republish presence so friends' copies of my pet
    /// react to their cursor with my new mode. Chipkoo also carries the cling epoch + reset scope so a
    /// pat (mine or a friend's) can release it. (Behavior, not durable DB state — no DB write; chipkoo
    /// is coerced back to neutral on next launch by AppDelegate, so persisting it raw is harmless.)
    func updateCursorMode(_ mode: String, epoch: Int, scope: String) {
        let changed = (myCursorMode != mode) || (myClingEpoch != epoch) || (myChipkooScope != scope)
        guard changed else { return }
        myCursorMode = mode; myClingEpoch = epoch; myChipkooScope = scope
        UserDefaults.standard.set(mode, forKey: "pat.me.cursorMode")
        if ready { Task { await trackAll() } }
    }

    /// VIEWER side: ask `ownerUid` to release the Chipkoo activation `epoch` by stamping it into MY
    /// presence on that friendship channel (presence, NOT broadcast — it survives the owner being
    /// asleep/mid-reconnect and is re-read on their wake; a fire-and-forget broadcast would be lost
    /// exactly in that window and the owner would re-advertise clinging forever).
    func requestClear(ownerUid: String, epoch: Int) {
        edgeClearReq.byFriend[ownerUid] = epoch
        if let ch = channels[ownerUid] { Task { await track(on: ch, friend: ownerUid) } }
    }

    /// Best-effort: drop presence on every channel so an owner who quits while clinging un-clings on
    /// friends' desktops immediately (instead of after the 120s staleness fallback).
    func untrackAll() async { for ch in channels.values { await ch.untrack() } }

    func setCharacter(_ id: String) {
        guard myCharacter != id else { return }
        myCharacter = id
        Task {
            await trackAll()
            if let uid = myUID {
                do { try await client.from("profiles").update(["active_character": id]).eq("uid", value: uid).execute() }
                catch { NSLog("Digital Pat: profile character update failed: \(error.localizedDescription)") }
            }
        }
    }

    // MARK: friend management

    func createInvite(multi: Bool = false) async -> String? {
        try? await client.rpc("create_invite", params: ["p_multi": multi]).execute().value
    }

    @discardableResult
    func acceptInvite(_ token: String) async -> Bool {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "digital-pat://add?token=", with: "")
        do {
            _ = try await client.rpc("accept_invite", params: ["p_token": t]).execute()
            await refreshFriends()
            return true
        } catch {
            NSLog("Digital Pat: accept_invite failed: \(error.localizedDescription)")
            return false
        }
    }

    func removeFriend(_ uid: String) async {
        _ = try? await client.rpc("remove_friend", params: ["p_other": uid]).execute()
        await refreshFriends()
    }

    /// Full account reset ("Reset Pat…"): remove me + all my friendships SERVER-side (so every friend
    /// sees me vanish, no orphaned data), tear down all live state, and sign out so the NEXT launch is
    /// a brand-new anonymous identity. The caller (AppDelegate) then clears UserDefaults + relaunches.
    func resetAccount() async {
        _ = try? await client.rpc("delete_my_account").execute()   // friends' graph watchers see the DELETEs → I disappear
        heartbeat?.invalidate(); heartbeat = nil
        for (f, ch) in channels { subs[f]?.cancel(); await ch.unsubscribe(); await client.removeChannel(ch) }
        channels.removeAll(); subs.removeAll(); live.removeAll(); lastSeen.removeAll(); profiles.removeAll()
        graphSub?.cancel(); graphSub = nil
        if let g = graphChannel { await g.unsubscribe(); await client.removeChannel(g) }
        graphChannel = nil
        friends = []; ready = false
        onFriendsChanged?([])                                      // close every friend pet on the desktop
        try? await client.auth.signOut()                           // clears the cached anon session (Keychain)
    }
}
