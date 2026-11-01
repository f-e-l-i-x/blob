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
    // iOS only, for the jelly look: squash is a damped spring, so after a hit it overshoots
    // into a stretch and wobbles back. It acts along squashAngle (the hit's normal; default is
    // straight up, as for landing on the floor). mvx/mvy is the smoothed velocity the blob is
    // stretched along, and jiggle shakes its outline.
    var squashV: CGFloat = 0
    var squashAngle: CGFloat = .pi / 2
    var mvx: CGFloat = 0, mvy: CGFloat = 0
    var jiggle: CGFloat = 0
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
    // iOS only, for the juicier merge effects: merged value, the new blob's radius, a unique id.
    let v: Int
    let blobR: CGFloat
    let id: Int
}

final class GameWorld {
    var blobs: [Blob] = []
    var particles: [Particle] = []
    var flashes: [Flash] = []
    var bumperGlow: [CGFloat] = [0, 0]  // iOS only: 1 right after a hard hit on that bumper, fades out
    private var flashCount = 0
    var score = 0
    var best = UserDefaults.standard.integer(forKey: GameWorld.bestKey)
    var dangerTime: CGFloat = 0
    var over = false
    // iOS only, for the game-over screen: the blob that overflowed, and whether the score beat the old best.
    private(set) var overflowBlob: Blob?
    private(set) var newBest = false
    static let bestKey = "blobmerge-best"
    static let mergeCooldown: CGFloat = 0.15
    // iOS only: the top row holds at most this many blobs, packed to the right, and only
    // refills when a blob is flung or two merge.
    static let conveyorMax = 5
    static let conveyorRight = K.Cup.r - 2
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
        blobs = []; conveyor = []; particles = []; flashes = []; bumperGlow = [0, 0]
        score = 0; spawnTimer = 0; conveyorSpeed = 28; dangerTime = 0; over = false
        nextValue = nil
        overflowBlob = nil; newBest = false
        grabbed = nil; aim = nil
        // start with a full row, already packed to the right
        var right = GameWorld.conveyorRight
        for _ in 0..<GameWorld.conveyorMax {
            let v = randomValue(), hw = GameWorld.halfWidth(K.radius(for: v))
            addToConveyor(v: v, x: right - hw)
            right -= 2 * hw
        }
    }

    private func addToConveyor(v: Int, x: CGFloat) {
        let b = Blob(v: v, x: x, y: K.conveyorY, born: clock)
        b.stretch = 1.6  // conveyor blobs look like stretched pills
        conveyor.append(b)
    }

    /// Half the room a pill takes in the top row; a little under its drawn width, so neighbours squish together.
    static func halfWidth(_ r: CGFloat) -> CGFloat { r * 1.5 }
    private var nextValue: Int?

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

    /// Lets go without flinging: a grabbed blob just stays on the conveyor (used when pausing).
    func cancelTouch() {
        finger.down = false
        grabbed = nil
        aim = nil
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
            hit(o, min(0.35, o.squash + abs(vn) / 1500), nx, ny)
        }
        return true
    }

    /// nil without contact; otherwise the speed the blob hit with (0 if it wasn't moving in).
    private func collideCircle(_ o: Blob, _ c: Circle, bounce: CGFloat) -> CGFloat? {
        let dx = o.x - c.x, dy = o.y - c.y, d = hypot(dx, dy), m = o.r + c.r
        if d >= m || d == 0 { return nil }
        let nx = dx / d, ny = dy / d
        o.x = c.x + nx * m; o.y = c.y + ny * m
        let vn = o.vx * nx + o.vy * ny
        if vn < 0 { o.vx -= (1 + bounce) * vn * nx; o.vy -= (1 + bounce) * vn * ny }
        return max(0, -vn)
    }

    /// iOS only: a hit squashes the blob along the hit's normal (nx, ny) and shakes its outline.
    private func hit(_ b: Blob, _ k: CGFloat, _ nx: CGFloat, _ ny: CGFloat) {
        if k > abs(b.squash) * 0.5 { b.squashAngle = atan2(ny, nx) }
        b.squash = min(0.38, max(b.squash, k))
        // only real impacts shake it; resting contacts every substep shouldn't
        if k > 0.06 { b.jiggle = min(0.09, max(b.jiggle, k * 0.25)) }
    }

    private func merge(_ a: Blob, _ b: Blob, onConveyor: Bool = false) {
        let v = a.v * 2
        let nb = Blob(v: v, x: (a.x + b.x) / 2, y: onConveyor ? K.conveyorY : (a.y + b.y) / 2, born: clock)
        nb.squash = 0.35; nb.pop = 1; nb.jiggle = 0.06
        nb.mergeCooldown = GameWorld.mergeCooldown
        if onConveyor {
            // stays in the top row until it is flung
            nb.stretch = 1.6
            conveyor.removeAll { $0 === a || $0 === b }
            conveyor.append(nb)
        } else {
            nb.vx = (a.vx + b.vx) / 2; nb.vy = (a.vy + b.vy) / 2 - 80
            blobs.removeAll { $0 === a || $0 === b }
            blobs.append(nb)
        }
        score += v
        flashCount += 1
        flashes.append(Flash(x: nb.x, y: nb.y, r: nb.r * 2.6, t: 0, text: "+\(v)", v: v, blobR: nb.r, id: flashCount))
        // iOS only: big merges (512 and up) burst twice as many, faster particles.
        let big = v >= 512
        for _ in 0..<(big ? 28 : 14) {
            let ang = CGFloat.random(in: 0..<1) * 6.28, sp = (60 + CGFloat.random(in: 0..<1) * 160) * (big ? 1.4 : 1)
            particles.append(Particle(x: nb.x, y: nb.y, vx: cos(ang) * sp, vy: sin(ang) * sp,
                                      life: 0.5 + CGFloat.random(in: 0..<1) * 0.3, v: v))
        }
        conveyorSpeed = min(70, 28 + CGFloat(score) / 60)
        onMerge?(v)
    }

    func step(_ dt: CGFloat) {
        stepConveyor(dt)

        // blobs
        let SUB = 4, h = dt / CGFloat(SUB)
        for _ in 0..<SUB {
            for b in blobs {
                b.vy += K.gravity * h
                b.vx *= 1 - 0.4 * h; b.vy *= 1 - 0.2 * h
                b.x += b.vx * h; b.y += b.vy * h
                b.rot += b.spin * h; b.spin *= 1 - 1.5 * h
                for sg in K.segs { collideSeg(b, sg, bounce: 0.25) }
                for (i, bp) in K.bumpers.enumerated() {
                    guard let speed = collideCircle(b, bp, bounce: 0.9) else { continue }
                    hit(b, speed > 20 ? 0.3 : 0.05, (b.x - bp.x) / (b.r + bp.r), (b.y - bp.y) / (b.r + bp.r))
                    if speed > 60 { bumperGlow[i] = 1 }
                }
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
                        hit(a, k, nx, ny); hit(b, k, nx, ny)
                    }
                }
            }
            if let (a, b) = merged { merge(a, b) }
            // iOS: the finger no longer pokes blobs in the cup; it only grabs from the top row.
        }
        if dt > 0 {
            finger.vx = (finger.x - finger.px) / dt; finger.vy = (finger.y - finger.py) / dt
            finger.px = finger.x; finger.py = finger.y
        }

        for b in blobs {
            b.stretch += (1 - b.stretch) * dt * 4
            // smoothed velocity for the motion stretch; moving blobs keep a little jiggle
            let k = min(1, dt * 12)
            b.mvx += (b.vx - b.mvx) * k; b.mvy += (b.vy - b.mvy) * k
            b.jiggle = max(b.jiggle, min(0.05, hypot(b.vx, b.vy) / 8000))
            relax(b, dt)
        }
        for b in conveyor { relax(b, dt) }
        for i in bumperGlow.indices { bumperGlow[i] = max(0, bumperGlow[i] - dt * 2.5) }
        for i in particles.indices {
            particles[i].x += particles[i].vx * dt; particles[i].y += particles[i].vy * dt
            particles[i].vy += 300 * dt; particles[i].life -= dt
        }
        particles.removeAll { $0.life <= 0 }
        for i in flashes.indices { flashes[i].t += dt }
        flashes.removeAll { $0.t >= 0.8 }

        // overflow check: a settled blob above the danger line for too long ends the game
        let culprit = blobs.first { $0.y - $0.r < K.dangerY && clock - $0.born > 1.5 && abs($0.vy) < 60 }
        let danger = culprit != nil
        if danger { overflowBlob = culprit }
        dangerTime = danger ? dangerTime + dt : max(0, dangerTime - dt * 2)
        if dangerTime > 2 { gameOver() }
    }

    /// Squash spring, jiggle, pop and merge cooldown, once per frame.
    private func relax(_ b: Blob, _ dt: CGFloat) {
        // a soft, lightly damped spring: overshoots into a stretch and wobbles back
        b.squashV += (-230 * b.squash - 7 * b.squashV) * dt
        b.squash = max(-0.3, min(0.4, b.squash + b.squashV * dt))
        b.jiggle *= exp(-3 * dt)
        if b.pop > 0 { b.pop = max(0, b.pop - dt * 3) }
        if b.mergeCooldown > 0 { b.mergeCooldown = max(0, b.mergeCooldown - dt) }
    }

    // iOS: the top row is a queue. Blobs drift right until they rest against the right end or
    // the blob in front, matching neighbours that touch merge in place, and a new blob comes in
    // from the left only when there is a free spot and room for it.
    private func stepConveyor(_ dt: CGFloat) {
        conveyor.sort { $0.x > $1.x }  // front (right) first
        var limit = GameWorld.conveyorRight
        var touching: [Bool] = []
        for (i, b) in conveyor.enumerated() {
            let hw = GameWorld.halfWidth(b.r), stop = limit - hw
            if b !== grabbed {
                b.stretch += (1.6 - b.stretch) * dt * 5
                if b.x < stop {
                    let moving = b.vx > 0
                    b.x = min(stop, b.x + conveyorSpeed * dt)
                    b.vx = conveyorSpeed
                    if b.x >= stop && moving {
                        // bumps into the queue: squish sideways, and the one in front wobbles too
                        b.vx = 0
                        hit(b, 0.2, 1, 0)
                        if i > 0 { hit(conveyor[i - 1], 0.08, 1, 0) }
                    }
                } else {
                    // a merge can leave a bigger blob overlapping; ease it back out of the way
                    b.x += (stop - b.x) * min(1, dt * 10)
                    b.vx = 0
                }
            }
            touching.append(b.x >= stop - 1)
            limit = b.x - hw
        }
        for i in conveyor.indices.dropFirst() {
            let a = conveyor[i - 1], b = conveyor[i]
            guard a.v == b.v, touching[i], a !== grabbed, b !== grabbed,
                  a.mergeCooldown <= 0, b.mergeCooldown <= 0 else { continue }
            merge(a, b, onConveyor: true)
            break
        }

        spawnTimer -= dt
        guard spawnTimer <= 0, conveyor.count < GameWorld.conveyorMax else { return }
        let v = nextValue ?? randomValue()
        nextValue = v
        let hw = GameWorld.halfWidth(K.radius(for: v))
        let leftEdge = conveyor.map { $0.x - GameWorld.halfWidth($0.r) }.min() ?? GameWorld.conveyorRight
        // only once it fits fully inside the jar
        if leftEdge - 2 * hw >= K.Cup.l {
            addToConveyor(v: v, x: -hw)
            conveyor.last?.vx = conveyorSpeed
            nextValue = nil
            spawnTimer = 0.6
        }
    }

    private func gameOver() {
        running = false; over = true
        newBest = score > best && score > 0
        if score > best {
            best = score
            UserDefaults.standard.set(best, forKey: GameWorld.bestKey)
        }
        onGameOver?()
    }
}
