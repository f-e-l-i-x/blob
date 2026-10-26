import SpriteKit
import SwiftUI

struct ContentView: View {
    @State private var model = GameModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpriteView(scene: model.scene)
                    .ignoresSafeArea()
                BottomBar(model: model)
                OverlayHost(model: model)
            }
            .onAppear { model.scene.safeInsets = UIEdgeInsets(geo.safeAreaInsets) }
            .onChange(of: geo.safeAreaInsets) { _, insets in model.scene.safeInsets = UIEdgeInsets(insets) }
        }
        .background(Color(K.bg).ignoresSafeArea())
        .statusBarHidden()
        // leaving the app mid-game pauses it
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.pause() }
        }
    }
}

private extension UIEdgeInsets {
    init(_ e: EdgeInsets) { self.init(top: e.top, left: e.leading, bottom: e.bottom, right: e.trailing) }
}

// Pause on the left (only while playing), haptics on/off on the right. Sits in the strip the
// scene leaves free at the bottom (K.Layout.barHeight).
private struct BottomBar: View {
    let model: GameModel

    var body: some View {
        VStack {
            Spacer()
            HStack {
                let playing = model.phase == .playing
                CircleButton(symbol: "pause.fill", title: "Pause") { model.pause() }
                    .opacity(playing ? 1 : 0)
                    .allowsHitTesting(playing)
                Spacer()
                CircleButton(symbol: model.hapticsOn ? "iphone.radiowaves.left.and.right" : "iphone.slash",
                             title: model.hapticsOn ? "Turn haptics off" : "Turn haptics on") { model.toggleHaptics() }
            }
            .padding(.horizontal, 20)
            .frame(height: K.Layout.barHeight)
        }
    }
}

private struct CircleButton: View {
    let symbol: String
    let title: String
    let onTap: () -> Void

    var body: some View {
        Button(title, systemImage: symbol, action: onTap)
            .labelStyle(.iconOnly)
            .buttonStyle(CircleButtonStyle())
    }
}

private struct CircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color(K.scoreInk))
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: SwiftUI.Circle())
            .overlay(SwiftUI.Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
    }
}

// Reads `phase` in its own body, so showing or hiding the overlay doesn't make SwiftUI
// re-evaluate ContentView and the SpriteView.
private struct OverlayHost: View {
    let model: GameModel

    var body: some View {
        if model.phase != .playing {
            OverlayView(model: model)
        }
    }
}

// Start, "Paused" and "Overflow!" screens, styled like #overlay in index.html.
private struct OverlayView: View {
    let model: GameModel

    private var title: String {
        switch model.phase {
        case .over: "Overflow!"
        case .paused: "Paused"
        default: "Blob Merge"
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.system(size: 44, weight: .bold))
                .kerning(-1)
                .foregroundStyle(Color(K.ink))
            Group {
                if model.phase == .over {
                    Text("Score **\(String(model.score))**  ·  Best **\(String(model.best))**")
                } else if model.phase == .paused {
                    Text("Score **\(String(model.score))**")
                } else {
                    Text("Grab a blob from the top, drag to aim, release to fling it into the cup.\nPoke blobs in the cup with your finger to nudge them together.\nMatching numbers merge. Don't let the cup overflow.")
                }
            }
            .foregroundStyle(Color(K.muted))
            .lineSpacing(4)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            if model.phase == .paused {
                Button("Resume") { model.resume() }
                    .buttonStyle(PillButtonStyle())
                Button("Restart") { model.play() }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(K.muted))
            } else {
                Button(model.phase == .over ? "Play again" : "Play") { model.play() }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(K.bg).opacity(0.85).ignoresSafeArea())
    }
}

private struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 34)
            .background(Capsule().fill(Color(K.button)))
            .overlay(Capsule().strokeBorder(Color(K.ink), lineWidth: 4))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
