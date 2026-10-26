import UIKit

@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)

    /// Wakes the haptic engine ahead of the first fling, so that first tap doesn't stall a frame.
    static func prepare() {
        light.prepare()
        medium.prepare()
        heavy.prepare()
    }

    static func fling() {
        light.impactOccurred()
        light.prepare()
    }

    /// Stronger for bigger values; 512 and up get a heavy thump.
    static func merge(_ v: Int) {
        if v >= 512 {
            heavy.impactOccurred()
            heavy.prepare()
        } else {
            medium.impactOccurred(intensity: min(1, 0.5 + log2(CGFloat(v)) * 0.06))
            medium.prepare()
        }
    }
}
