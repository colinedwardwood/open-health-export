// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import Foundation

enum LaunchMark {
    static let start = ContinuousClock.now

    static func millisecondsToNow() -> Double {
        let elapsed = start.duration(to: .now)
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
    }
}
