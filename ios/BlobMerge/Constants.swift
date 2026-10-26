import UIKit

// Ported from index.html. The world is a fixed 400 x 440 coordinate space (y pointing down)
// that GameScene scales to fit the screen.
enum K {
    static let W: CGFloat = 400
    static let H: CGFloat = 440

    enum Cup {
        static let l: CGFloat = 12
        static let r: CGFloat = 388
        static let t: CGFloat = 10
        static let b: CGFloat = 430
        static let chamfer: CGFloat = 40
    }

    // iOS screen layout, in points: header with the score, the jar machine, bottom bar.
    enum Layout {
        static let headerHeight: CGFloat = 86
        static let barHeight: CGFloat = 56
        static let sideMargin: CGFloat = 8
        // World-space extent of the machine: top of the dispenser lid to the stand's shadow.
        static let machineTop: CGFloat = -46
        static let machineBottom: CGFloat = 482
    }

    static let conveyorY: CGFloat = 52
    static let dangerY: CGFloat = 110
    static let gravity: CGFloat = 900

    static let colors: [Int: UIColor] = [
        1: UIColor(hex: 0xd81f26), 2: UIColor(hex: 0xe8621a), 4: UIColor(hex: 0x2a9a3a),
        8: UIColor(hex: 0x1f86c4), 16: UIColor(hex: 0x2238c9), 32: UIColor(hex: 0xa020b0),
        64: UIColor(hex: 0xd4205a), 128: UIColor(hex: 0xe6a0c0), 256: UIColor(hex: 0xf0b400),
        512: UIColor(hex: 0x14a89a), 1024: UIColor(hex: 0x6b3fd1), 2048: UIColor(hex: 0x111111),
    ]
    static func color(for v: Int) -> UIColor { colors[v] ?? UIColor(hex: 0x333333) }
    static func radius(for v: Int) -> CGFloat { 11 + log2(CGFloat(v)) * 4.2 }

    // Cup wall as segments (inner side). Bottom corners are chamfered.
    static let segs: [Segment] = [
        Segment(Cup.l, Cup.t, Cup.l, Cup.b - Cup.chamfer),
        Segment(Cup.l, Cup.b - Cup.chamfer, Cup.l + Cup.chamfer, Cup.b),
        Segment(Cup.l + Cup.chamfer, Cup.b, Cup.r - Cup.chamfer, Cup.b),
        Segment(Cup.r - Cup.chamfer, Cup.b, Cup.r, Cup.b - Cup.chamfer),
        Segment(Cup.r, Cup.b - Cup.chamfer, Cup.r, Cup.t),
        Segment(Cup.r, Cup.t, Cup.l, Cup.t),
    ]
    static let bumpers: [Circle] = [Circle(x: Cup.l, y: 175, r: 22), Circle(x: Cup.r, y: 175, r: 22)]

    // Page colours
    static let bg = UIColor(hex: 0xc9c9c9)
    static let ink = UIColor(hex: 0x111111)
    static let scoreInk = UIColor(hex: 0x6a7079)
    static let muted = UIColor(hex: 0x333333)
    static let button = UIColor(hex: 0x1e74c9)
}

struct Segment {
    let x1, y1, x2, y2: CGFloat
    init(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }
}

struct Circle {
    let x, y, r: CGFloat
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: alpha)
    }

    /// Blend toward `other`; `by` 0 keeps this colour, 1 gives `other`.
    func mixed(with other: UIColor, by f: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * f, green: g1 + (g2 - g1) * f,
                       blue: b1 + (b2 - b1) * f, alpha: a1 + (a2 - a1) * f)
    }
}
