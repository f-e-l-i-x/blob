import SpriteKit
import SwiftUI

struct ContentView: View {
    @State private var model = GameModel()

    var body: some View {
        ZStack {
            SpriteView(scene: model.scene)
                .ignoresSafeArea()
            OverlayHost(model: model)
        }
        .background(Color(K.bg))
        .statusBarHidden()
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

// Start screen and "Overflow!" screen, styled like #overlay in index.html.
private struct OverlayView: View {
    let model: GameModel

    var body: some View {
        VStack(spacing: 14) {
            Text(model.phase == .over ? "Overflow!" : "Blob Merge")
                .font(.system(size: 44, weight: .bold))
                .kerning(-1)
                .foregroundStyle(Color(K.ink))
            Group {
                if model.phase == .over {
                    Text("Score **\(String(model.score))**  ·  Best **\(String(model.best))**")
                } else {
                    Text("Grab a blob from the top, drag to aim, release to fling it into the cup.\nPoke blobs in the cup with your finger to nudge them together.\nMatching numbers merge. Don't let the cup overflow.")
                }
            }
            .foregroundStyle(Color(K.muted))
            .lineSpacing(4)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            Button(model.phase == .over ? "Play again" : "Play") { model.play() }
                .buttonStyle(PillButtonStyle())
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
