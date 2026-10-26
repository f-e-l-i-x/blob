import UIKit

@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)

    /// Wakes the haptic engine ahead of the first fling, so that first tap doesn't stall a frame.
    static func prepare() {
        light.prepare()
        medium.prepare()
    }

    static func fling() {
        light.impactOccurred()
        light.prepare()
    }

    static func merge() {
        medium.impactOccurred()
        medium.prepare()
    }
}
