import AppKit
import QuartzCore
import Combine

/// How a pet reacts to a nearby cursor — the Strategy. Each case encapsulates the algorithm that
/// turns (pet, cursor) geometry into a desired panel-origin target. NEUTRAL = no cursor-driven
/// movement (today's behavior; gaze-lean is handled separately and stays on for ALL modes).
///
/// Deliberately an enum (not protocol + classes): 3 fixed behaviors, Codable-as-String so it rides
/// the presence channel for free, value type, single source of truth. Adding a 4th behavior = a new
/// case + a switch arm. (Head First "Strategy" at the right altitude — the varying algorithm is
/// encapsulated and the CursorReactor context is blind to which case it holds.)
enum CursorMode: String, CaseIterable, Codable {
    case neutral, attract, push, chipkoo

    var label: String {
        switch self {
        case .neutral: return "Neutral"
        case .attract: return "Attract — comes to the cursor"
        case .push:    return "Push — flees the cursor"
        case .chipkoo: return "Chipkoo — clings to the cursor (pat to release)"
        }
    }

    /// Decode-with-default — friend pets read a possibly-absent/garbage string off presence.
    static func from(_ raw: String?) -> CursorMode { CursorMode(rawValue: raw ?? "") ?? .neutral }

    /// The desired panel ORIGIN to ease toward this tick, or nil = no cursor-driven target.
    /// AppKit global/flipped coords. Attract & Push engage at similar (moderate) distances.
    func target(petOrigin: NSPoint, size: NSSize, cursor: NSPoint,
                bounds: NSRect, cfg: CursorReactor.Config) -> NSPoint? {
        guard self != .neutral else { return nil }
        let center = NSPoint(x: petOrigin.x + size.width / 2, y: petOrigin.y + size.height / 2)
        let dx = cursor.x - center.x, dy = cursor.y - center.y
        let dist = hypot(dx, dy)
        guard dist > 0.0001 else { return nil }

        switch self {
        case .neutral:
            return nil

        case .attract:                              // come to the cursor, settle a small gap away
            guard dist <= cfg.radius, dist > cfg.attractGap else { return nil }
            let ux = dx / dist, uy = dy / dist
            let dc = NSPoint(x: cursor.x - ux * cfg.attractGap, y: cursor.y - uy * cfg.attractGap)
            return Self.clampOrigin(center: dc, size: size, bounds: bounds)

        case .push:                                 // keep a personal bubble; flee only when cursor is close
            guard dist < cfg.pushBubble else { return nil }
            // Flee CONTINUOUSLY, straight away from the cursor to the bubble distance. If a wall
            // blocks that axis, redirect the blocked component into the OPEN axis (slide along the
            // wall in the direction the push is already pointing) — smooth, no darting, no trap.
            let halfW = size.width / 2, halfH = size.height / 2
            let minCX = bounds.minX + halfW, maxCX = bounds.maxX - halfW
            let minCY = bounds.minY + halfH, maxCY = bounds.maxY - halfH
            let B = cfg.pushBubble
            let ax = -dx / dist, ay = -dy / dist        // unit vector AWAY from the cursor
            var cx = cursor.x + ax * B, cy = cursor.y + ay * B

            if cx < minCX || cx > maxCX {               // x blocked → put the rest into y
                cx = min(max(cx, minCX), maxCX)
                let remain = (B * B - (cx - cursor.x) * (cx - cursor.x)).squareRoot()
                let dir: CGFloat = abs(ay) > 0.05 ? (ay > 0 ? 1 : -1)
                                                    : (maxCY - cursor.y >= cursor.y - minCY ? 1 : -1)
                cy = min(max(cursor.y + dir * remain, minCY), maxCY)
            } else if cy < minCY || cy > maxCY {        // y blocked → put the rest into x
                cy = min(max(cy, minCY), maxCY)
                let remain = (B * B - (cy - cursor.y) * (cy - cursor.y)).squareRoot()
                let dir: CGFloat = abs(ax) > 0.05 ? (ax > 0 ? 1 : -1)
                                                    : (maxCX - cursor.x >= cursor.x - minCX ? 1 : -1)
                cx = min(max(cursor.x + dir * remain, minCX), maxCX)
            }
            return NSPoint(x: cx - halfW, y: cy - halfH)

        case .chipkoo:                              // CLING: always engage (no radius), sit glued a
                                                    // tiny gap from the cursor and follow it forever.
                                                    // Latches — the only exit is a pat (handled in
                                                    // PetState/FriendStore, never here). Clamped, so a
                                                    // corner-parked cursor yields target==origin → the
                                                    // follower can settle to 0 CPU.
            let ux = dx / dist, uy = dy / dist
            let dc = NSPoint(x: cursor.x - ux * cfg.chipkooGap, y: cursor.y - uy * cfg.chipkooGap)
            return Self.clampOrigin(center: dc, size: size, bounds: bounds)
        }
    }

