import SwiftUI

private struct Heart: Identifiable {
    let id = UUID()
    let dx: CGFloat
    let scale: CGFloat
}

private struct HeartView: View {
    let heart: Heart
    @State private var up = false
    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 9 * heart.scale))
            .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.72))
            .offset(x: heart.dx * 0.7, y: up ? -32 : -2)
            .opacity(up ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1.0)) { up = true } }
    }
}

/// Renders the kitten: the current animation frame from the Animator (crisp pixels,
/// flipped to face the walk direction), plus breathing, the pat squash + hearts,
/// the speech bubble, and the drag/pat gesture.
struct CatView: View {
    @ObservedObject var state: PetState
    @ObservedObject var anim: Animator

    var onPat: () -> Void
    var onDragChanged: (CGSize) -> Void
    var onDragEnded: () -> Void

    @State private var breathe = false
    @State private var bounce = false
    @State private var hearts: [Heart] = []
    @State private var heartsGen = 0
    @State private var didDrag = false
    @State private var pressStart: Date?
    // per-mood hover reaction transforms
    @State private var hovering = false
    @State private var reactRot: Double = 0
    @State private var reactY: CGFloat = 0
    @State private var reactX: CGFloat = 0
    @State private var reactScale: CGFloat = 1

    private let petSize: CGFloat = 60   // natively small so the bubble hugs the head

