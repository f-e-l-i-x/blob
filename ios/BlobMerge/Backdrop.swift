import SpriteKit

// iOS-only scenery, each piece drawn once into a texture: the table background, and the
// "machine" around the game: a glass jar on a stand, with a dispenser lid on top and pipes
// that carry the conveyor in and out.
//
// Machine textures are drawn in world coordinates (y down) inside their `rect`; their sprites
// sit at the rect's centre with yScale = -1 to undo the world flip.
enum Backdrop {
    static var cupPath: CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: K.segs[0].x1, y: K.segs[0].y1))
        for s in K.segs { p.addLine(to: CGPoint(x: s.x2, y: s.y2)) }
        p.closeSubpath()
        return p
    }

    /// The jar's walls without the top: left wall, chamfers, bottom, right wall.
    static var wallPath: CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: K.segs[0].x1, y: K.segs[0].y1))
        for s in K.segs.prefix(5) { p.addLine(to: CGPoint(x: s.x2, y: s.y2)) }
        return p
    }

    static let cupRect = CGRect(x: 0, y: 0, width: K.W, height: K.H)
    static let lidRect = CGRect(x: -4, y: -46, width: K.W + 8, height: 62)
    static let meterRect = CGRect(x: 130, y: -30, width: 140, height: 14)
    static let standRect = CGRect(x: 0, y: 428, width: K.W, height: 48)
    static let standShadowRect = CGRect(x: -40, y: 440, width: K.W + 80, height: 70)
    static func pipeRect(left: Bool) -> CGRect {
        left ? CGRect(x: -80, y: 24, width: 98, height: 56) : CGRect(x: K.W - 18, y: 24, width: 98, height: 56)
    }

    static let graphite = [UIColor(hex: 0x5a616b), UIColor(hex: 0x353b43), UIColor(hex: 0x22262c)]

    private static let space = CGColorSpaceCreateDeviceRGB()

    private static func gradient(_ colors: [UIColor], _ locations: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: colors.map(\.cgColor) as CFArray, locations: locations)!
    }

    private static func render(_ size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return SKTexture(image: UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) })
    }

    /// Renders a piece of the machine with world coordinates inside `rect`.
    private static func world(_ rect: CGRect, scale: CGFloat = 3, _ draw: (CGContext) -> Void) -> SKTexture {
        render(rect.size, scale: scale) { ctx in
            ctx.translateBy(x: -rect.minX, y: -rect.minY)
            draw(ctx)
        }
    }

    /// Fills `path` with a top-to-bottom gradient between y0 and y1.
    private static func fill(_ ctx: CGContext, _ path: CGPath, _ colors: [UIColor], _ locations: [CGFloat], y0: CGFloat, y1: CGFloat) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.drawLinearGradient(gradient(colors, locations), start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1), options: [])
        ctx.restoreGState()
    }

    // MARK: - Background

    /// Grey table: lighter at the top, a soft pool of light around `light`, and faint grain.
    /// In screen points with y down; the sprite sits in the scene, not the world.
    static func background(size: CGSize, light: CGPoint) -> SKTexture {
        render(size, scale: 2) { ctx in
            ctx.drawLinearGradient(gradient([UIColor(hex: 0xd6d6d6), UIColor(hex: 0xb8b8b8)], [0, 1]),
                                   start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            ctx.drawRadialGradient(gradient([UIColor(white: 1, alpha: 0.35), UIColor(white: 1, alpha: 0)], [0, 1]),
                                   startCenter: light, startRadius: 0, endCenter: light,
                                   endRadius: max(size.width, size.height) * 0.6, options: [])
            let light = UIColor(white: 1, alpha: 0.05).cgColor, dark = UIColor(white: 0, alpha: 0.05).cgColor
            for _ in 0..<Int(size.width * size.height / 5) {
                ctx.setFillColor(Bool.random() ? light : dark)
                ctx.fill(CGRect(x: .random(in: 0..<size.width), y: .random(in: 0..<size.height), width: 0.5, height: 0.5))
            }
        }
    }

    // MARK: - Glass jar

    /// The back of the jar: faintly cool white, darker toward the bottom, with a soft inner
    /// shadow along the walls. Covers `cupRect`.
    static func cupInterior() -> SKTexture {
        world(cupRect) { ctx in
            let path = cupPath
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(gradient([UIColor(hex: 0xfbfdff), UIColor(hex: 0xe4ebf1)], [0, 1]),
                                   start: CGPoint(x: 0, y: K.Cup.t), end: CGPoint(x: 0, y: K.Cup.b), options: [])
            // inner shadow: fill everything outside the jar, casting a shadow inward
            ctx.setShadow(offset: .zero, blur: 16, color: UIColor(hex: 0x203040, alpha: 0.2).cgColor)
            let outside = CGMutablePath()
            outside.addRect(cupRect.insetBy(dx: -100, dy: -100))
            outside.addPath(path)
            ctx.addPath(outside)
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fillPath(using: .evenOdd)
        }
    }

    /// Reflections on the front of the glass, drawn over the blobs: two soft vertical streaks
    /// on the left, a thin one on the right and a curved glint above the bottom. Covers `cupRect`.
    static func glassFront() -> SKTexture {
        world(cupRect) { ctx in
            ctx.addPath(cupPath)
            ctx.clip()
            func streak(x: CGFloat, width: CGFloat, alpha: CGFloat, top: CGFloat, bottom: CGFloat) {
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                ctx.drawLinearGradient(gradient([UIColor(white: 1, alpha: 0), UIColor(white: 1, alpha: alpha), UIColor(white: 1, alpha: 0)], [0, 0.5, 1]),
                                       start: CGPoint(x: x, y: 0), end: CGPoint(x: x + width, y: 0), options: [])
                // fade the ends out
                ctx.setBlendMode(.destinationIn)
                ctx.drawLinearGradient(gradient([.clear, .white, .white, .clear], [0, 0.2, 0.75, 1]),
                                       start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
                ctx.setBlendMode(.normal)
                ctx.endTransparencyLayer()
            }
            streak(x: 22, width: 26, alpha: 0.5, top: 20, bottom: 400)
            streak(x: 54, width: 8, alpha: 0.35, top: 40, bottom: 330)
            streak(x: 358, width: 16, alpha: 0.3, top: 30, bottom: 380)
            let glint = CGMutablePath()
            glint.move(to: CGPoint(x: 70, y: 420))
            glint.addQuadCurve(to: CGPoint(x: 200, y: 416), control: CGPoint(x: 130, y: 414))
            ctx.addPath(glint)
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.45).cgColor)
            ctx.setLineWidth(3)
            ctx.setLineCap(.round)
            ctx.strokePath()
        }
    }

    // MARK: - Dispenser

    /// The dispenser lid: a graphite housing over the jar's opening, with screws and a slot
    /// for the speed meter (`meterRect`). Covers `lidRect`.
    static func lid() -> SKTexture {
        world(lidRect) { ctx in
            let body = CGPath(roundedRect: lidRect, cornerWidth: 14, cornerHeight: 14, transform: nil)
            fill(ctx, body, graphite, [0, 0.45, 1], y0: lidRect.minY, y1: lidRect.maxY)
            // lip over the jar's opening, a little darker
            fill(ctx, CGPath(rect: CGRect(x: lidRect.minX + 6, y: lidRect.maxY - 8, width: lidRect.width - 12, height: 6), transform: nil),
                 [UIColor(hex: 0x1a1d22), UIColor(hex: 0x15171b)], [0, 1], y0: lidRect.maxY - 8, y1: lidRect.maxY - 2)
            // top highlight
            ctx.addPath(CGPath(roundedRect: lidRect.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 12.5, cornerHeight: 12.5, transform: nil))
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.18).cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokePath()
            // meter slot, sunk into the housing
            let slot = CGPath(roundedRect: meterRect.insetBy(dx: -3, dy: -3), cornerWidth: 10, cornerHeight: 10, transform: nil)
            fill(ctx, slot, [UIColor(hex: 0x0c0e11), UIColor(hex: 0x1b1f24)], [0, 1], y0: meterRect.minY - 3, y1: meterRect.maxY + 3)
            ctx.addPath(slot)
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.12).cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
            // screws
            for x in [lidRect.minX + 18, lidRect.maxX - 18] {
                let c = CGPoint(x: x, y: meterRect.midY)
                let head = CGPath(ellipseIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9), transform: nil)
                fill(ctx, head, [UIColor(hex: 0x9aa2ad), UIColor(hex: 0x4a5059)], [0, 1], y0: c.y - 4.5, y1: c.y + 4.5)
                ctx.move(to: CGPoint(x: c.x - 2.5, y: c.y + 1))
                ctx.addLine(to: CGPoint(x: c.x + 2.5, y: c.y - 1))
                ctx.setStrokeColor(UIColor(hex: 0x2a2e34).cgColor)
                ctx.setLineWidth(1.2)
                ctx.strokePath()
            }
        }
    }

    /// A pipe feeding the conveyor in (left) or out (right), with a flange where it meets the
    /// jar wall. Drawn over the conveyor blobs, so they disappear into it. Covers `pipeRect`.
    static func pipe(left: Bool) -> SKTexture {
        let rect = pipeRect(left: left)
        return world(rect) { ctx in
            let tube = left ? CGRect(x: rect.minX, y: 30, width: rect.width - 10, height: 44)
                            : CGRect(x: rect.minX + 10, y: 30, width: rect.width - 10, height: 44)
            let tubeColors = [UIColor(hex: 0x6a727c), UIColor(hex: 0x3a4048), UIColor(hex: 0x262a30), UIColor(hex: 0x3a4048)]
            fill(ctx, CGPath(rect: tube, transform: nil), tubeColors, [0, 0.35, 0.8, 1], y0: tube.minY, y1: tube.maxY)
            let flange = left ? CGRect(x: rect.maxX - 14, y: rect.minY, width: 14, height: rect.height)
                              : CGRect(x: rect.minX, y: rect.minY, width: 14, height: rect.height)
            let f = CGPath(roundedRect: flange, cornerWidth: 4, cornerHeight: 4, transform: nil)
            fill(ctx, f, graphite, [0, 0.45, 1], y0: flange.minY, y1: flange.maxY)
            ctx.addPath(CGPath(roundedRect: flange.insetBy(dx: 1, dy: 1), cornerWidth: 3, cornerHeight: 3, transform: nil))
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.18).cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
        }
    }

    // MARK: - Stand

    /// The stand the jar sits on: a top plate and a wider foot. Covers `standRect`.
    static func stand() -> SKTexture {
        world(standRect) { ctx in
            let foot = CGRect(x: 14, y: 448, width: K.W - 28, height: 24)
            fill(ctx, CGPath(roundedRect: foot, cornerWidth: 10, cornerHeight: 10, transform: nil),
                 [UIColor(hex: 0x4a5059), UIColor(hex: 0x2b3036), UIColor(hex: 0x1c1f24)], [0, 0.4, 1], y0: foot.minY, y1: foot.maxY)
            let plate = CGRect(x: 36, y: 433, width: K.W - 72, height: 18)
            fill(ctx, CGPath(roundedRect: plate, cornerWidth: 7, cornerHeight: 7, transform: nil),
                 graphite, [0, 0.5, 1], y0: plate.minY, y1: plate.maxY)
            for r in [plate, foot] {
                ctx.move(to: CGPoint(x: r.minX + 10, y: r.minY + 1.5))
                ctx.addLine(to: CGPoint(x: r.maxX - 10, y: r.minY + 1.5))
            }
            ctx.setStrokeColor(UIColor(white: 1, alpha: 0.22).cgColor)
            ctx.setLineWidth(1.2)
            ctx.strokePath()
        }
    }

    /// Soft contact shadow on the table under the stand. Covers `standShadowRect`.
    static func standShadow() -> SKTexture {
        world(standShadowRect, scale: 2) { ctx in
            ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: UIColor(white: 0, alpha: 0.45).cgColor)
            ctx.addPath(CGPath(ellipseIn: CGRect(x: 10, y: 462, width: K.W - 20, height: 14), transform: nil))
            ctx.setFillColor(UIColor(white: 0, alpha: 0.35).cgColor)
            ctx.fillPath()
        }
    }

    // MARK: - Bumpers

    /// A glossy blue stud of radius `r`, lit from the top left, centred in a (2r + 2)² canvas.
    static func bumper(r: CGFloat) -> SKTexture {
        let side = r * 2 + 2
        return render(CGSize(width: side, height: side), scale: 3) { ctx in
            let c = CGPoint(x: side / 2, y: side / 2)
            let disc = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
            ctx.saveGState()
            ctx.addPath(disc)
            ctx.clip()
            let lit = CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4)
            ctx.drawRadialGradient(gradient([UIColor(hex: 0x74b4ff), UIColor(hex: 0x1e64c8), UIColor(hex: 0x0b3270)], [0, 0.55, 1]),
                                   startCenter: lit, startRadius: 0, endCenter: c, endRadius: r,
                                   options: [.drawsAfterEndLocation])
            let spot = CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.45)
            ctx.drawRadialGradient(gradient([UIColor(white: 1, alpha: 0.9), UIColor(white: 1, alpha: 0)], [0, 1]),
                                   startCenter: spot, startRadius: 0, endCenter: spot, endRadius: r * 0.42, options: [])
            ctx.restoreGState()
            ctx.addPath(disc)
            ctx.setStrokeColor(UIColor(hex: 0x0a2a5e).cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokePath()
        }
    }
}
