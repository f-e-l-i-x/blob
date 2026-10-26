import UIKit

@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)

    static func fling() {
        light.impactOccurred()
        light.prepare()
    }

    static func merge() {
        medium.impactOccurred()
        medium.prepare()
    }
}