    var body: some View {
        VStack(spacing: 1) {
            bubble.frame(height: 22)
            ZStack {
                spriteFrame
                    .scaleEffect(x: anim.flipX ? -1 : 1, y: 1)
                    .rotationEffect(.degrees(Double(state.gazeLean) * 7), anchor: .bottom)  // lean toward cursor
                    .offset(x: state.gazeLean * 4)
                    .animation(.spring(response: 0.45, dampingFraction: 0.7), value: state.gazeLean)
                ForEach(hearts) { HeartView(heart: $0) }
            }
            .frame(width: petSize, height: petSize)
            .scaleEffect(x: bounce ? 1.06 : 1.0,
                         y: bounce ? 0.94 : (breathe ? 1.015 : 0.99),
                         anchor: .bottom)
            .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: breathe)
            .animation(.spring(response: 0.26, dampingFraction: 0.5), value: bounce)
            // per-mood hover reaction (driven explicitly via withAnimation)
            .rotationEffect(.degrees(reactRot), anchor: .bottom)
            .offset(x: reactX, y: reactY)
            .scaleEffect(reactScale, anchor: .bottom)
        }
        .frame(width: 130, height: 92)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if pressStart == nil { pressStart = Date() }
                    let moved = abs(v.translation.width) + abs(v.translation.height)
                    if !didDrag && moved > 10 { didDrag = true }
                    if didDrag { onDragChanged(v.translation) }   // keep following once grabbed
                }
                .onEnded { v in
                    let moved = abs(v.translation.width) + abs(v.translation.height)
                    let quick = (pressStart.map { Date().timeIntervalSince($0) } ?? 1) < 0.2
                    // A brief contact that drifted only a little is a PAT, not a drag — otherwise a
                    // trackpad flick swallows the pat (no purr/hearts, and a Chipkoo cling never releases).
                    if didDrag && !(quick && moved < 24) { onDragEnded() } else { onPat() }
                    didDrag = false; pressStart = nil
                }
        )
        .onHover { inside in
            hovering = inside
            if inside { state.peek(); playReaction() } else { stopReaction() }
        }
        .onAppear { breathe = true }
        .onChange(of: state.patPulse) { _ in firePat() }
        .onChange(of: state.perkPulse) { _ in firePerk() }
    }

    @ViewBuilder private var spriteFrame: some View {
        if let img = anim.frame ?? Sprites.image(characterId: state.character, mood: state.mood.rawValue) {
            Image(nsImage: img)
                .interpolation(.none)        // crisp pixels
                .resizable()
                .scaledToFit()
        } else {
            Text(state.mood.emoji).font(.system(size: 60))
        }
    }

    @ViewBuilder private var bubble: some View {
        if let text = state.bubble {
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Color(red: 0.42, green: 0.35, blue: 0.33))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(state.mood.accent.opacity(0.55), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                )
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state.bubble)
        } else {
            Color.clear
        }
    }

    private func firePat() {
        bounce = true
        hearts = (0..<4).map { i in
            Heart(dx: CGFloat(i) * 13 - 20 + CGFloat.random(in: -4...4),
                  scale: CGFloat.random(in: 0.8...1.3))
        }
        heartsGen &+= 1
        let gen = heartsGen   // only the LATEST pat's timer clears the hearts (rapid pats don't wipe new ones early)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { bounce = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) { if heartsGen == gen { hearts = [] } }
    }

    private func firePerk() {
        bounce = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { bounce = false }
    }

    // MARK: - per-mood hover reactions (transform-based, no new art)

    private func after(_ d: Double, _ b: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: b)
    }
    private func anim(_ resp: Double = 0.22, _ damp: Double = 0.45, _ b: @escaping () -> Void) {
        withAnimation(.spring(response: resp, dampingFraction: damp), b)
    }
    private func settle(_ delay: Double) {
        after(delay) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                reactRot = 0; reactY = 0; reactX = 0; reactScale = 1
            }
        }
    }

    private func playReaction() {
        switch state.mood {
        case .neutral:        // looks up + happy wiggle + hop
            anim { reactY = -10; reactRot = 8 }
            after(0.16) { anim { reactRot = -7 } }
            settle(0.38)
        case .coding:         // eager "tippy-tap" double-bob
            anim(0.13, 0.5) { reactY = -6 }
            after(0.15) { anim(0.13, 0.5) { reactY = 0 } }
            after(0.30) { anim(0.13, 0.5) { reactY = -6 } }
            settle(0.5)
        case .thinking:       // pondering tilt L↔R, then an "idea!" hop
            anim(0.5, 0.7) { reactRot = -11 }
            after(0.42) { anim(0.5, 0.7) { reactRot = 11 } }
            after(0.9) { anim(0.25, 0.4) { reactRot = 0; reactY = -9 } }
            settle(1.1)
        case .meeting:        // polite nod
            anim(0.18, 0.5) { reactY = -4 }
            after(0.2) { anim(0.18, 0.6) { reactY = 0 } }
            after(0.4) { anim(0.18, 0.5) { reactY = -4 } }
            settle(0.62)
        case .communicating:  // chatty shimmy
            anim(0.1, 0.5) { reactX = -5 }
            after(0.1) { anim(0.1, 0.5) { reactX = 5 } }
            after(0.2) { anim(0.1, 0.5) { reactX = -4 } }
            after(0.3) { anim(0.1, 0.5) { reactX = 4 } }
            settle(0.42)
        case .browsing:       // lazy sway
            anim(0.5, 0.7) { reactRot = -7 }
            after(0.5) { anim(0.5, 0.7) { reactRot = 7 } }
            settle(1.05)
        case .creating:       // playful full spin
            withAnimation(.easeInOut(duration: 0.6)) { reactRot = 360 }
            after(0.62) { reactRot = 0 }   // snap back (360 == 0 visually)
        case .vibing:         // head-bob to a beat while hovered
            withAnimation(.easeInOut(duration: 0.34).repeatForever(autoreverses: true)) { reactY = -6 }
        case .idle:           // sleepy stir: deeper breath + tiny wiggle, stays curled
            anim(0.7, 0.85) { reactScale = 1.06 }
            after(0.18) { anim(0.5, 0.7) { reactRot = -3 } }
            after(0.6) { anim(0.5, 0.7) { reactRot = 0 } }
            after(0.72) { anim(0.7, 0.85) { reactScale = 1.0 } }
        }
    }

    private func stopReaction() {
        // also stops the vibing repeatForever bob
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            reactRot = 0; reactY = 0; reactX = 0; reactScale = 1
        }
    }
}
