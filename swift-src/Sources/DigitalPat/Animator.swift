import AppKit
import Combine

/// A tiny sprite-frame player. Publishes the current frame (and horizontal flip)
/// so a SwiftUI view can render it. Plays looping or one-shot clips off a timer.
/// This is the rendering core for the kitten's animation — the seam where a
/// richer runtime (e.g. Rive) could later slot in behind the same interface.
@MainActor
final class Animator: ObservableObject {
    @Published var frame: NSImage?
    @Published var flipX: Bool = false

    private(set) var current: String = ""
    private var clip: [NSImage] = []
    private var idx = 0
    private var fps: Double = 6
    private var loop = true
    private var timer: Timer?
    private var onFinish: (() -> Void)?

    /// Play a clip. If the same looping clip (name+flip) is already running, this is a no-op
    /// so we don't restart it on every state re-evaluation.
    func play(_ name: String,
              frames: [NSImage],
              fps: Double = 6,
              loop: Bool = true,
              flipX: Bool = false,
              onFinish: (() -> Void)? = nil) {
        guard !frames.isEmpty else { return }
        if name == current, loop, self.flipX == flipX, timer != nil { return }

        timer?.invalidate(); timer = nil
        self.current = name
        self.clip = frames
        self.fps = max(1, fps)
        self.loop = loop
        self.flipX = flipX
        self.onFinish = onFinish
        idx = 0
        frame = frames[0]

        // Single-frame clip: nothing to tick. Fire finish for one-shots.
        if frames.count == 1 {
            if !loop { let f = onFinish; self.onFinish = nil; f?() }
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / self.fps, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        idx += 1
        if idx >= clip.count {
            if loop {
                idx = 0
            } else {
                timer?.invalidate(); timer = nil
                idx = clip.count - 1
                frame = clip[idx]
                let f = onFinish; onFinish = nil
                f?()
                return
            }
        }
        frame = clip[idx]
    }

    func stop() { timer?.invalidate(); timer = nil }
    deinit { timer?.invalidate() }   // a looping clip's timer is retained by the run loop; tear it down
}
