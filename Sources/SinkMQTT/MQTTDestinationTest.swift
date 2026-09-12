// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import DestinationTrust
import Foundation
import WireFormat

/// R-25 MQTT test: CONNECT/CONNACK, PUBLISH canary, PUBACK when QoS confirms delivery.
/// Subscribe is intentionally absent (ADR-0003 publish-only).
public enum MQTTDestinationTest {
    public static func run(
        destination: MQTTDestination,
        pipe: any MQTTBytePipe,
        canary: Data,
        onProgress: DestinationTestProgress? = nil
    ) async -> DestinationTestReport {
        let total = destination.confirmsDelivery ? 3 : 2
        var steps: [DestinationTestStepReport] = []
        let session = MQTTSession(pipe: pipe)
        onProgress?(1, total, .connect)
        do {
            try await session.connect(destination: destination)
        } catch {
            return .failed(at: .connect)
        }
        steps.append(DestinationTestStepReport(name: .connect, outcome: .passed))

        onProgress?(2, total, .publishCanary)
        do {
            try await session.publish(
                topic: try destination.resolvedTopic(batchID: "canary"),
                payload: canary,
                qos: destination.qos
            )
            try await session.disconnect()
        } catch {
            return .failed(at: .publishCanary, prior: steps)
        }

        if destination.confirmsDelivery {
            steps.append(DestinationTestStepReport(name: .publishCanary, outcome: .passed))
            onProgress?(3, total, .receiveEcho)
            steps.append(DestinationTestStepReport(name: .receiveEcho, outcome: .passed))
            return DestinationTestReport(verdict: .passed, steps: steps)
        }
        steps.append(
            DestinationTestStepReport(name: .publishCanary, outcome: .sentUnconfirmed)
        )
        return DestinationTestReport(verdict: .sentUnconfirmed, steps: steps)
    }
}
