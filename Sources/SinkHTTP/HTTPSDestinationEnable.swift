// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import DestinationTrust
import Foundation
import NetEgress
import WireFormat

public struct HTTPSDestinationProbe: Sendable {
    public let destination: HTTPSDestination
    public let report: DestinationTestReport
    public let identity: TLSIdentity?
    public let preview: Data
    public let pin: PinRecord?
    public let pendingEvents: [TrustEvent]
}

public enum HTTPSDestinationEnable {
    public static func probe(
        destination: HTTPSDestination,
        transport: any HTTPTransport,
        exporterID: String,
        emittedAt: String,
        pinPolicy: PinPolicy = .leaf,
        canaryCode: String = "OHE1-HTTPS",
        meteredPolicy: MeteredNetworkPolicy = .refuseMetered,
        pathConditions: NetworkPathConditions = .clear
    ) async throws -> HTTPSDestinationProbe {
        let prepared = try await prepare(
            destination: destination,
            transport: transport,
            exporterID: exporterID,
            emittedAt: emittedAt,
            pinPolicy: pinPolicy,
            canaryCode: canaryCode,
            meteredPolicy: meteredPolicy,
            pathConditions: pathConditions
        )
        guard prepared.report.allowsEnablement else {
            throw SetupError.verificationRequired
        }
        var setup = prepared.setup
        return HTTPSDestinationProbe(
            destination: destination,
            report: prepared.report,
            identity: prepared.identity,
            preview: prepared.preview,
            pin: setup.pin,
            pendingEvents: setup.drainEvents()
        )
    }

    public static func commit(
        probe: HTTPSDestinationProbe,
        transport: any HTTPTransport
    ) throws -> (destination: VerifiedDestination, events: [TrustEvent]) {
        var setup = DestinationSetup()
        try setup.resumeAfterPassedTest(
            preview: probe.preview,
            pin: probe.pin,
            identity: probe.identity,
            testReport: probe.report
        )
        let delivery: any HTTPTransport
        if let pin = probe.pin {
            delivery = PinningHTTPTransport(inner: transport, pin: pin)
        } else {
            delivery = transport
        }
        let verified = try setup.enable(
            sink: HTTPSSink(destination: probe.destination, transport: delivery)
        )
        return (verified, probe.pendingEvents + setup.drainEvents())
    }

    public static func complete(
        destination: HTTPSDestination,
        transport: any HTTPTransport,
        exporterID: String,
        emittedAt: String,
        pinPolicy: PinPolicy = .leaf,
        canaryCode: String = "OHE1-HTTPS",
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
            transport: transport,
            exporterID: exporterID,
            emittedAt: emittedAt,
            pinPolicy: pinPolicy,
            canaryCode: canaryCode,
            meteredPolicy: meteredPolicy,
            pathConditions: pathConditions
        )
        let committed = try commit(probe: probe, transport: transport)
        return (
            committed.destination,
            committed.events,
            probe.report,
            probe.identity,
            probe.preview
        )
    }

    private static func prepare(
        destination: HTTPSDestination,
        transport: any HTTPTransport,
        exporterID: String,
        emittedAt: String,
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
            batchID: BatchID(rawValue: "00000000-0000-4000-8000-000000000025"),
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

        let identity = try await transport.identityProbe()
        if destination.url.scheme?.lowercased() == "https" {
            guard let identity else {
                throw EgressError.transport("HTTPS destination returned no TLS identity")
            }
            try setup.recordPin(
                from: identity,
                at: emittedAt,
                policy: pinPolicy
            )
        } else {
            try setup.pinWithoutTLS()
        }

        let delivery: any HTTPTransport
        if let pin = setup.pin {
            delivery = PinningHTTPTransport(inner: transport, pin: pin)
        } else {
            delivery = transport
        }
        let report = await HTTPSDestinationTest.run(
            destination: destination,
            transport: delivery,
            pin: setup.pin,
            canary: canary,
            observedAt: emittedAt
        )
        try setup.recordTest(report)
        return (setup, identity, canary, report)
    }
}
