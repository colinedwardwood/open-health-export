// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum LaunchMark {
    static let start = ContinuousClock.now

    static func millisecondsToNow() -> Double {
        let elapsed = start.duration(to: .now)
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
    }
}
