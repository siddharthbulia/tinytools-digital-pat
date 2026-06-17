import AppKit

/// Pat's ambient life: a smooth, cancellable Glide Engine + a Calm Director that
/// keeps her ~80% resting and only occasionally plays around (screen-only, no window
/// info, zero permissions). Behaviors: Corner Hop, Idle Doze Drift, Cursor Glance,
/// App-Switch Perk-Up, Off-Screen Peek, Edge Cling.
@MainActor
final class Roamer {
    private weak var panel: NSPanel?
    private let state: PetState

    /// Set true while the user is dragging Pat — suppresses roaming + cancels any glide.
    var dragging = false { didSet { if dragging { cancelGlide() } } }
    /// User toggle — when on, Pat stays put (no autonomous movement).
    private(set) var calmMode = false

    // glide
    private var glideTimer: Timer?
    private var glideStart = NSPoint.zero
    private var glideTarget = NSPoint.zero
    private var glideT0 = Date()
    private var glideDur: TimeInterval = 1
    private var glideDone: (() -> Void)?
    private var gliding = false
    /// True while an autonomous glide is in flight — the CursorReactor yields to it (and vice-versa).
    var isGliding: Bool { gliding }

    // director
    private var moveTimer: Timer?
    private var peekTimer: Timer?
    /// When the CursorReactor last moved the pet — autonomous roaming defers for a beat afterward
    /// so a roam tick never yanks a pet the user is actively luring with the cursor.
    private var lastCursorReaction = Date(timeIntervalSince1970: 0)

    init(panel: NSPanel, state: PetState) { self.panel = panel; self.state = state }

    func start() {
        scheduleNextMove()   // gaze + cursor reaction now live in the shared CursorReactor (AppDelegate)
    }

    /// Called by the CursorReactor on each cursor-driven move so roaming yields briefly.
    func noteCursorReaction() { lastCursorReaction = Date() }

    func setCalm(_ on: Bool) {
        calmMode = on
        if on { cancelGlide(); peekTimer?.invalidate(); state.setGaze(0) }
    }

    // MARK: - Glide Engine (eased, 60fps, fully cancellable)

