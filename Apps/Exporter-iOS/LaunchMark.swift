import Foundation

enum LaunchMark {
    static let start = ContinuousClock.now

    static func millisecondsToNow() -> Double {
        let elapsed = start.duration(to: .now)
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
    }
}
