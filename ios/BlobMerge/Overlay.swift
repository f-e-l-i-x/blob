import SwiftUI

// The start, "Paused" and "Overflow!" screens: a frosted card over the dimmed game, which
// springs in and out when the phase changes.

private enum Ink {
    static let title = Color(UIColor(hex: 0x1d2127))
    static let body = Color(UIColor(hex: 0x4a5059))
    static let soft = Color(UIColor(hex: 0x7a818b))
}

private func rounded(_ size: CGFloat, _ weight: Font.Weight) -> Font {
    .system(size: size, weight: weight, design: .rounded)
}

// Reads `phase` in its own body, so showing or hiding the overlay doesn't make SwiftUI
// re-evaluate ContentView and the SpriteView.
struct OverlayHost: View {
    let model: GameModel

    var body: some View {
        ZStack {
            if model.phase != .playing {
                // Light dim on the start screen so the demo blobs stay visible behind the card.
                Color(UIColor(hex: 0x1d2127))
                    .opacity(model.phase == .start ? 0.06 : 0.22)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)  // the bottom bar's buttons stay usable
                    .transition(.opacity)
                OverlayCard(model: model)
                    .transition(.asymmetric(insertion: .scale(scale: 0.88).combined(with: .opacity).combined(with: .offset(y: 24)),
                                            removal: .scale(scale: 0.96).combined(with: .opacity)))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: model.phase)
    }
}

private struct OverlayCard: View {
    let model: GameModel

    var body: some View {
        VStack(spacing: 18) {
            switch model.phase {
            case .over: overflow
            case .paused: paused
            default: start
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 28)
        .frame(maxWidth: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 30, y: 14)
        .padding(.horizontal, 24)
    }

    private func title(_ s: String) -> some View {
        Text(s)
            .font(rounded(40, .heavy))
            .kerning(-0.5)
            .foregroundStyle(Ink.title)
    }

    // MARK: Start

    @ViewBuilder private var start: some View {
        title("Blob Merge")
        VStack(alignment: .leading, spacing: 14) {
            HowTo(symbol: "hand.draw.fill", text: "Grab a blob from the top, drag to aim, and let go to fling it.")
            HowTo(symbol: "hand.point.up.left.fill", text: "Poke blobs in the jar to nudge them together.")
            HowTo(symbol: "arrow.triangle.merge", text: "Matching numbers merge. Don't let the jar overflow.")
        }
        Button("Play") { model.play() }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 4)
    }

    // MARK: Paused

    @ViewBuilder private var paused: some View {
        title("Paused")
        Text("Score \(Text(String(model.score)).fontWeight(.heavy))")
            .font(rounded(18, .medium))
            .foregroundStyle(Ink.body)
        VStack(spacing: 10) {
            Button("Resume") { model.resume() }
                .buttonStyle(PrimaryButtonStyle())
            Button("Restart") { model.play() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: Overflow

    @ViewBuilder private var overflow: some View {
        title("Overflow!")
        VStack(spacing: 2) {
            Text("SCORE")
                .font(rounded(12, .bold))
                .kerning(1.5)
                .foregroundStyle(Ink.soft)
            CountUp(target: model.score)
                .font(rounded(60, .black))
                .foregroundStyle(Ink.title)
            // a new best replaces the "Best" line, which would show the same number
            if model.newBest {
                NewBestBadge().padding(.top, 4)
            } else {
                Text("Best \(String(model.best))")
                    .font(rounded(15, .semibold))
                    .foregroundStyle(Ink.soft)
            }
        }
        Button("Play again") { model.play() }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 4)
    }
}

private struct HowTo: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(LinearGradient(colors: [Color(UIColor(hex: 0x5aa9ff)), Color(K.button)], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(text)
                .font(rounded(15, .medium))
                .foregroundStyle(Ink.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Counts from 0 up to `target` with an ease-out when it appears.
private struct CountUp: View {
    let target: Int
    @State private var shown = 0

    var body: some View {
        Text(String(shown))
            .monospacedDigit()
            .task(id: target) {
                shown = 0
                let steps = 45
                for i in 1...steps {
                    try? await Task.sleep(for: .milliseconds(18))
                    let t = Double(i) / Double(steps)
                    shown = Int((1 - pow(1 - t, 3)) * Double(target))
                }
                shown = target
            }
    }
}

/// "NEW BEST" ribbon that pops in after the score has counted up, with a burst of blob-coloured dots.
private struct NewBestBadge: View {
    @State private var shown = false

    var body: some View {
        ZStack {
            if shown { Burst() }
            Text("NEW BEST")
                .font(rounded(13, .heavy))
                .kerning(1.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(LinearGradient(colors: [Color(UIColor(hex: 0xffcf3a)), Color(UIColor(hex: 0xf09a00))], startPoint: .top, endPoint: .bottom),
                            in: Capsule())
                .shadow(color: Color(UIColor(hex: 0xf09a00)).opacity(0.45), radius: 8, y: 3)
                .rotationEffect(.degrees(-4))
                .scaleEffect(shown ? 1 : 0.2)
                .opacity(shown ? 1 : 0)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(850))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { shown = true }
            Haptics.newBest()
        }
    }
}

private struct Burst: View {
    @State private var out = false
    private let colors = K.colors.keys.sorted().map { Color(K.color(for: $0)) }

    var body: some View {
        ZStack {
            ForEach(0..<22, id: \.self) { i in
                let a = Double(i) / 22 * 2 * .pi
                let d = 60 + Double((i * 37) % 45)
                SwiftUI.Circle()
                    .fill(colors[i % colors.count])
                    .frame(width: 7, height: 7)
                    .offset(x: out ? cos(a) * d : 0, y: out ? sin(a) * d * 0.7 : 0)
                    .opacity(out ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { out = true } }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(rounded(20, .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: 220)
            .padding(.vertical, 15)
            .background(LinearGradient(colors: [Color(UIColor(hex: 0x4fb0ff)), Color(K.button)], startPoint: .top, endPoint: .bottom),
                        in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: Color(K.button).opacity(0.4), radius: configuration.isPressed ? 4 : 10, y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(rounded(17, .semibold))
            .foregroundStyle(Ink.body)
            .padding(.vertical, 8)
            .padding(.horizontal, 20)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
