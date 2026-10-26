import CoreGraphics
import Foundation

// Game state and the hand-written physics from index.html, in world coordinates (y down).
// Nothing in here knows about SpriteKit; GameScene draws it.

final class Blob {
    let v: Int
    var x: CGFloat, y: CGFloat
    var vx: CGFloat = 0, vy: CGFloat = 0
    let r: CGFloat
    let seed: [CGFloat]
    var rot: CGFloat
    var spin: CGFloat = 0
    var squash: CGFloat = 0
    var stretch: CGFloat = 1
    var pop: CGFloat = 0
    var mergeCooldown: CGFloat = 0  // iOS only: seconds until a freshly merged blob may merge again
    let born: TimeInterval
    let id: CGFloat

    init(v: Int, x: CGFloat, y: CGFloat, born: TimeInterval) {
        self.v = v
        self.x = x
        self.y = y
        r = K.radius(for: v)
        seed = (0..<9).map { _ in 0.85 + CGFloat.random(in: 0..<1) * 0.3 }
        rot = CGFloat.random(in: 0..<1) * 6.28
        self.born = born
        id = CGFloat.random(in: 0..<1)
    }
}

// The finger is the grey touch circle: it grabs conveyor blobs and pokes blobs in the cup.
struct Finger {
    var x: CGFloat = 0, y: CGFloat = 0, px: CGFloat = 0, py: CGFloat = 0
    var vx: CGFloat = 0, vy: CGFloat = 0
    let r: CGFloat = 9
    var down = false
}

struct Particle {
    var x, y, vx, vy, life: CGFloat
    let v: Int
}

struct Flash {
    let x, y, r: CGFloat
    var t: CGFloat
    let text: String
}

final class GameWorld {
    var blobs: [Blob] = []
    var particles: [Particle] = []
    var flashes: [Flash] = []
    var score = 0
    var best = UserDefaults.standard.integer(forKey: GameWorld.bestKey)
    var dangerTime: CGFloat = 0
    var over = false
    static let bestKey = "blobmerge-best"
    static let mergeCooldown: CGFloat = 0.15
    var conveyor: [Blob] = []
    var finger = Finger()
    var grabbed: Blob?
    var aim: CGPoint?
    var spawnTimer: CGFloat = 0
    var conveyorSpeed: CGFloat = 28
    var clock: TimeInterval = 0
    var running = false

    var onFling: (() -> Void)?
    var onMerge: ((Int) -> Void)?
    var onGameOver: (() -> Void)?

    private func randomValue() -> Int {
        let maxOnBoard = blobs.reduce(1) { max($0, $1.v) }
        let top = max(2, min(5, log2(CGFloat(maxOnBoard))))  // up to 16
        let p = CGFloat.random(in: 0..<1)
        let e = Int(floor(pow(p, 1.8) * top))
        return 1 << e
    }

    func reset() {
        blobs = []; conveyor = []; particles = []; flashes = []
        score = 0; spawnTimer = 0; conveyorSpeed = 28; dangerTime = 0; over = false
        grabbed = nil; aim = nil
        for i in 0..<4 { addToConveyor(x: 40 + CGFloat(i) * 95) }
    }

    private func addToConveyor(x: CGFloat) {
        let b = Blob(v: randomValue(), x: x, y: K.conveyorY, born: clock)
        b.stretch = 1.6  // conveyor blobs look like stretched pills
        conveyor.append(b)
    }

    // MARK: - Input

    func pointerDown(_ p: CGPoint) {
        guard running else { return }
        finger.x = p.x; finger.y = p.y; finger.px = p.x; finger.py = p.y
        finger.vx = 0; finger.vy = 0; finger.down = true
        var pick: Blob?, bestD: CGFloat = 1e9
        for b in conveyor {
            let d = hypot(b.x - p.x, b.y - p.y)
            if d < b.r * 1.9 + 14 && d < bestD { bestD = d; pick = b }
        }
        if let pick { grabbed = pick; aim = p }
    }

    func pointerMove(_ p: CGPoint) {
        guard finger.down else { return }
        finger.x = p.x; finger.y = p.y
        if grabbed != nil { aim = p }
    }

