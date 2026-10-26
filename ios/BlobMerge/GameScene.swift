import SpriteKit

final class GameScene: SKScene {
    // Everything in the cup is drawn in world coordinates (y down, like the canvas)
    // under this node, which is flipped and scaled to fit the screen.
    private let world = SKNode()
    private var scale: CGFloat = 1, offX: CGFloat = 0, offY: CGFloat = 0
    private var worldOrigin = CGPoint.zero
    private let background = SKSpriteNode()
    private var backgroundSize = CGSize.zero
    private var bumperNodes: [(stud: SKSpriteNode, glow: SKSpriteNode)] = []

    private let speedBarL = SKShapeNode()
    private let speedBarR = SKShapeNode()

    let game = GameWorld()
    private var lastTime: TimeInterval?
    private var blobNodes: [BlobNode] = []
    private var activeTouch: UITouch?

    private let fingerCircle = SKShapeNode(circleOfRadius: 9)
    private let fingerDot = SKShapeNode(circleOfRadius: 2.4)
    private let arrow = SKShapeNode()
    private let grabDot = SKShapeNode(circleOfRadius: 3)
    private let dangerLine = SKShapeNode()
    private let scoreLabel = SKLabelNode()
    private let bestLabel = SKLabelNode()
    private var shownScore = -1, shownBest = -1
    private var flashNodes: [FlashNodes] = []
    private var lastFlashId = 0
    private var shake: CGFloat = 0          // screen shake amplitude, world units
    private var slowMo: TimeInterval = 0    // seconds of slow motion left after a big merge
    private var particleNodes: [SKShapeNode] = []
    private let flashTexture = GameScene.makeFlashTexture()
    private var warmup: SKNode?

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = K.bg
        anchorPoint = .zero
        background.zPosition = -100
        addChild(background)
        addChild(world)
        buildCup()
        buildOverlays()
        buildScore()
        buildWarmup()
        game.reset()
    }

    func start() {
        warmup?.removeFromParent()
        warmup = nil
        game.reset()
        game.running = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layout()
    }

    // Portrait branch of resize() in index.html.
    private func layout() {
        let w = size.width, h = size.height
        scale = min((w - 32) / K.W, (h - 32 - 70) / K.H)
        offX = (w - K.W * scale) / 2
        offY = (h - K.H * scale + 60) / 2
        worldOrigin = CGPoint(x: offX, y: h - offY)
        world.position = worldOrigin
        world.xScale = scale
        world.yScale = -scale
        if size != backgroundSize {
            backgroundSize = size
            background.texture = Backdrop.background(size: size, light: CGPoint(x: w / 2, y: offY + K.H * scale * 0.45))
            background.size = size
            background.position = CGPoint(x: w / 2, y: h / 2)
        }
        scoreLabel.position = CGPoint(x: w / 2, y: h - (offY - 4))
        bestLabel.position = CGPoint(x: w / 2, y: h - (offY - 52))
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime.map { min(0.033, currentTime - $0) } ?? 0
        lastTime = currentTime
        game.clock = currentTime
        // Slow motion eases from 35% back to full speed over its duration.
        let timeScale = 1 - 0.65 * slowMo / Self.slowMoDuration
        slowMo = max(0, slowMo - dt)
        if game.running { game.step(CGFloat(dt * timeScale)) }
        shake *= CGFloat(exp(-dt * 10))
        render()
    }

    private static let slowMoDuration: TimeInterval = 0.35

    // MARK: - Input

    // Only the first finger down counts, like a single pointer on the web.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let t = touches.first else { return }
        activeTouch = t
        game.pointerDown(t.location(in: world))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        game.pointerMove(t.location(in: world))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        activeTouch = nil
        game.release()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    // MARK: - Drawing

    private func render() {
        var i = 0
        func blobNode() -> BlobNode {
            if i == blobNodes.count {
                let n = BlobNode()
                world.addChild(n)
                blobNodes.append(n)
            }
            defer { i += 1 }
            return blobNodes[i]
        }
        for b in game.blobs {
            blobNode().show(b, stretchX: b.stretch, selected: false, t: game.clock, z: Z.blobs)
        }
        for b in game.conveyor {
            blobNode().show(b, stretchX: b.stretch, selected: b === game.grabbed, t: game.clock, z: Z.conveyor)
        }
        for n in blobNodes[i...] { n.isHidden = true }

        // New merges kick off a screen shake that grows with the value, and big ones slow time.
        for f in game.flashes where f.id > lastFlashId {
            lastFlashId = f.id
            shake = max(shake, max(0, log2(CGFloat(f.v)) - 1) * 0.7)
            if f.v >= 512 { slowMo = Self.slowMoDuration }
        }
        world.position = CGPoint(x: worldOrigin.x + .random(in: -1...1) * shake * scale,
                                 y: worldOrigin.y + .random(in: -1...1) * shake * scale)

        // merge flashes: soft white glow, a ring wave in the new colour, and a bouncy "+N"
        while flashNodes.count < game.flashes.count {
            let n = FlashNodes(texture: flashTexture)
            n.glow.zPosition = Z.flash
            n.ring.zPosition = Z.flash
            n.text.zPosition = Z.flashText
            for c in [n.glow, n.ring, n.text] as [SKNode] { world.addChild(c) }
            flashNodes.append(n)
        }
        for (j, n) in flashNodes.enumerated() {
            guard j < game.flashes.count else { n.hide(); continue }
            n.show(game.flashes[j])
        }

        // particles
        while particleNodes.count < game.particles.count {
            let n = SKShapeNode(circleOfRadius: 3)
            n.strokeColor = .clear
            n.lineWidth = 0
            n.zPosition = Z.particles
            world.addChild(n)
            particleNodes.append(n)
        }
        for (j, n) in particleNodes.enumerated() {
            guard j < game.particles.count else { n.isHidden = true; continue }
            let p = game.particles[j]
            n.isHidden = false
            n.position = CGPoint(x: p.x, y: p.y)
            n.fillColor = K.color(for: p.v)
            n.alpha = max(0, min(1, p.life * 2))
        }

        // touch indicator
        let f = game.finger
        fingerCircle.isHidden = !f.down
        fingerDot.isHidden = !f.down
        fingerCircle.position = CGPoint(x: f.x, y: f.y)
        fingerDot.position = fingerCircle.position

        // aim arrow
        if let g = game.grabbed, let aim = game.aim {
            grabDot.isHidden = false
            grabDot.position = CGPoint(x: g.x, y: g.y)
            let dx = aim.x - g.x, dy = aim.y - g.y, len = min(hypot(dx, dy), 200)
            if len > 8 {
                let a = atan2(dy, dx), ex = g.x + cos(a) * len, ey = g.y + sin(a) * len
                let p = CGMutablePath()
                p.move(to: CGPoint(x: g.x, y: g.y)); p.addLine(to: CGPoint(x: ex, y: ey))
                p.move(to: CGPoint(x: ex, y: ey)); p.addLine(to: CGPoint(x: ex - cos(a - 0.45) * 14, y: ey - sin(a - 0.45) * 14))
                p.move(to: CGPoint(x: ex, y: ey)); p.addLine(to: CGPoint(x: ex - cos(a + 0.45) * 14, y: ey - sin(a + 0.45) * 14))
                arrow.path = p
                arrow.isHidden = false
            } else {
                arrow.isHidden = true
            }
        } else {
            grabDot.isHidden = true
            arrow.isHidden = true
        }

        updateSpeedBars(conveyorSpeed: game.conveyorSpeed)

        for (i, n) in bumperNodes.enumerated() {
            let g = game.bumperGlow[i]
            let s = 1 + 0.12 * g
            n.stud.xScale = s
            n.stud.yScale = -s
            n.stud.colorBlendFactor = 0.45 * g  // tint toward white
            n.glow.alpha = 0.9 * g
        }

        // danger line pulses when you're about to overflow
        dangerLine.isHidden = game.dangerTime <= 0
        if !dangerLine.isHidden {
            let a = 0.3 + 0.5 * abs(sin(game.clock * 1000 / 120))
            dangerLine.strokeColor = UIColor(red: 216 / 255, green: 31 / 255, blue: 38 / 255, alpha: a)
        }

        if game.score != shownScore || game.best != shownBest {
            if game.score > shownScore && shownScore > 0 {
                // punch the big score when it goes up
                scoreLabel.removeAction(forKey: "punch")
                scoreLabel.setScale(1.25)
                let back = SKAction.scale(to: 1, duration: 0.25)
                back.timingMode = .easeOut
                scoreLabel.run(back, withKey: "punch")
            }
            shownScore = game.score; shownBest = game.best
            scoreLabel.attributedText = scoreText(String(game.score), size: 48, weight: .black)
            bestLabel.attributedText = scoreText("best \(game.best)", size: 13, weight: .semibold)
        }
    }

    private func scoreText(_ s: String, size: CGFloat, weight: UIFont.Weight) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: K.scoreInk,
        ])
    }

    // Draws a hidden copy of everything that first shows up during play (every
    // value's blob and number, touch circle, aim arrow, danger line, flash, "+N", particle)
    // behind the start screen. The GPU then sets them up before Play instead of stuttering
    // the first time each appears in the game.
    private func buildWarmup() {
        let warm = SKNode()
        warm.zPosition = Z.cup - 1  // under the white cup interior, so nothing shows
        for (i, v) in K.colors.keys.sorted().enumerated() {
            let n = BlobNode()
            let b = Blob(v: v, x: 70 + CGFloat(i % 4) * 85, y: 180 + CGFloat(i / 4) * 80, born: 0)
            n.show(b, stretchX: 1, selected: i == 0, t: 0, z: 0)
            warm.addChild(n)
        }
        let line = CGMutablePath()
        line.move(to: CGPoint(x: 100, y: 300))
        line.addLine(to: CGPoint(x: 200, y: 330))
        let arrowCopy = arrow.copy() as! SKShapeNode
        arrowCopy.path = line
        let glow = SKSpriteNode(texture: flashTexture, size: CGSize(width: 60, height: 60))
        let plus = SKLabelNode()
        plus.attributedText = NSAttributedString(string: "+2", attributes: [
            .font: UIFont.systemFont(ofSize: 16, weight: .heavy), .foregroundColor: UIColor.darkGray,
        ])
        plus.yScale = -1
        let particle = SKShapeNode(circleOfRadius: 3)
        particle.fillColor = K.color(for: 1)
        particle.strokeColor = .clear
        let dots = [fingerCircle.copy(), fingerDot.copy(), grabDot.copy()].compactMap { $0 as? SKNode } + [glow, plus, particle]
        for n in dots { n.position = CGPoint(x: 200, y: 250) }
        // The arrow and danger-line paths already lie inside the cup, so they stay where they are.
        for n in dots + [arrowCopy, dangerLine.copy() as! SKShapeNode] {
            n.isHidden = false
            n.zPosition = 0  // copies keep their own z; keep them all under the cup
            warm.addChild(n)
        }
        world.addChild(warm)
        warm.run(.sequence([.wait(forDuration: 1), .removeFromParent()]))
        warmup = warm
    }

    private func buildScore() {
        for l in [scoreLabel, bestLabel] {
            l.horizontalAlignmentMode = .center
            l.verticalAlignmentMode = .bottom
            addChild(l)
        }
    }

    private func buildOverlays() {
        fingerCircle.fillColor = UIColor(red: 150 / 255, green: 150 / 255, blue: 150 / 255, alpha: 0.75)
        fingerCircle.strokeColor = .clear
        fingerCircle.lineWidth = 0
        fingerCircle.zPosition = Z.finger
        fingerDot.fillColor = UIColor(hex: 0x222222)
        fingerDot.strokeColor = .clear
        fingerDot.lineWidth = 0
        fingerDot.zPosition = Z.finger + 0.1
        arrow.strokeColor = K.ink
        arrow.lineWidth = 2.5
        arrow.lineCap = .round
        arrow.zPosition = Z.arrow
        grabDot.fillColor = K.ink
        grabDot.strokeColor = .clear
        grabDot.lineWidth = 0
        grabDot.zPosition = Z.arrow
        let line = CGMutablePath()
        line.move(to: CGPoint(x: K.Cup.l, y: K.dangerY))
        line.addLine(to: CGPoint(x: K.Cup.r, y: K.dangerY))
        dangerLine.path = line.copy(dashingWithPhase: 0, lengths: [8, 8])
        dangerLine.lineWidth = 2
        dangerLine.zPosition = Z.danger
        for n in [fingerCircle, fingerDot, arrow, grabDot, dangerLine] {
            n.isHidden = true
            world.addChild(n)
        }
    }

    // MARK: - Static cup

    private enum Z {
        static let cup: CGFloat = 0, danger: CGFloat = 1, flash: CGFloat = 2, blobs: CGFloat = 3
        static let conveyor: CGFloat = 4, flashText: CGFloat = 5, particles: CGFloat = 6
        static let finger: CGFloat = 7, arrow: CGFloat = 8, bumpers: CGFloat = 9
        static let outline: CGFloat = 10, rail: CGFloat = 11
    }

    private func buildCup() {
        let C = K.Cup.self

        let center = CGPoint(x: K.W / 2, y: K.H / 2)
        let pad = Backdrop.shadowPad
        let shadow = SKSpriteNode(texture: Backdrop.cupShadow(), size: CGSize(width: K.W + pad * 2, height: K.H + pad * 2))
        let cup = SKSpriteNode(texture: Backdrop.cupInterior(), size: CGSize(width: K.W, height: K.H))
        for (n, z) in [(shadow, Z.cup - 2), (cup, Z.cup)] {
            n.position = center
            n.yScale = -1  // undo the world flip
            n.zPosition = z
            world.addChild(n)
        }

        // shiny studs that light up and pulse when a blob hits them
        for bp in K.bumpers {
            let stud = SKSpriteNode(texture: Backdrop.bumper(r: bp.r), size: CGSize(width: bp.r * 2 + 2, height: bp.r * 2 + 2))
            stud.yScale = -1
            stud.color = .white
            let glow = SKSpriteNode(texture: flashTexture, size: CGSize(width: bp.r * 4.5, height: bp.r * 4.5))
            glow.color = UIColor(hex: 0x7fc0ff)
            glow.colorBlendFactor = 1
            glow.alpha = 0
            for n in [stud, glow] { n.position = CGPoint(x: bp.x, y: bp.y) }
            stud.zPosition = Z.bumpers
            glow.zPosition = Z.bumpers - 0.1
            world.addChild(glow)
            world.addChild(stud)
            bumperNodes.append((stud, glow))
        }

        let outlinePath = CGMutablePath()
        outlinePath.move(to: CGPoint(x: K.segs[0].x1, y: K.segs[0].y1))
        for s in K.segs.prefix(5) { outlinePath.addLine(to: CGPoint(x: s.x2, y: s.y2)) }
        let outline = stroke(outlinePath, color: K.ink, width: 9)
        outline.lineJoin = .round
        outline.zPosition = Z.outline
        world.addChild(outline)

        let railPath = CGMutablePath()
        railPath.move(to: CGPoint(x: C.l, y: C.t))
        railPath.addLine(to: CGPoint(x: C.r, y: C.t))
        let rail = stroke(railPath, color: K.ink, width: 5)
        rail.zPosition = Z.rail
        world.addChild(rail)

        for bar in [speedBarL, speedBarR] {
            bar.strokeColor = K.button
            bar.lineWidth = 4
            bar.zPosition = Z.rail + 0.1
            world.addChild(bar)
        }
        updateSpeedBars(conveyorSpeed: 28)
    }

    private func updateSpeedBars(conveyorSpeed: CGFloat) {
        let C = K.Cup.self
        let k = (conveyorSpeed - 28) / 42
        let l = CGMutablePath()
        l.move(to: CGPoint(x: C.l + 6, y: C.t + 4))
        l.addLine(to: CGPoint(x: C.l + 6 + 60 + 100 * k, y: C.t + 4))
        speedBarL.path = l
        let r = CGMutablePath()
        r.move(to: CGPoint(x: C.r - 6, y: C.t + 4))
        r.addLine(to: CGPoint(x: C.r - 6 - 60 - 100 * k, y: C.t + 4))
        speedBarR.path = r
    }

    // MARK: - Helpers

    // White radial gradient, opaque in the centre and transparent at the rim.
    private static func makeFlashTexture() -> SKTexture {
        let d: CGFloat = 128
        let image = UIGraphicsImageRenderer(size: CGSize(width: d, height: d)).image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            let c = CGPoint(x: d / 2, y: d / 2)
            ctx.cgContext.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: d / 2, options: [])
        }
        return SKTexture(image: image)
    }

    private func stroke(_ path: CGPath, color: UIColor, width: CGFloat) -> SKShapeNode {
        let n = SKShapeNode(path: path)
        n.fillColor = .clear
        n.strokeColor = color
        n.lineWidth = width
        return n
    }
}

