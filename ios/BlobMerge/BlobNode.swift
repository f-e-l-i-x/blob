import CoreImage.CIFilterBuiltins
import SpriteKit

// One blob on screen: the wobbly soft shape (blobPath/drawBlob in index.html) plus its number.
// Lives under GameScene's flipped world node, so coordinates are world units with y down.
//
// iOS-only shading, all built from the same outline: this node fills it in a darker shade
// (bottom shadow crescent) with a thin rim, `body` is the main colour shifted up and shrunk
// a little, and `highlight` is a small glossy copy near the top left.
//
// The number is embossed (light edge up-left, dark edge down-right) and bulged as if printed
// on a dome. That is baked once per value into a texture; `face` squashes and stretches it
// with the blob, and it sits under the highlight as if inside the jelly.
//
// The jelly deformation (pill stretch, squash along the last hit, stretch along the motion) is
// one 2x2 matrix. The outline uses it directly; the number gets it split into rotate, scale,
// rotate (faceTurn, face's scale, faceTurnBack), which SKNodes can express.
final class BlobNode: SKShapeNode {
    private let body = SKShapeNode()
    private let highlight = SKShapeNode()
    private let faceTurn = SKNode()
    private let faceTurnBack = SKNode()
    private let face = SKNode()
    private let number = SKSpriteNode()
    private var shownValue = 0
    private var rimColor = UIColor.clear

    override init() {
        super.init()
        for n in [body, highlight] {
            n.strokeColor = .clear
            n.lineWidth = 0
        }
        body.zPosition = 0.1
        faceTurn.zPosition = 0.2
        highlight.zPosition = 0.6
        highlight.fillColor = UIColor(white: 1, alpha: 0.3)
        addChild(body)
        addChild(faceTurn)
        faceTurn.addChild(faceTurnBack)
        faceTurnBack.addChild(face)
        addChild(highlight)
        // `face` undoes the world flip (negative yScale), so its children use y-up coordinates.
        number.position = CGPoint(x: 0, y: -1)
        face.addChild(number)
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
        let m = Self.deformation(for: b, stretchX: 1 + (stretchX - 1) * 0.5)
        let (turn, sx, sy, turnBack) = Self.split(m)
        let grow = 1 + b.pop * 0.25
        faceTurn.zRotation = turn
        faceTurn.xScale = sx * grow
        faceTurn.yScale = sy * grow
        faceTurnBack.zRotation = turnBack
        face.yScale = -1

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
        let (texture, size) = Self.numberTexture(for: b)
        number.texture = texture
        number.size = size
    }

    // MARK: - Number texture

    private static var numberTextures: [Int: (SKTexture, CGSize)] = [:]
    private static let ciContext = CIContext()
    static let bulge: Float = 0.3  // CIBumpDistortion scale; 0 = flat

