import CoreDomain
import DestinationTrust
import Foundation
import NetEgress
import WireFormat

/// Completes R-25 before an MQTT destination can carry health payloads.
public enum MQTTDestinationEnable {
    public static func complete(
        destination: MQTTDestination,
        pipe: any MQTTBytePipe,
        exporterID: String,
        emittedAt: String,
        identity: TLSIdentity? = nil,
        pinPolicy: PinPolicy = .leaf,
        canaryCode: String = "OHE1-MQTT"
    ) async throws -> (
        destination: VerifiedDestination,
        events: [TrustEvent],
        report: DestinationTestReport,
        identity: TLSIdentity?
    ) {
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
        let verified = try setup.enable(
            sink: MQTTSink(destination: destination, pipe: pipe)
        )
        return (verified, setup.drainEvents(), report, observed)
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
}
