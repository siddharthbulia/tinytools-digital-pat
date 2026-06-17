import AppKit
import Combine

/// The brain: watches the frontmost app + idle time, decides the kitten's mood,
/// and drives the Animator (sit / blink / walk / purr / sleep). Walking is triggered
/// externally (drag + wander) via beginWalk/endWalk. Observed by CatView.
@MainActor
final class PetState: ObservableObject {
    @Published var mood: Mood = .neutral {
        // only MY pet publishes its mood to friends; a friend's pet is driven FROM their presence.
        didSet { if mood != oldValue, selfDriven { FriendStore.shared.updateMood(mood.rawValue) } }
    }
    /// Cursor-interaction mode (Attract/Push/Neutral/Chipkoo). Like `mood`, only MY pet publishes it
    /// to friends; a friend's pet has its mode set FROM their presence (via the CursorReactor, which
    /// OBSERVES this property — never write cursorMode from the reactor). Chipkoo also carries the
    /// cling epoch + reset scope so a pat can release it.
    @Published var cursorMode: CursorMode = .neutral {
        didSet {
            if cursorMode != oldValue, selfDriven {
                FriendStore.shared.updateCursorMode(cursorMode.rawValue, epoch: clingEpoch, scope: chipkooScope.rawValue)
            }
        }
    }
    /// Monotonic counter bumped on every Chipkoo enter AND every release. A friend echoes the epoch
    /// it reacted to; we release only when it matches the current one → stale/duplicate clears are
    /// no-ops, no wall-clock skew. (Owner-minted logical clock.)
    private var clingEpoch = 0
    var chipkooEpoch: Int { clingEpoch }
    /// WHO may release a latched Chipkoo (owner-owned, rides presence). v1 = always `.global`.
    @Published private(set) var chipkooScope: ChipkooResetScope = .global
    @Published var bubble: String? = nil
    /// Bumped on every pat so the view fires floating hearts + a little squash.
    @Published var patPulse: Int = 0
    /// -1…1 — how much the kitten leans/looks toward the cursor (Cursor Glance).
    @Published var gazeLean: CGFloat = 0
    /// Bumped for a quick perk-up hop (e.g. on app switch).
    @Published var perkPulse: Int = 0

    /// Which character's sprites this pet draws. My pet tracks the selected character; a friend's
    /// pet is fixed to their chosen character.
    var character: String
    /// My pet (true) watches the frontmost app + idle to pick its own mood; a friend's pet (false)
    /// is told its mood via `applyExternalMood`.
    let selfDriven: Bool

    let animator = Animator()
    var isHidden = false

    init(character: String = Characters.shared.currentId, selfDriven: Bool = true) {
        self.character = character
        self.selfDriven = selfDriven
    }

    private enum Behavior { case sit, purr }
    private var behavior: Behavior = .sit

    private let tickInterval: TimeInterval = 5
    private let idleThreshold: TimeInterval =
        ProcessInfo.processInfo.environment["PAT_NAP_FAST"] != nil ? 7 : 120  // 2 min → napping
    private var tickTimer: Timer?
    private var bubbleTimer: Timer?
    private var frontMood: Mood = .neutral
    private var frontBundleId: String?

    // MARK: lifecycle

    func start() {
        guard selfDriven else {
            // friend's pet: just render + ambient blinks; mood comes via applyExternalMood
            applyBase()
            scheduleBlink()
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        frontBundleId = front?.bundleIdentifier
        frontMood = Mood.from(bundleId: front?.bundleIdentifier, appName: front?.localizedName)
        mood = frontMood
        applyBase()
        scheduleBlink()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        tickTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }

        showBubble("hi! i'm Pat 🐱", seconds: 4.5)
    }

    /// Drive a friend's pet to a new mood (from presence). Same blink-wipe transition my pet uses.
    func applyExternalMood(_ newMood: Mood) {
        guard newMood != mood else { return }
        mood = newMood
        guard behavior == .sit else { return }
        if mood == .idle {
            applyBase()
        } else if let b = Sprites.named(characterId: character, "blink"), let m = moodImage() {
            animator.play("swap", frames: [b, m], fps: 9, loop: false) { [weak self] in self?.applyBase() }
        } else {
            applyBase()
        }
    }

    // MARK: animation base (what plays when just resting)

    private func moodImage() -> NSImage? { Sprites.image(characterId: character, mood: mood.rawValue) }

    private func applyBase() {
        if mood == .idle {
            if let f = Sprites.named(characterId: character, "idle") { animator.play("sleep", frames: [f], loop: true) }
        } else if let f = moodImage() {
            animator.play("sit-\(mood.rawValue)", frames: [f], loop: true)
        }
    }

    /// The eyes-closed frame for the CURRENT mood (same outfit). Falls back to the generic
    /// neutral blink only for neutral; nil for moods whose eyes are already closed.
    private func blinkFrame() -> NSImage? {
        if let b = Sprites.named(characterId: character, "\(mood.rawValue)-blink") { return b }
        return mood == .neutral ? Sprites.named(characterId: character, "blink") : nil
    }

    /// Occasional natural blink while sitting — uses the per-mood blink so the outfit doesn't flash.
    private func scheduleBlink() {
        let delay = Double.random(in: 3.0...6.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if self.behavior == .sit, self.mood != .idle, self.mood != .vibing,
               let b = self.blinkFrame(), let m = self.moodImage() {
                self.animator.play("blink", frames: [b, m], fps: 8, loop: false)
            }
            self.scheduleBlink()
        }
    }

