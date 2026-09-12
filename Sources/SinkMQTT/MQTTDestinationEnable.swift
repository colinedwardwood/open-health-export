// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import DestinationTrust
import Foundation
import NetEgress
import WireFormat

public struct MQTTDestinationProbe: Sendable {
    public let destination: MQTTDestination
    public let report: DestinationTestReport
    public let identity: TLSIdentity?
    public let preview: Data
    public let pin: PinRecord?
    public let pendingEvents: [TrustEvent]
}

/// Completes R-25 before an MQTT destination can carry health payloads.
public enum MQTTDestinationEnable {
    public static func probe(
        destination: MQTTDestination,
        pipe: any MQTTBytePipe,
        exporterID: String,
        emittedAt: String,
        identity: TLSIdentity? = nil,
        pinPolicy: PinPolicy = .leaf,
        canaryCode: String = "OHE1-MQTT",
        meteredPolicy: MeteredNetworkPolicy = .refuseMetered,
        pathConditions: NetworkPathConditions = .clear
    ) async throws -> MQTTDestinationProbe {
        let prepared = try await prepare(
            destination: destination,
            pipe: pipe,
            exporterID: exporterID,
            emittedAt: emittedAt,
            identity: identity,
            pinPolicy: pinPolicy,
            canaryCode: canaryCode,
            meteredPolicy: meteredPolicy,
            pathConditions: pathConditions
        )
        guard prepared.report.allowsEnablement else {
            throw SetupError.verificationRequired
        }
        var setup = prepared.setup
        return MQTTDestinationProbe(
            destination: destination,
            report: prepared.report,
            identity: prepared.identity,
            preview: prepared.preview,
            pin: setup.pin,
            pendingEvents: setup.drainEvents()
        )
    }

    public static func commit(
        probe: MQTTDestinationProbe,
        pipe: any MQTTBytePipe
    ) throws -> (destination: VerifiedDestination, events: [TrustEvent]) {
        var setup = DestinationSetup()
        try setup.resumeAfterPassedTest(
            preview: probe.preview,
            pin: probe.pin,
            identity: probe.identity,
            testReport: probe.report
        )
        let verified = try setup.enable(
            sink: MQTTSink(destination: probe.destination, pipe: pipe)
        )
        return (verified, probe.pendingEvents + setup.drainEvents())
    }

    public static func complete(
        destination: MQTTDestination,
        pipe: any MQTTBytePipe,
        exporterID: String,
        emittedAt: String,
        identity: TLSIdentity? = nil,
        pinPolicy: PinPolicy = .leaf,
        canaryCode: String = "OHE1-MQTT",
        meteredPolicy: MeteredNetworkPolicy = .refuseMetered,
        pathConditions: NetworkPathConditions = .clear
    ) async throws -> (
        destination: VerifiedDestination,
        events: [TrustEvent],
        report: DestinationTestReport,
        identity: TLSIdentity?,
        preview: Data
    ) {
        let probe = try await probe(
            destination: destination,
            pipe: pipe,
            exporterID: exporterID,
            emittedAt: emittedAt,
            identity: identity,
            pinPolicy: pinPolicy,
            canaryCode: canaryCode,
            meteredPolicy: meteredPolicy,
            pathConditions: pathConditions
        )
        let committed = try commit(probe: probe, pipe: pipe)
        return (
            committed.destination,
            committed.events,
            probe.report,
            probe.identity,
            probe.preview
        )
    }

    public static func resume(
        destination: MQTTDestination,
        pipe: any MQTTBytePipe,
        testReport: DestinationTestReport
    ) throws -> VerifiedDestination {
        var setup = DestinationSetup()
        try setup.resumeEnabled(testReport: testReport)
        return try setup.enable(sink: MQTTSink(destination: destination, pipe: pipe))
    }

    private static func prepare(
        destination: MQTTDestination,
        pipe: any MQTTBytePipe,
        exporterID: String,
        emittedAt: String,
        identity: TLSIdentity?,
        pinPolicy: PinPolicy,
        canaryCode: String,
        meteredPolicy: MeteredNetworkPolicy,
        pathConditions: NetworkPathConditions
    ) async throws -> (
        setup: DestinationSetup,
        identity: TLSIdentity?,
        preview: Data,
        report: DestinationTestReport
    ) {
        try MeteredNetworkGate.require(path: pathConditions, policy: meteredPolicy)
        let canary = try NativeWire.encodeCanary(
            code: canaryCode,
            batchID: BatchID(rawValue: "00000000-0000-4000-8000-000000000090"),
            envelope: WireEnvelope(
                exporterId: exporterID,
                seq: 1,
                emittedAt: emittedAt,
                observedAt: emittedAt
            )
        )
        var setup = DestinationSetup()
        try setup.recordPreview(canary)
        try setup.markCanarySent(code: canaryCode)
        try setup.confirmCanary(canaryCode)
        let observed: TLSIdentity?
        if let identity {
            observed = identity
        } else {
            observed = await pipe.identity()
        }
        if destination.url.scheme?.lowercased() == "mqtts" {
            guard let observed else {
                throw EgressError.transport("mqtts destination returned no TLS identity")
            }
            try setup.recordPin(from: observed, at: emittedAt, policy: pinPolicy)
        } else {
            try setup.pinWithoutTLS()
        }
        let report = await MQTTDestinationTest.run(
            destination: destination,
            pipe: pipe,
            canary: canary
        )
        try setup.recordTest(report)
        return (setup, observed, canary, report)
    }
}