    private func glide(to target: NSPoint, duration: TimeInterval, lean: CGFloat = 0, then: (() -> Void)? = nil) {
        guard let panel else { then?(); return }
        glideTimer?.invalidate()
        glideStart = panel.frame.origin
        glideTarget = target
        glideDur = max(0.12, duration)
        glideT0 = Date()
        glideDone = then
        gliding = true
        if lean != 0 { state.setGaze(lean) }
        glideTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.glideStep() }
        }
    }

    private func glideStep() {
        guard let panel, gliding else { glideTimer?.invalidate(); glideTimer = nil; return }
        let t = min(1, Date().timeIntervalSince(glideT0) / glideDur)
        let e = CGFloat(t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2)   // ease-in-out
        panel.setFrameOrigin(NSPoint(x: glideStart.x + (glideTarget.x - glideStart.x) * e,
                                     y: glideStart.y + (glideTarget.y - glideStart.y) * e))
        if t >= 1 {
            glideTimer?.invalidate(); glideTimer = nil; gliding = false
            state.setGaze(0)
            let d = glideDone; glideDone = nil
            saveOrigin()
            d?()
        }
    }

    private func cancelGlide() {
        glideTimer?.invalidate(); glideTimer = nil
        peekTimer?.invalidate(); peekTimer = nil
        gliding = false; glideDone = nil
        state.setGaze(0)
    }

    private func glideDuration(_ from: NSPoint, _ to: NSPoint) -> TimeInterval {
        let d = hypot(to.x - from.x, to.y - from.y)
        return min(1.25, max(0.6, 0.6 + Double(d) / 1400.0))
    }

    // MARK: - Calm Director

    private func scheduleNextMove() {
        let fast = ProcessInfo.processInfo.environment["PAT_FAST"] != nil
        let delay = fast ? Double.random(in: 5...10) : Double.random(in: 90...125)
        moveTimer?.invalidate()
        moveTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        defer { scheduleNextMove() }
        guard !calmMode, !dragging, !gliding, !state.isHidden, panel != nil else { return }
        if Date().timeIntervalSince(lastCursorReaction) < 2.0 { return }   // pet is busy following the cursor
        if state.idleSeconds() >= 110 { dozeDrift(); return }   // about to nap → drift to a quiet corner
        switch Int.random(in: 0..<10) {
        case 0..<4: cornerHop()
        case 4..<7: wander()        // anywhere, including the middle
        case 7..<9: edgeCling()
        default:    offScreenPeek()
        }
    }

    /// Roam to a random point anywhere on screen (corners, middle, edges — wherever).
    private func wander() {
        guard let panel, let f = vf() else { return }
        let size = panel.frame.size
        let cur = panel.frame.origin
        let inset: CGFloat = 30
        let x = CGFloat.random(in: (f.minX + inset)...(f.maxX - size.width - inset))
        let y = CGFloat.random(in: (f.minY + inset)...(f.maxY - size.height - inset))
        let target = NSPoint(x: x, y: y)
        glide(to: target, duration: glideDuration(cur, target),
              lean: target.x < cur.x ? -0.4 : 0.4) { [weak self] in self?.state.settle() }
    }

    // MARK: - geometry helpers

    private func vf() -> NSRect? { (panel?.screen ?? NSScreen.main)?.visibleFrame }

    private func corners(_ size: NSSize, _ f: NSRect, inset: CGFloat = 18) -> [NSPoint] {
        [NSPoint(x: f.minX + inset, y: f.maxY - size.height - inset),
         NSPoint(x: f.maxX - size.width - inset, y: f.maxY - size.height - inset),
         NSPoint(x: f.minX + inset, y: f.minY + inset),
         NSPoint(x: f.maxX - size.width - inset, y: f.minY + inset)]
    }

    private func dist(_ a: NSPoint, _ b: NSPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    // MARK: - behaviors

    private func cornerHop() {
        guard let panel, let f = vf() else { return }
        let size = panel.frame.size
        let cur = panel.frame.origin
        let mouse = NSEvent.mouseLocation
        // candidate corners we're not already in; prefer the one farthest from the cursor.
        let cands = corners(size, f).filter { dist($0, cur) > 60 }
        guard let target = cands.max(by: { dist($0, mouse) < dist($1, mouse) }) else { return }
        glide(to: target, duration: glideDuration(cur, target),
              lean: target.x < cur.x ? -0.5 : 0.5) { [weak self] in self?.state.settle() }
    }

    private func edgeCling() {
        guard let panel, let f = vf() else { return }
        let size = panel.frame.size
        let cur = panel.frame.origin
        let onLeft = Bool.random()
        let x = onLeft ? f.minX + 10 : f.maxX - size.width - 10
        let y = min(max(cur.y + CGFloat.random(in: -120...120), f.minY + 12), f.maxY - size.height - 12)
        let target = NSPoint(x: x, y: y)
        glide(to: target, duration: glideDuration(cur, target),
              lean: onLeft ? -0.5 : 0.5) { [weak self] in self?.state.settle() }
    }

    private func offScreenPeek() {
        guard let panel, let f = vf() else { return }
        let size = panel.frame.size
        let cur = panel.frame.origin
        let goRight = cur.x > f.midX
        // slide so only a ~22pt sliver remains visible
        let offX = goRight ? f.maxX - 22 : f.minX - (size.width - 22)
        let off = NSPoint(x: offX, y: cur.y)
        glide(to: off, duration: glideDuration(cur, off), lean: goRight ? 0.7 : -0.7) { [weak self] in
            guard let self, let panel = self.panel, let f = self.vf() else { return }
            self.peekTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 1.3...2.2), repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.dragging, !self.calmMode else { return }
                    // peek back to the corner on that side
                    let inX = goRight ? f.maxX - size.width - 18 : f.minX + 18
                    let back = NSPoint(x: inX, y: panel.frame.origin.y)
                    self.glide(to: back, duration: 0.7, lean: goRight ? -0.4 : 0.4) { [weak self] in self?.state.settle() }
                }
            }
        }
    }

    private func dozeDrift() {
        guard let panel, let f = vf() else { return }
        let size = panel.frame.size
        let cur = panel.frame.origin
        // drift to the nearest corner to curl up
        guard let target = corners(size, f).min(by: { dist($0, cur) < dist($1, cur) }) else { return }
        if dist(target, cur) < 30 { return }   // already cozy
        glide(to: target, duration: glideDuration(cur, target), lean: target.x < cur.x ? -0.4 : 0.4)
    }

    private func saveOrigin() {
        guard let panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: "digitalpat.petOrigin")
    }
}
