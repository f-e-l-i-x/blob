import SpriteKit

// One blob on screen: the wobbly soft shape (blobPath/drawBlob in index.html) plus its number.
// Lives under GameScene's flipped world node, so coordinates are world units with y down.
//
// iOS-only shading, all built from the same outline: this node fills it in a darker shade
// (bottom shadow crescent) with a thin rim, `body` is the main colour shifted up and shrunk
// a little, and `highlight` is a small glossy copy near the top left.
//
// The number is embossed (light edge up-left, dark edge down-right), lives in `face` so it
// squashes and stretches with the blob, and sits under the highlight as if inside the jelly.
final class BlobNode: SKShapeNode {
    private let body = SKShapeNode()
    private let highlight = SKShapeNode()
    private let face = SKNode()
    private let label = SKLabelNode()
    private let labelShadow = SKLabelNode()
    private let labelLight = SKLabelNode()
    private var shownValue = 0
    private var rimColor = UIColor.clear

    override init() {
        super.init()
        for n in [body, highlight] {
            n.strokeColor = .clear
            n.lineWidth = 0
        }
        body.zPosition = 0.1
        face.zPosition = 0.2
        highlight.zPosition = 0.6
        highlight.fillColor = UIColor(white: 1, alpha: 0.3)
        addChild(body)
        addChild(face)
        addChild(highlight)
        // `face` undoes the world flip (negative yScale), so its children use y-up coordinates.
        for (l, z) in [(labelShadow, 0.1), (labelLight, 0.2), (label, 0.3)] {
            l.verticalAlignmentMode = .center
            l.horizontalAlignmentMode = .center
            l.zPosition = z
            face.addChild(l)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ b: Blob, stretchX: CGFloat, selected: Bool, t: TimeInterval, z: CGFloat) {
        isHidden = false
        zPosition = z
        position = CGPoint(x: b.x, y: b.y)
        if shownValue != b.v { applyValue(b) }

        let outline = Self.path(for: b, stretchX: stretchX, t: t)
        let box = outline.boundingBox
        path = outline
        var bodyT = CGAffineTransform(translationX: 0, y: -box.height * 0.04).scaledBy(x: 0.92, y: 0.92)
        body.path = outline.copy(using: &bodyT)
        var glossT = CGAffineTransform(translationX: box.midX - box.width * 0.17, y: box.midY - box.height * 0.2)
            .scaledBy(x: 0.38, y: 0.3)
        highlight.path = outline.copy(using: &glossT)

        // Full squash, but only half the pill stretch, so conveyor numbers stay easy to read.
        let (sx, sy) = Self.squashStretch(for: b, stretchX: 1 + (stretchX - 1) * 0.5)
        let grow = 1 + b.pop * 0.25
        face.xScale = sx * grow
        face.yScale = -sy * grow

        if selected {
            strokeColor = K.ink
            lineWidth = 3.5
        } else {
            strokeColor = rimColor
            lineWidth = 1.2
        }
    }

    private func applyValue(_ b: Blob) {
        shownValue = b.v
        let base = K.color(for: b.v)
        body.fillColor = base
        fillColor = base.mixed(with: .black, by: 0.28)
        rimColor = base.mixed(with: .black, by: 0.5)

        // The rounded heavy face runs wider than the web's bold, so 4-digit values get a bit smaller.
        let size = max(9, b.r * 0.62 * (b.v >= 1000 ? 0.85 : 1))
        var font = UIFont.systemFont(ofSize: size, weight: .heavy)
        if let rounded = font.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: rounded, size: size)
        }
        let ink = b.v == 128 ? UIColor(hex: 0x7a2850) : UIColor(white: 1, alpha: 0.95)
        let shadowInk = base.mixed(with: .black, by: 0.5).withAlphaComponent(0.75)
        let lightInk = UIColor(white: 1, alpha: b.v == 128 ? 0.6 : 0.45)
        for (l, c) in [(label, ink), (labelShadow, shadowInk), (labelLight, lightInk)] {
            l.attributedText = NSAttributedString(string: String(b.v), attributes: [.font: font, .foregroundColor: c])
        }
        // Light from the top left, matching the highlight. Offsets grow with the text size.
        let d = max(0.6, size * 0.06)
        label.position = CGPoint(x: 0, y: -1)
        labelLight.position = CGPoint(x: -d * 0.7, y: -1 + d * 0.7)
        labelShadow.position = CGPoint(x: d, y: -1 - d * 1.2)
    }

    static func squashStretch(for b: Blob, stretchX: CGFloat) -> (sx: CGFloat, sy: CGFloat) {
        let sq = b.squash
        return (stretchX * (1 + sq), (1 - sq * 0.8) / stretchX.squareRoot())
    }

    static func path(for b: Blob, stretchX: CGFloat, t: TimeInterval) -> CGPath {
        let n = b.seed.count
        let (sx, sy) = squashStretch(for: b, stretchX: stretchX)
        let tt = CGFloat(t)
        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            let a = b.rot + CGFloat(i) / CGFloat(n) * .pi * 2
            let wob = 1 + sin(tt * 3 + CGFloat(i) * 1.7 + b.id * 10) * 0.03
            let rr = b.r * b.seed[i] * wob * (1 + b.pop * 0.25)
            pts.append(CGPoint(x: cos(a) * rr * sx, y: sin(a) * rr * sy))
        }
        func mid(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }
        let path = CGMutablePath()
        path.move(to: mid(pts[n - 1], pts[0]))
        for i in 0..<n {
            path.addQuadCurve(to: mid(pts[i], pts[(i + 1) % n]), control: pts[i])
        }
        path.closeSubpath()
        return path
    }
}
