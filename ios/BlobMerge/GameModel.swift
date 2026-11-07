import Observation
import SpriteKit

// Bridges the SpriteKit scene to the SwiftUI overlay (#overlay in index.html) and bottom bar.
@MainActor
@Observable
final class GameModel {
    enum Phase { case start, playing, paused, over, flashcards }

    /// Seconds of play between word breaks. In Debug builds, the launch argument
    /// `-flashcardInterval <seconds>` overrides it for testing.
    static let breakInterval: TimeInterval = 3 * 60
    static let cardsPerBreak = 3

    private(set) var phase: Phase = .start
    private(set) var score = 0
    private(set) var best = 0
    private(set) var newBest = false
    private(set) var hapticsOn = Haptics.enabled
    // The word break: three cards, each shown in Spanish until tapped, then in English.
    private(set) var cards: [Word] = []
    private(set) var cardIndex = 0
    private(set) var cardFlipped = false

    @ObservationIgnored let scene: GameScene

    init() {
        scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        best = scene.game.best
        scene.game.onFling = { Haptics.fling() }
        // no merge haptics for the demo blobs on the start screen
        scene.game.onMerge = { [weak self] v in if self?.phase == .playing { Haptics.merge(v) } }
        // called after the scene's short overflow sequence
        scene.onGameOver = { [weak self] in
            guard let self else { return }
            score = scene.game.score
            best = scene.game.best
            newBest = scene.game.newBest
            phase = .over
        }
        var interval = Self.breakInterval
        #if DEBUG
        let override = UserDefaults.standard.double(forKey: "flashcardInterval")
        if override > 0 { interval = override }
        #endif
        scene.breakInterval = interval
        scene.onBreakDue = { [weak self] in self?.startBreak() }
    }

    private func startBreak() {
        guard phase == .playing, !scene.game.over else { return }
        scene.pause()
        score = scene.game.score
        cards = Words.pick(Self.cardsPerBreak)
        cardIndex = 0
        cardFlipped = false
        guard !cards.isEmpty else { return scene.resume() }  // no word list: keep playing
        phase = .flashcards
    }

    /// Tap on the card: flip to the English side, then on to the next word; after the last
    /// one a fresh game starts.
    func tapCard() {
        guard phase == .flashcards else { return }
        Haptics.flip()
        if !cardFlipped {
            cardFlipped = true
        } else if cardIndex + 1 < cards.count {
            cardIndex += 1
            cardFlipped = false
        } else {
            play()
        }
    }

    func play() {
        Haptics.prepare()
        scene.start()
        phase = .playing
    }

    func pause() {
        guard phase == .playing, !scene.game.over else { return }
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