    /// Origin for a desired CENTER, clamped so the panel stays fully on screen.
    private static func clampOrigin(center: NSPoint, size: NSSize, bounds: NSRect) -> NSPoint {
        NSPoint(x: min(max(center.x - size.width / 2, bounds.minX), bounds.maxX - size.width),
                y: min(max(center.y - size.height / 2, bounds.minY), bounds.maxY - size.height))
    }
}

/// WHO can release a latched Chipkoo. This is OWNER-OWNED and rides presence next to the mode:
/// - `.global` (v1): any pat — by the owner or ANY friend — clears it for everyone.
/// - `.localViewer` (future): each friend must pat to stop the cling on THEIR screen only; the owner
///   stays clung for everyone else.
/// The entire v1→v2 change is the value the owner emits — friend/transport code is already in place.
/// (This is the "global trigger vs local override" category made explicit.)
enum ChipkooResetScope: String, Codable { case global, localViewer }

/// The Strategy CONTEXT + the ONE shared movement engine. Exactly one per pet panel — the own pet
/// AND every friend pet build one identically (the only cursor-reaction code path in the app).
/// Owns a global mouse monitor (gaze on every move, all modes) + a lazily-started 60fps spring
/// follower that self-stops when settled (idle CPU = 0). Neutral = the follower never runs =
/// byte-for-byte today's behavior.
@MainActor
final class CursorReactor {
    struct Config {
        var radius: CGFloat      = 200   // ATTRACT activation: cursor within this → pet comes
        var attractGap: CGFloat  = 55    // attract settles this far from the cursor (noses up, no jitter)
        var pushBubble: CGFloat  = 120   // PUSH personal bubble: flee only when cursor is within this,
                                         // and keep ~this distance — a close, comfortable range,
                                         // NOT a far fling.
        var chipkooGap: CGFloat  = 28    // CHIPKOO sits this close to the cursor — reads as "glued"
                                         // while keeping the click hotspot out of the sprite hit-rect.
        var stiffness: CGFloat   = 9.0   // spring k (snappier chase)
        var damping: CGFloat     = 0.86  // velocity retained/tick → critically-damped, no overshoot
        var maxSpeed: CGFloat    = 1400  // px/sec cap → never teleports on a fast flick
        var restEpsilon: CGFloat = 0.5   // settle threshold (px) → stop the loop
    }

    private weak var panel: NSPanel?
    private let state: PetState
    private let cfg = Config()
    private var mode: CursorMode = .neutral
    /// Host veto: own pet → !dragging && !gliding && !hidden && !calm; friend pet → !dragging && !hidden.
    private let isEnabled: () -> Bool
    /// Called on each reactor move so the own pet's Roamer can yield (nil for friend pets).
    var onActiveMove: (() -> Void)?

    private var monitor: Any?
    private var link: Timer?
    private var lastTime = CACurrentMediaTime()
    private var vel = CGVector.zero
    private var cursor = NSEvent.mouseLocation
    private var running = false
    private var modeSub: AnyCancellable?