    func release() {
        finger.down = false
        guard let b = grabbed, let aim else { return }
        let dx = aim.x - b.x, dy = aim.y - b.y
        let len = hypot(dx, dy)
        conveyor.removeAll { $0 === b }
        b.stretch = 1.6
        if len > 8 {
            let power = min(len, 200) * 4.2
            b.vx = dx / len * power; b.vy = dy / len * power
        } else { b.vx = 0; b.vy = 60 }
        b.spin = (CGFloat.random(in: 0..<1) - 0.5) * 6
        blobs.append(b)
        grabbed = nil; self.aim = nil
        onFling?()
    }

    // MARK: - Physics

    @discardableResult
    private func collideSeg(_ o: Blob, _ s: Segment, bounce: CGFloat) -> Bool {
        let ex = s.x2 - s.x1, ey = s.y2 - s.y1, L2 = ex * ex + ey * ey
        var t = ((o.x - s.x1) * ex + (o.y - s.y1) * ey) / L2
        t = max(0, min(1, t))
        let px = s.x1 + ex * t, py = s.y1 + ey * t
        let dx = o.x - px, dy = o.y - py, d = hypot(dx, dy)
        if d >= o.r || d == 0 { return false }
        let nx = dx / d, ny = dy / d
        o.x += nx * (o.r - d); o.y += ny * (o.r - d)
        let vn = o.vx * nx + o.vy * ny
        if vn < 0 {
            o.vx -= (1 + bounce) * vn * nx; o.vy -= (1 + bounce) * vn * ny
            let tx = -ny, ty = nx, vt = o.vx * tx + o.vy * ty
            o.vx -= vt * tx * 0.08; o.vy -= vt * ty * 0.08
            o.squash = min(0.35, o.squash + abs(vn) / 1500)
        }
        return true
    }

    private func collideCircle(_ o: Blob, _ c: Circle, bounce: CGFloat) -> Bool {
        let dx = o.x - c.x, dy = o.y - c.y, d = hypot(dx, dy), m = o.r + c.r
        if d >= m || d == 0 { return false }
        let nx = dx / d, ny = dy / d
        o.x = c.x + nx * m; o.y = c.y + ny * m
        let vn = o.vx * nx + o.vy * ny
        if vn < 0 { o.vx -= (1 + bounce) * vn * nx; o.vy -= (1 + bounce) * vn * ny }
        return true
    }

    private func merge(_ a: Blob, _ b: Blob) {
        let v = a.v * 2
        let nb = Blob(v: v, x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, born: clock)
        nb.vx = (a.vx + b.vx) / 2; nb.vy = (a.vy + b.vy) / 2 - 80
        nb.squash = 0.35; nb.pop = 1
        nb.mergeCooldown = GameWorld.mergeCooldown
        blobs.removeAll { $0 === a || $0 === b }
        blobs.append(nb)
        score += v
        flashes.append(Flash(x: nb.x, y: nb.y, r: nb.r * 2.6, t: 0, text: "+\(v)"))
        for _ in 0..<14 {
            let ang = CGFloat.random(in: 0..<1) * 6.28, sp = 60 + CGFloat.random(in: 0..<1) * 160
            particles.append(Particle(x: nb.x, y: nb.y, vx: cos(ang) * sp, vy: sin(ang) * sp,
                                      life: 0.5 + CGFloat.random(in: 0..<1) * 0.3, v: v))
        }
        conveyorSpeed = min(70, 28 + CGFloat(score) / 60)
        onMerge?(v)
    }

