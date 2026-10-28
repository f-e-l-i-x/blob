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