    init(panel: NSPanel, state: PetState, isEnabled: @escaping () -> Bool) {
        self.panel = panel; self.state = state; self.isEnabled = isEnabled
        // INVARIANT: the reactor OBSERVES cursorMode and MUST NEVER write it — assigning
        // state.cursorMode from here would create a Combine feedback loop. setMode() only mutates
        // the reactor's own `mode`. This single sink is the ONE wiring path for own AND friend pets:
        // anything (menu, pat, presence) that changes state.cursorMode drives the reactor here.
        // @Published replays its current value on subscribe, so the initial mode arrives with no race.
        modeSub = state.$cursorMode.sink { [weak self] m in
            Task { @MainActor in self?.setMode(m) }
        }
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in self?.onMouse() }
        }
    }

    func stop() {
        modeSub?.cancel(); modeSub = nil
        if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil
        suspend()
    }
    deinit { if let m = monitor { NSEvent.removeMonitor(m) } }

    /// Re-arm the follower even if the cursor is still (e.g. after a drag ends or the pet un-hides
    /// while latched in Chipkoo) — otherwise it would wait for the next mouse move to re-close the gap.
    func kick() { ensureRunning() }

    func setMode(_ m: CursorMode) {
        guard m != mode else { return }
        mode = m
        if m == .neutral { state.setGaze(0) }
        ensureRunning()
    }

    /// Stop the follower without tearing down the monitor (drag start / own-pet glide / settle).
    func suspend() { link?.invalidate(); link = nil; running = false; vel = .zero }

    private func onMouse() {
        cursor = NSEvent.mouseLocation
        if let panel, isEnabled() {     // gaze-lean — SAME in every mode (this is today's behavior)
            let c = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
            let d = hypot(cursor.x - c.x, cursor.y - c.y)
            state.setGaze(d < 280 ? (cursor.x - c.x) / 160 : 0)
        }
        ensureRunning()
    }

    private func ensureRunning() {
        guard !running, panel != nil else { return }
        guard mode != .neutral || hypot(vel.dx, vel.dy) > cfg.restEpsilon else { return }
        running = true
        lastTime = CACurrentMediaTime()
        link = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
    }

    private func step() {
        guard let panel else { suspend(); return }
        guard isEnabled() else { state.setGaze(0); suspend(); return }   // dragging/gliding/hidden/calm → hands off

        let now = CACurrentMediaTime()
        let dt = min(1.0 / 30.0, max(1.0 / 240.0, now - lastTime))       // clamp dt across sleep/stall
        lastTime = now

        let origin = panel.frame.origin
        // Chipkoo can chase the cursor across displays → clamp to the screen UNDER the cursor (not
        // panel.screen, which would strand the pet on its origin display). Other modes keep the
        // existing same-screen clamp.
        let bounds: NSRect = {
            if mode == .chipkoo, let s = NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) }) {
                return s.visibleFrame
            }
            return (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        }()
        let target = mode.target(petOrigin: origin, size: panel.frame.size, cursor: cursor, bounds: bounds, cfg: cfg)

        if let target {
            let toX = target.x - origin.x, toY = target.y - origin.y
            vel.dx = (vel.dx + cfg.stiffness * toX * dt) * cfg.damping   // semi-implicit Euler spring
            vel.dy = (vel.dy + cfg.stiffness * toY * dt) * cfg.damping
            let sp = hypot(vel.dx, vel.dy) / dt
            if sp > cfg.maxSpeed { let s = cfg.maxSpeed / sp; vel.dx *= s; vel.dy *= s }
            let nx = min(max(origin.x + vel.dx, bounds.minX), bounds.maxX - panel.frame.width)
            let ny = min(max(origin.y + vel.dy, bounds.minY), bounds.maxY - panel.frame.height)
            panel.setFrameOrigin(NSPoint(x: nx, y: ny))
            onActiveMove?()
            // Settle when we're AT the target and barely moving — for ANY mode (a latching mode like
            // Chipkoo with a corner-parked cursor would otherwise spin the loop at 60fps forever).
            // A cursor move re-arms us via onMouse → ensureRunning.
            if hypot(toX, toY) < cfg.restEpsilon && hypot(vel.dx, vel.dy) < cfg.restEpsilon { suspend() }
        } else {
            vel.dx *= cfg.damping; vel.dy *= cfg.damping                 // decay residual, then stop (0 idle CPU)
            if hypot(vel.dx, vel.dy) < cfg.restEpsilon { suspend() }
        }
    }
}
