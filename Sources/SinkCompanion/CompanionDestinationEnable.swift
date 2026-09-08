import CoreDomain
import DestinationTrust
import Foundation
import WireFormat

/// Completes R-25 before a companion destination can carry health payloads.
public enum CompanionDestinationEnable {
    public static func complete(
        testPipe: any CompanionBytePipe,
        deliveryPipe: any CompanionBytePipe,
        installationID: String,
        emittedAt: String,
        canaryCode: String = "OHE1-COMP"
    ) async throws -> (
        destination: VerifiedDestination,
        events: [TrustEvent],
        report: DestinationTestReport
    ) {
        let batchID = "00000000-0000-4000-8000-000000000002"
        let preview = try NativeWire.encodeCanary(
            code: canaryCode,
            batchID: BatchID(rawValue: batchID),
            envelope: WireEnvelope(
                exporterId: installationID,
                seq: 1,
                emittedAt: emittedAt,
                observedAt: emittedAt
            )
        )
        var setup = DestinationSetup()
        try setup.recordPreview(preview)
        try setup.markCanarySent(code: canaryCode)
        try setup.confirmCanary(canaryCode)
        try setup.pinWithoutTLS()
        let report = await CompanionDestinationTest.run(
            pipe: testPipe,
            installationID: installationID,
            canary: preview,
            batchID: batchID
        )
        try setup.recordTest(report)
        let destination = try setup.enable(
            sink: CompanionSink(pipe: deliveryPipe, installationID: installationID)
        )
        return (destination, setup.drainEvents(), report)
    }

    public static func resume(
        deliveryPipe: any CompanionBytePipe,
        installationID: String,
        testReport: DestinationTestReport
    ) throws -> VerifiedDestination {
        var setup = DestinationSetup()
        try setup.resumeEnabled(testReport: testReport)
        return try setup.enable(
            sink: CompanionSink(pipe: deliveryPipe, installationID: installationID)
        )
    }
}