    func step(_ dt: CGFloat) {
        // conveyor: blobs drift right and leave on the right
        for b in conveyor where b !== grabbed {
            b.x += conveyorSpeed * dt
            b.stretch += (1.6 - b.stretch) * dt * 5
        }
        conveyor.removeAll { $0 !== grabbed && $0.x >= K.W + 40 }
        // keep a steady supply
        spawnTimer -= dt
        let minX = conveyor.reduce(CGFloat(1e9)) { min($0, $1.x) }
        if conveyor.count < 5 && (minX > 70 || conveyor.isEmpty) && spawnTimer <= 0 {
            addToConveyor(x: -30); spawnTimer = 0.6
        }

        // blobs
        let SUB = 4, h = dt / CGFloat(SUB)
        for _ in 0..<SUB {
            for b in blobs {
                b.vy += K.gravity * h
                b.vx *= 1 - 0.4 * h; b.vy *= 1 - 0.2 * h
                b.x += b.vx * h; b.y += b.vy * h
                b.rot += b.spin * h; b.spin *= 1 - 1.5 * h
                for sg in K.segs { collideSeg(b, sg, bounce: 0.25) }
                for bp in K.bumpers where collideCircle(b, bp, bounce: 0.9) { b.squash = 0.3 }
            }
            // blob-blob (at most one merge per substep)
            var merged: (Blob, Blob)?
            pairs: for i in 0..<blobs.count {
                for j in (i + 1)..<blobs.count {
                    let a = blobs[i], b = blobs[j]
                    let dx = b.x - a.x, dy = b.y - a.y, m = a.r + b.r
                    var d = hypot(dx, dy)
                    if d == 0 { d = 0.001 }
                    if d >= m { continue }
                    if a.v == b.v {
                        // A blob fresh from a merge waits a moment, so chain merges play out step by step.
                        // Until then the pair neither merges nor pushes apart.
                        if a.mergeCooldown > 0 || b.mergeCooldown > 0 { continue }
                        merged = (a, b); break pairs
                    }
                    let nx = dx / d, ny = dy / d, over = m - d
                    let ma = a.r * a.r, mb = b.r * b.r, tot = ma + mb
                    a.x -= nx * over * mb / tot; a.y -= ny * over * mb / tot
                    b.x += nx * over * ma / tot; b.y += ny * over * ma / tot
                    let rv = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny
                    if rv < 0 {
                        let jimp = -(1 + 0.15) * rv / (1 / ma + 1 / mb)
                        a.vx -= jimp * nx / ma; a.vy -= jimp * ny / ma
                        b.vx += jimp * nx / mb; b.vy += jimp * ny / mb
                        let k = min(0.3, -rv / 1800)
                        a.squash = max(a.squash, k); b.squash = max(b.squash, k)
                    }
                }
            }
            if let (a, b) = merged { merge(a, b) }

            // finger pokes blobs in the cup (unless it is busy aiming a conveyor blob)
            if finger.down && grabbed == nil {
                for b in blobs {
                    let dx = b.x - finger.x, dy = b.y - finger.y, m = b.r + finger.r
                    var d = hypot(dx, dy)
                    if d == 0 { d = 0.001 }
                    if d >= m { continue }
                    let nx = dx / d, ny = dy / d
                    b.x = finger.x + nx * m; b.y = finger.y + ny * m
                    let vn = (b.vx - finger.vx) * nx + (b.vy - finger.vy) * ny
                    if vn < 0 { b.vx -= 1.3 * vn * nx; b.vy -= 1.3 * vn * ny; b.squash = max(b.squash, 0.25) }
                }
            }
        }
        if dt > 0 {
            finger.vx = (finger.x - finger.px) / dt; finger.vy = (finger.y - finger.py) / dt
            finger.px = finger.x; finger.py = finger.y
        }

        for b in blobs {
            b.squash *= 1 - 6 * dt
            b.stretch += (1 - b.stretch) * dt * 4
            if b.pop > 0 { b.pop = max(0, b.pop - dt * 3) }
            if b.mergeCooldown > 0 { b.mergeCooldown = max(0, b.mergeCooldown - dt) }
        }
        for i in particles.indices {
            particles[i].x += particles[i].vx * dt; particles[i].y += particles[i].vy * dt
            particles[i].vy += 300 * dt; particles[i].life -= dt
        }
        particles.removeAll { $0.life <= 0 }
        for i in flashes.indices { flashes[i].t += dt }
        flashes.removeAll { $0.t >= 0.8 }

        // overflow check: a settled blob above the danger line for too long ends the game
        let danger = blobs.contains { $0.y - $0.r < K.dangerY && clock - $0.born > 1.5 && abs($0.vy) < 60 }
        dangerTime = danger ? dangerTime + dt : max(0, dangerTime - dt * 2)
        if dangerTime > 2 { gameOver() }
    }

    private func gameOver() {
        running = false; over = true
        if score > best {
            best = score
            UserDefaults.standard.set(best, forKey: GameWorld.bestKey)
        }
        onGameOver?()    }
}
