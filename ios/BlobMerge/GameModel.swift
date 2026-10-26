import Observation
import SpriteKit

// Bridges the SpriteKit scene to the SwiftUI overlay (#overlay in index.html) and bottom bar.
@MainActor
@Observable
final class GameModel {
    enum Phase { case start, playing, paused, over }

    private(set) var phase: Phase = .start
    private(set) var score = 0
    private(set) var best = 0
    private(set) var hapticsOn = Haptics.enabled

    @ObservationIgnored let scene: GameScene

    init() {
        scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        best = scene.game.best
        scene.game.onFling = { Haptics.fling() }
        scene.game.onMerge = { Haptics.merge($0) }
        scene.game.onGameOver = { [weak self] in
            guard let self else { return }
            score = scene.game.score
            best = scene.game.best
            phase = .over
        }
    }

    func play() {
        Haptics.prepare()
        scene.start()
        phase = .playing
    }

    func pause() {
        guard phase == .playing else { return }
        scene.pause()
        score = scene.game.score
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        Haptics.prepare()
        scene.resume()
        phase = .playing
    }

    func toggleHaptics() {
        Haptics.enabled.toggle()
        hapticsOn = Haptics.enabled
    }
}
