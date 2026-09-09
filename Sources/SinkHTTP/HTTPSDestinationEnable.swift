import CoreDomain
import DestinationTrust
import Foundation
import NetEgress
import WireFormat

public enum HTTPSDestinationEnable {
    public static func complete(
        destination: HTTPSDestination,
        transport: any HTTPTransport,
        exporterID: String,
        emittedAt: String,
        pinPolicy: PinPolicy = .leaf,
        canaryCode: String = "OHE1-HTTPS"
    ) async throws -> (
        destination: VerifiedDestination,
        events: [TrustEvent],
        report: DestinationTestReport,
        identity: TLSIdentity?
    ) {
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

        let report = await HTTPSDestinationTest.run(
            destination: destination,
            transport: transport,
            pin: setup.pin,
            canary: canary,
            observedAt: emittedAt
        )
        try setup.recordTest(report)
        let verified = try setup.enable(
            sink: HTTPSSink(destination: destination, transport: transport)
        )
        return (
            verified,
            setup.drainEvents(),
            report,
            identity
        )
    }
}
