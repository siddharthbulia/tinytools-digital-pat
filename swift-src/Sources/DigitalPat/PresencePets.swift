import AppKit
import SwiftUI

/// A friend living on your desktop — the SAME pet as your own (full reactions, blinks, hover
/// transforms, pat → purr + hearts), but driven by THEIR mood (from presence). Touching it does
/// exactly what touching your own pet does (locally). Draggable; right-click → remove friend.
@MainActor
final class FriendPet {
    let uid: String
    let state: PetState
    let panel: NSPanel
    static let size = NSSize(width: 130, height: 92)   // identical to my own pet panel

    var onMoved: ((CGRect) -> Void)?
    var onRemove: (() -> Void)?
    private var grabOffset: CGSize?
    private var reactor: CursorReactor?

    // The owner's synced Chipkoo state, + which activation (epoch) I've locally relaxed by patting.
    private var syncedMode = "neutral"
    private var syncedClingEpoch = 0
    private var syncedScope = "global"
    private var suppressedClingEpoch: Int?   // == syncedClingEpoch ⇒ I patted THIS activation → relaxed locally

    init(uid: String, character: String, mood: String, name: String,
         cursorMode: String, clingEpoch: Int, chipkooScope: String) {
        self.uid = uid
        syncedMode = cursorMode; syncedClingEpoch = clingEpoch; syncedScope = chipkooScope
        state = PetState(character: character, selfDriven: false)
        state.mood = Mood(rawValue: mood) ?? .neutral

        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isMovable = false   // we position it ourselves; let the system move it = jitter
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let view = CatView(
            state: state, anim: state.animator,
            onPat: { [weak self] in self?.handlePat() },                   // touch → react + (if clinging) release
            onDragChanged: { [weak self] t in self?.drag(t) },
            onDragEnded: { [weak self] in self?.dragEnded() }
        ).contextMenu {
            Text(name)
            Button("Remove friend") { [weak self] in self?.onRemove?() }
        }

        panel.contentView = NSHostingView(rootView: view)
        panel.orderFrontRegardless()
        state.start()
        applyMode()   // set state.cursorMode BEFORE the reactor so its $cursorMode sink replays it

        // SAME cursor-reaction engine as my own pet — reacts to THIS machine's cursor using the
        // friend's synced mode. The reactor OBSERVES state.cursorMode (we never call setMode here).
        reactor = CursorReactor(panel: panel, state: state, isEnabled: { [weak self] in
            guard let self else { return false }
            return self.grabOffset == nil && !self.state.isHidden
        })
        reactor?.start()
    }

    var character: String { state.character }

    /// Apply a friend's latest character + mood + cursor mode (+ Chipkoo epoch/scope). Character swaps
    /// IN PLACE (no recreate); mood after so the swapped-in character shows their current mood; the mode
    /// drives how their pet reacts to MY cursor (via state.cursorMode → reactor sink).
    func update(character: String, mood: String, name: String,
                cursorMode: String, clingEpoch: Int, chipkooScope: String) {
        if state.character != character { state.changeCharacter(character) }
        state.applyExternalMood(Mood(rawValue: mood) ?? .neutral)
        syncedMode = cursorMode; syncedClingEpoch = clingEpoch; syncedScope = chipkooScope
        applyMode()
    }

    /// Resolve the owner's synced mode against my local relax: if I patted THIS cling activation
    /// (suppressedClingEpoch == the owner's current epoch), show neutral so the 45s heartbeat re-apply
    /// can't re-cling me before the owner confirms. A new activation (epoch advances) lapses the relax.
    private func applyMode() {
        let m = CursorMode.from(syncedMode)
        let effective: CursorMode = (m == .chipkoo && suppressedClingEpoch == syncedClingEpoch) ? .neutral : m
        state.cursorMode = effective   // selfDriven=false → no rebroadcast; reactor sink applies it
    }

