import SpriteKit

// One blob on screen: the wobbly soft shape (blobPath/drawBlob in index.html) plus its number.
// Lives under GameScene's flipped world node, so coordinates are world units with y down.
final class BlobNode: SKShapeNode {
    private let label = SKLabelNode()
    private var shownValue = 0

    override init() {
        super.init()
        strokeColor = .clear
        lineWidth = 0
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.yScale = -1  // undo the world flip so the text reads upright
        label.position = CGPoint(x: 0, y: 1)
        label.zPosition = 0.5
        addChild(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ b: Blob, stretchX: CGFloat, selected: Bool, t: TimeInterval, z: CGFloat) {
        isHidden = false
        zPosition = z
        position = CGPoint(x: b.x, y: b.y)
        path = Self.path(for: b, stretchX: stretchX, t: t)
        if selected {
            strokeColor = K.ink
            lineWidth = 3.5
        } else {
            strokeColor = .clear
            lineWidth = 0
        }
        if shownValue != b.v {
            shownValue = b.v
            fillColor = K.color(for: b.v)
            let ink = b.v == 128 ? UIColor(hex: 0x7a2850) : UIColor(white: 1, alpha: 0.88)
            label.attributedText = NSAttributedString(string: String(b.v), attributes: [
                .font: UIFont.systemFont(ofSize: max(9, b.r * 0.62), weight: .bold),
                .foregroundColor: ink,
            ])
        }
    }

    static func path(for b: Blob, stretchX: CGFloat, t: TimeInterval) -> CGPath {
        let n = b.seed.count
        let sq = b.squash
        let sx = stretchX * (1 + sq), sy = (1 - sq * 0.8) / stretchX.squareRoot()
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
