import Observation
import SpriteKit

// Bridges the SpriteKit scene to the SwiftUI overlay (#overlay in index.html).
@MainActor
@Observable
final class GameModel {
    enum Phase { case start, playing, over }

    private(set) var phase: Phase = .start
    private(set) var score = 0
    private(set) var best = 0

    @ObservationIgnored let scene: GameScene

    init() {
        scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        best = scene.game.best
        scene.game.onFling = { Haptics.fling() }
        scene.game.onMerge = { _ in Haptics.merge() }
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
}