    /// The embossed, bulged number for a value, rendered once and cached. Size is in world units.
    private static func numberTexture(for b: Blob) -> (SKTexture, CGSize) {
        if let cached = numberTextures[b.v] { return cached }

        // The rounded heavy face runs wider than the web's bold, so 4-digit values get a bit smaller.
        let fontSize = max(9, b.r * 0.62 * (b.v >= 1000 ? 0.85 : 1))
        var font = UIFont.systemFont(ofSize: fontSize, weight: .heavy)
        if let rounded = font.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: rounded, size: fontSize)
        }
        let base = K.color(for: b.v)
        let ink = b.v == 128 ? UIColor(hex: 0x7a2850) : UIColor(white: 1, alpha: 0.95)
        let shadowInk = base.mixed(with: .black, by: 0.5).withAlphaComponent(0.75)
        let lightInk = UIColor(white: 1, alpha: b.v == 128 ? 0.6 : 0.45)

        // Light from the top left, matching the highlight. Offsets grow with the text size.
        let d = max(0.6, fontSize * 0.06)
        let text = String(b.v) as NSString
        let width = text.size(withAttributes: [.font: font]).width
        // Extra room around the digits so the bulge doesn't push them off the canvas.
        let size = CGSize(width: ceil(width * 1.25 + d * 4), height: ceil(font.capHeight * 1.9 + d * 4))
        // Draw so the digits (cap height) are centred on the canvas.
        let origin = CGPoint(x: (size.width - width) / 2, y: size.height / 2 - (font.ascender - font.capHeight / 2))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 4
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            for (c, dx, dy) in [(shadowInk, d, d * 1.2), (lightInk, -d * 0.7, -d * 0.7), (ink, 0, 0)] {
                text.draw(at: CGPoint(x: origin.x + dx, y: origin.y + dy), withAttributes: [.font: font, .foregroundColor: c])
            }
        }

        var result = (SKTexture(image: image), size)
        if let cg = image.cgImage {
            let input = CIImage(cgImage: cg)
            let bump = CIFilter.bumpDistortion()
            bump.inputImage = input
            bump.center = CGPoint(x: input.extent.midX, y: input.extent.midY)
            bump.radius = Float(max(input.extent.width, input.extent.height) * 0.55)
            bump.scale = bulge
            if let out = bump.outputImage?.cropped(to: input.extent),
               let bulged = ciContext.createCGImage(out, from: input.extent) {
                result.0 = SKTexture(cgImage: bulged)
            }
        }
        numberTextures[b.v] = result
        return result
    }

    /// Scales by `along` in the direction `angle` and by `across` perpendicular to it.
    private static func axisScale(_ angle: CGFloat, along: CGFloat, across: CGFloat) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: -angle)
            .concatenating(CGAffineTransform(scaleX: along, y: across))
            .concatenating(CGAffineTransform(rotationAngle: angle))
    }

    /// Pill stretch, then the squash spring along the last hit's normal (squeezed along it,
    /// bulging across; negative squash is the rebound stretch), then a stretch along the motion.
    static func deformation(for b: Blob, stretchX: CGFloat) -> CGAffineTransform {
        let sq = b.squash
        let speed = hypot(b.mvx, b.mvy)
        let e = min(0.18, speed / 3500)
        var m = CGAffineTransform(scaleX: stretchX, y: 1 / stretchX.squareRoot())
            .concatenating(axisScale(b.squashAngle, along: 1 - sq * 0.8, across: 1 + sq))
        if e > 0.001 {
            m = m.concatenating(axisScale(atan2(b.mvy, b.mvx), along: 1 + e, across: 1 - e * 0.5))
        }
        return m
    }

    /// Splits a 2x2 matrix into rotate(turn) * scale(sx, sy) * rotate(turnBack) (a closed-form SVD).
    static func split(_ t: CGAffineTransform) -> (turn: CGFloat, sx: CGFloat, sy: CGFloat, turnBack: CGFloat) {
        // column-vector form: [[t.a, t.c], [t.b, t.d]]
        let e = (t.a + t.d) / 2, f = (t.a - t.d) / 2, g = (t.b + t.c) / 2, h = (t.b - t.c) / 2
        let q = hypot(e, h), r = hypot(f, g)
        let a1 = atan2(g, f), a2 = atan2(h, e)
        return ((a2 + a1) / 2, q + r, q - r, (a2 - a1) / 2)
    }

    static func path(for b: Blob, stretchX: CGFloat, t: TimeInterval) -> CGPath {
        let n = b.seed.count
        let m = deformation(for: b, stretchX: stretchX)
        let tt = CGFloat(t)
        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            let a = b.rot + CGFloat(i) / CGFloat(n) * .pi * 2
            // slow idle wobble, plus a faster jiggle after hits and while moving
            let wob = 1 + sin(tt * 3 + CGFloat(i) * 1.7 + b.id * 10) * 0.03
                + sin(tt * 13 + CGFloat(i) * 2.9 + b.id * 7) * b.jiggle
            let rr = b.r * b.seed[i] * wob * (1 + b.pop * 0.25)
            pts.append(CGPoint(x: cos(a) * rr, y: sin(a) * rr).applying(m))
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