// The nodes for one merge flash. Reused from a pool; the "+N" text is only rebuilt when the
// pooled node switches to a different flash.
private final class FlashNodes {
    let glow: SKSpriteNode
    let ring = SKShapeNode()
    let text = SKLabelNode()
    private var shownId = 0

    init(texture: SKTexture) {
        glow = SKSpriteNode(texture: texture)
        ring.fillColor = .clear
        text.horizontalAlignmentMode = .center
        text.verticalAlignmentMode = .baseline
    }

    func hide() {
        glow.isHidden = true; ring.isHidden = true; text.isHidden = true
    }

    func show(_ f: Flash) {
        let k = f.t / 0.8  // 0...1 over the flash's life
        glow.isHidden = false
        glow.position = CGPoint(x: f.x, y: f.y)
        glow.size = CGSize(width: f.r * 2, height: f.r * 2)
        glow.alpha = 0.95 * (1 - k)

        // ring: races out from the blob's edge during the first 60% of the flash
        let rk = min(1, k / 0.6)
        ring.isHidden = rk >= 1
        if !ring.isHidden {
            let ease = 1 - (1 - rk) * (1 - rk) * (1 - rk)
            let r = f.blobR + (f.r * 1.1 - f.blobR) * ease
            ring.path = CGPath(ellipseIn: CGRect(x: f.x - r, y: f.y - r, width: r * 2, height: r * 2), transform: nil)
            ring.lineWidth = 1 + 5 * (1 - rk)
            ring.alpha = 0.9 * (1 - rk)
        }

        if shownId != f.id {
            shownId = f.id
            ring.strokeColor = K.color(for: f.v)
            let size = 18 + log2(CGFloat(f.v)) * 1.5
            var font = UIFont.systemFont(ofSize: size, weight: .black)
            if let rounded = font.fontDescriptor.withDesign(.rounded) { font = UIFont(descriptor: rounded, size: size) }
            text.attributedText = NSAttributedString(string: f.text, attributes: [
                .font: font,
                .foregroundColor: K.color(for: f.v).mixed(with: .black, by: 0.15),
                .strokeColor: UIColor.white,
                .strokeWidth: -4,  // negative: fill and outline
            ])
        }
        // pops in with an overshoot, settles, then floats up and fades
        let s = k < 0.12 ? 0.4 + k / 0.12 * 0.9 : max(1, 1.3 - (k - 0.12) / 0.15 * 0.3)
        text.isHidden = false
        text.xScale = s
        text.yScale = -s  // negative undoes the world flip
        text.position = CGPoint(x: f.x, y: f.y - 22 - k * 36)
        text.alpha = 1 - k * k
    }
}
