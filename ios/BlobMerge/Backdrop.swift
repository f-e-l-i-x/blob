import SpriteKit

// iOS-only scenery, each drawn once into a texture: the table background, the cup's soft drop
// shadow, the shaded cup interior and the shiny bumper studs.
//
// Textures used in the world are drawn in UIKit's y-down space, the same as world coordinates;
// their sprites get yScale = -1 to undo the world flip.
enum Backdrop {
    static var cupPath: CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: K.segs[0].x1, y: K.segs[0].y1))
        for s in K.segs { p.addLine(to: CGPoint(x: s.x2, y: s.y2)) }
        p.closeSubpath()
        return p
    }

    /// Margin around the cup in the shadow texture, so the blur isn't cut off.
    static let shadowPad: CGFloat = 40

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

    /// Soft drop shadow under the cup, `shadowPad` larger than the world on every side.
    static func cupShadow() -> SKTexture {
        let pad = shadowPad
        return render(CGSize(width: K.W + pad * 2, height: K.H + pad * 2), scale: 2) { ctx in
            ctx.translateBy(x: pad, y: pad)
            ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 22, color: UIColor(white: 0, alpha: 0.4).cgColor)
            ctx.addPath(cupPath)
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fillPath()  // hidden under the cup itself; only the shadow shows
        }
    }

    /// Ceramic-white inside: slightly greyer toward the bottom, a soft inner shadow along the
    /// walls and a glassy sheen near the left wall. Covers the world rect (0, 0, W, H).
    static func cupInterior() -> SKTexture {
        render(CGSize(width: K.W, height: K.H), scale: 3) { ctx in
            let path = cupPath
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(gradient([.white, UIColor(white: 0.92, alpha: 1)], [0, 1]),
                                   start: CGPoint(x: 0, y: K.Cup.t), end: CGPoint(x: 0, y: K.Cup.b), options: [])

            // inner shadow: fill everything outside the cup, casting a shadow inward
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 16, color: UIColor(white: 0, alpha: 0.2).cgColor)
            let outside = CGMutablePath()
            outside.addRect(CGRect(x: -100, y: -100, width: K.W + 200, height: K.H + 200))
            outside.addPath(path)
            ctx.addPath(outside)
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()

            ctx.drawLinearGradient(gradient([UIColor(white: 1, alpha: 0), UIColor(white: 1, alpha: 0.85), UIColor(white: 1, alpha: 0)], [0, 0.5, 1]),
                                   start: CGPoint(x: 34, y: 0), end: CGPoint(x: 84, y: 0), options: [])
        }
    }

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
