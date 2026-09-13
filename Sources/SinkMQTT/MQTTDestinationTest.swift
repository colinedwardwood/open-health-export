// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import DestinationTrust
import Foundation
import NetEgress
import WireFormat

/// R-25 MQTT test: TLS when mqtts, CONNECT/CONNACK, PUBLISH canary, PUBACK when QoS confirms delivery.
/// Subscribe is intentionally absent (ADR-0003 publish-only).
public enum MQTTDestinationTest {
    public static func run(
        destination: MQTTDestination,
        pipe: any MQTTBytePipe,
        canary: Data,
        pin: PinRecord? = nil,
        observedAt: String = "1970-01-01T00:00:00Z",
        onProgress: DestinationTestProgress? = nil
    ) async -> DestinationTestReport {
        let mqtts = destination.url.scheme?.lowercased() == "mqtts"
        let extra = (mqtts ? 1 : 0) + (pin == nil ? 0 : 1)
        let total = (destination.confirmsDelivery ? 3 : 2) + extra
        var steps: [DestinationTestStepReport] = []
        var index = 0
        if mqtts {
            index += 1
            onProgress?(index, total, .tlsHandshake)
            let identity = await pipe.identity()
            guard identity != nil else {
                return .failed(at: .tlsHandshake)
            }
            steps.append(DestinationTestStepReport(name: .tlsHandshake, outcome: .passed))
        }
        if let pin {
            index += 1
            onProgress?(index, total, .confirmCertificate)
            switch PinGate.evaluate(
                observed: await pipe.identity(),
                stored: pin,
                policy: pin.policy,
                observedAt: observedAt
            ) {
            case .matched, .noTLS:
                steps.append(DestinationTestStepReport(name: .confirmCertificate, outcome: .passed))
            default:
                return .failed(at: .confirmCertificate, prior: steps)
            }
        }

        let session = MQTTSession(pipe: pipe)
        index += 1
        onProgress?(index, total, .connect)
        do {
            try await session.connect(destination: destination)
        } catch {
            return .failed(at: .connect, prior: steps)
        }
        steps.append(DestinationTestStepReport(name: .connect, outcome: .passed))

        index += 1
        onProgress?(index, total, .publishCanary)
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
            index += 1
            onProgress?(index, total, .receiveEcho)
            steps.append(DestinationTestStepReport(name: .receiveEcho, outcome: .passed))
            return DestinationTestReport(verdict: .passed, steps: steps)
        }
        steps.append(
            DestinationTestStepReport(name: .publishCanary, outcome: .sentUnconfirmed)
        )
        return DestinationTestReport(verdict: .sentUnconfirmed, steps: steps)
    }
}
