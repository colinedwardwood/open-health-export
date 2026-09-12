// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation
import Testing
import Watchdog

@Test func ux36TenFailuresInAnHourProduceOneNotification() {
    var state = NotificationRateLimitState()
    let results = (0 ..< 10).map { attempt in
        NotificationRateLimit.claim(
            kind: .exportFailed,
            destinationID: "destination-a",
            nowEpoch: TimeInterval(attempt * 6 * 60),
            state: &state
        )
    }
    #expect(results.filter { $0 }.count == 1)
}

@Test func ux36FailureLimitIsPerDestinationAndReopensAfterTwentyFourHours() {
    var state = NotificationRateLimitState()
    #expect(
        NotificationRateLimit.claim(
            kind: .exportFailed,
            destinationID: "destination-a",
            nowEpoch: 0,
            state: &state
        )
    )
    #expect(
        NotificationRateLimit.claim(
            kind: .exportFailed,
            destinationID: "destination-b",
            nowEpoch: 60,
            state: &state
        )
    )
    #expect(
        !NotificationRateLimit.claim(
            kind: .exportFailed,
            destinationID: "destination-a",
            nowEpoch: 23 * 60 * 60,
            state: &state
        )
    )
    #expect(
        NotificationRateLimit.claim(
            kind: .exportFailed,
            destinationID: "destination-a",
            nowEpoch: 24 * 60 * 60,
            state: &state
        )
    )
}

@Test func ux36OverdueAndFailedShareOneDestinationBucketWhileTrustBypassesIt() {
    var state = NotificationRateLimitState()
    #expect(
        NotificationRateLimit.claim(
            kind: .exportOverdue,
            destinationID: "destination-a",
            nowEpoch: 100,
            state: &state
        )
    )
    #expect(
        !NotificationRateLimit.claim(
            kind: .exportFailed,
            destinationID: "destination-a",
            nowEpoch: 200,
            state: &state
        )
    )
    #expect(
        NotificationRateLimit.claim(
            kind: .destinationTrustLost,
            destinationID: "destination-a",
            nowEpoch: 201,
            state: &state
        )
    )
}

@Test func ux36PlatformNotifierPersistsCooldownAndThreadsByDestination() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let notifier = try String(
        contentsOf: root.appendingPathComponent(
            "Apps/Exporter-iOS/LocalUserNotifier.swift"
        ),
        encoding: .utf8
    )
    #expect(notifier.contains("ohe.notificationCooldown.v1"))
    #expect(notifier.contains(#""dest.\(notice.destinationID)""#))
    #expect(notifier.contains(#""failure.\(notice.destinationID)""#))
    #expect(notifier.contains(#""notification_policy_version": 1"#))

    let harness = try String(
        contentsOf: root.appendingPathComponent(
            "Apps/Exporter-iOS/HarnessExport.swift"
        ),
        encoding: .utf8
    )
    for destinationID in ["local-file", "https", "mqtt", "companion"] {
        #expect(
            harness.contains("destinationID: \"\(destinationID)\""),
            "\(destinationID) failure path is not wired"
        )
    }
}