    // MARK: mood detection

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        Task { @MainActor in
            self.frontBundleId = app.bundleIdentifier
            self.frontMood = Mood.from(bundleId: app.bundleIdentifier, appName: app.localizedName)
            self.evaluate(announce: true)
            if !self.isHidden { self.perk() }   // "oh, you switched" ear-perk + hop
        }
    }

    private func tick() {
        evaluate(announce: false)
    }

    private func evaluate(announce: Bool) {
        let idle = currentIdleSeconds()
        // If a browser is frontmost, refine the mood from the active tab's domain.
        var base = frontMood
        if BrowserMood.isBrowser(frontBundleId), let host = BrowserMood.activeHost(forBundleId: frontBundleId) {
            base = BrowserMood.mood(forHost: host)
        }
        let newMood: Mood = idle >= idleThreshold ? .idle : base
        if newMood != mood {
            let wasNapping = (mood == .idle)
            mood = newMood
            if behavior == .sit {
                // hide the outfit swap behind a quick blink wipe (generic blink), then settle in
                if mood == .idle {
                    applyBase()
                } else if let b = Sprites.named(characterId: character, "blink"), let m = moodImage() {
                    animator.play("swap", frames: [b, m], fps: 9, loop: false) { [weak self] in self?.applyBase() }
                } else {
                    applyBase()
                }
            }
            if !isHidden && (announce || wasNapping || newMood == .idle) {
                showBubble(newMood.randomCaption(), seconds: 2.6)
            }
        }
    }

    private func currentIdleSeconds() -> TimeInterval {
        let anyEvent = CGEventType(rawValue: ~0) ?? .null
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }

    // MARK: interactions

    func pat() {
        behavior = .purr
        patPulse &+= 1
        showBubble(mood.patCaptions.randomElement() ?? "♡", seconds: 1.8)
        if let p = Sprites.named(characterId: character, "pat") { animator.play("purr", frames: [p], loop: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            guard let self, self.behavior == .purr else { return }
            self.behavior = .sit
            self.applyBase()
        }
        // Patting MY own clinging pet releases it (→ broadcast neutral). A friend's pet (selfDriven=false)
        // is owner-authoritative — it routes its pat through FriendStore instead (see FriendPet.onPat).
        if selfDriven { clearChipkoo(epoch: clingEpoch) }
    }

    // MARK: Chipkoo (latching cling — global trigger / future per-viewer override)

    /// Enter the latching cling. Bumps the epoch so a stale clear can't release THIS activation, and
    /// teaches the exit contract in-world (the only way out is a pat).
    func enterChipkoo() {
        clingEpoch += 1
        cursorMode = .chipkoo
        showBubble("hold tight! pat me to let go 🫶", seconds: 3.5)
    }

    /// The ONE place "a pat releases Chipkoo" lives. No-op unless we own this pet, are currently
    /// clinging, and the request matches the live activation. Bumping the epoch makes the release
    /// exactly-once and turns any later/duplicate clear for the same activation into a no-op.
    func clearChipkoo(epoch: Int) {
        guard selfDriven, cursorMode == .chipkoo, epoch == clingEpoch else { return }
        clingEpoch += 1
        cursorMode = .neutral
    }

    // MARK: bubbles

    func showBubble(_ text: String, seconds: TimeInterval) {
        bubble = text
        bubbleTimer?.invalidate()
        bubbleTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.bubble = nil }
        }
    }

    func peek() { showBubble("\(mood.label.lowercased()) \(mood.emoji)", seconds: 2.0) }

    /// Re-render my pet with the newly selected character's sprites (on character switch).
    /// No cache clear — Sprites is character-scoped, so the new character loads lazily without
    /// evicting friends' cached sprites.
    func refreshCharacter() {
        character = Characters.shared.currentId
        behavior = .sit
        applyBase()
    }

    /// Swap a friend's pet to a different character IN PLACE (no panel recreate → no flicker,
    /// keeps its position). Caller should apply the current mood right after.
    func changeCharacter(_ id: String) {
        guard character != id else { return }
        character = id
        behavior = .sit
        applyBase()
    }

    // MARK: ambient reactions (driven by the Roamer)

    /// Lean/look toward the cursor — only while calmly sitting (not napping/purring).
    /// Skips redundant assignments so a moving mouse doesn't needlessly re-render.
    func setGaze(_ x: CGFloat) {
        let v: CGFloat = (behavior == .sit && mood != .idle) ? max(-1, min(1, x)) : 0
        if abs(v - gazeLean) > 0.03 { gazeLean = v }
    }

    /// A quick ear-perk + blink, e.g. when the frontmost app changes.
    func perk() {
        guard behavior == .sit, mood != .idle else { return }
        perkPulse &+= 1
        if let b = blinkFrame(), let m = moodImage() {
            animator.play("perk", frames: [b, m], fps: 11, loop: false)
        }
    }

    /// A tiny settle micro-beat (blink) after a move lands.
    func settle() {
        guard behavior == .sit, mood != .idle, let b = blinkFrame(), let m = moodImage() else { return }
        animator.play("settle", frames: [b, m], fps: 9, loop: false)
    }

    /// Seconds since the last user input — for the Roamer's doze trigger. No permission needed.
    func idleSeconds() -> TimeInterval { currentIdleSeconds() }
}
