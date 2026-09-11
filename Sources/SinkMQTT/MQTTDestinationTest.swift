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
        canary: Data
    ) async -> DestinationTestReport {
        var steps: [DestinationTestStepReport] = []
        let session = MQTTSession(pipe: pipe)
        do {
            try await session.connect(destination: destination)
        } catch {
            return .failed(at: .connect)
        }
        steps.append(DestinationTestStepReport(name: .connect, outcome: .passed))

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
            steps.append(DestinationTestStepReport(name: .receiveEcho, outcome: .passed))
            return DestinationTestReport(verdict: .passed, steps: steps)
        }
        steps.append(
            DestinationTestStepReport(name: .publishCanary, outcome: .sentUnconfirmed)
        )
        return DestinationTestReport(verdict: .sentUnconfirmed, steps: steps)
    }
}