    /// A pat on a FRIEND's pet. Always the local purr/hearts. If it's clinging, optimistically relax it
    /// here (instant feel) — once per activation — and, for the GLOBAL scope, ask the owner to release
    /// it for everyone. (Future .localViewer scope: the local relax above IS the whole effect.)
    private func handlePat() {
        state.pat()   // selfDriven=false → pat() does NOT self-clear; the relax/handshake lives here
        guard CursorMode.from(syncedMode) == .chipkoo, suppressedClingEpoch != syncedClingEpoch else { return }
        suppressedClingEpoch = syncedClingEpoch   // debounce: one relax + at most one request per activation
        applyMode()                               // instant local un-cling
        if (ChipkooResetScope(rawValue: syncedScope) ?? .global) == .global {
            FriendStore.shared.requestClear(ownerUid: uid, epoch: syncedClingEpoch)
        }
    }

    func place(at origin: CGPoint) { panel.setFrameOrigin(origin) }
    var frame: CGRect { panel.frame }
    func close() { reactor?.stop(); panel.orderOut(nil) }

    /// Drag by ABSOLUTE cursor position (like my own pet) — NOT the gesture's relative
    /// translation. Translating while moving the window the gesture is measured against is a
    /// feedback loop = jitter. `t` is ignored on purpose.
    private func drag(_ t: CGSize) {
        let mouse = NSEvent.mouseLocation
        if grabOffset == nil {
            let o = panel.frame.origin
            grabOffset = CGSize(width: mouse.x - o.x, height: mouse.y - o.y)
        }
        guard let g = grabOffset else { return }
        panel.setFrameOrigin(NSPoint(x: mouse.x - g.width, y: mouse.y - g.height))
    }
    private func dragEnded() { grabOffset = nil; onMoved?(panel.frame) }
}

/// Renders ALL your friends as always-present pets on your desktop (Model A — no rooms, no deck).
/// Online friends show their live mood; offline friends nap (idle). Each pet swaps character/mood
/// in place as their presence updates; you can drag them around (positions persist).
@MainActor
final class PresencePetsController: ObservableObject {
    static let shared = PresencePetsController()

    private var friends: [String: Friend] = [:]
    private var pets: [String: FriendPet] = [:]

    private func posKey(_ uid: String) -> String { "pat.deck.pos.\(uid)" }
    private init() {}

    /// Reconcile the on-screen pets with the full friend list.
    func sync(_ list: [Friend]) {
        friends = Dictionary(uniqueKeysWithValues: list.map { ($0.uid, $0) })
        let ids = Set(list.map(\.uid))
        for (uid, pet) in pets where !ids.contains(uid) { pet.close(); pets[uid] = nil }   // unfriended
        for f in list {
            if let pet = pets[f.uid] {
                pet.update(character: f.character, mood: f.mood, name: f.name,
                           cursorMode: f.cursorMode, clingEpoch: f.clingEpoch, chipkooScope: f.chipkooScope)
            } else {
                pets[f.uid] = makePet(f); layoutNew(f.uid)
            }
        }
    }

    private func makePet(_ f: Friend) -> FriendPet {
        let pet = FriendPet(uid: f.uid, character: f.character, mood: f.mood, name: f.name,
                            cursorMode: f.cursorMode, clingEpoch: f.clingEpoch, chipkooScope: f.chipkooScope)
        pet.onRemove = { Task { await FriendStore.shared.removeFriend(f.uid) } }
        pet.onMoved = { [weak self] frame in
            self?.persist(f.uid, frame)
        }
        return pet
    }

    private func persist(_ uid: String, _ frame: CGRect) {
        UserDefaults.standard.set("\(frame.midX),\(frame.midY)", forKey: posKey(uid))
    }

    private func layoutNew(_ uid: String) {
        guard let pet = pets[uid], let vf = NSScreen.main?.visibleFrame else { return }
        if let s = UserDefaults.standard.string(forKey: posKey(uid)) {
            let p = s.split(separator: ",").compactMap { Double($0) }
            if p.count == 2 {
                pet.place(at: CGPoint(x: p[0] - FriendPet.size.width / 2, y: p[1] - FriendPet.size.height / 2)); return
            }
        }
        let n = pets.count - 1                          // tidy default cascade from the top-right
        pet.place(at: CGPoint(x: vf.maxX - 150 - FriendPet.size.width - CGFloat(n % 4) * 120,
                              y: vf.maxY - FriendPet.size.height - 8 - CGFloat(n / 4) * 104))
    }
}
