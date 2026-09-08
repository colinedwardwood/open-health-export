import CoreDomain
import DestinationTrust
import Foundation
import WireFormat

/// Completes R-25 for a local folder: canary preview, pin-without-TLS, real-path
/// write/read/confirm, then `DestinationSetup.enable`.
public enum LocalFileDestinationEnable {
    public static func complete(
        directory: URL,
        exporterId: String,
        emittedAt: String,
        canaryCode: String = "OHE1-FILE"
    ) throws -> (destination: VerifiedDestination, events: [TrustEvent], report: DestinationTestReport) {
        let preview = try NativeWire.encodeCanary(
            code: canaryCode,
            batchID: BatchID(rawValue: "00000000-0000-4000-8000-000000000001"),
            envelope: WireEnvelope(
                exporterId: exporterId,
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
        let report = try LocalFileDestinationTest.run(directory: directory)
        try setup.recordTest(report)
        let verified = try setup.enable(sink: LocalFileSink(directory: directory))
        return (verified, setup.drainEvents(), report)
    }

    public static func resume(
        directory: URL,
        testReport: DestinationTestReport
    ) throws -> VerifiedDestination {
        var setup = DestinationSetup()
        try setup.resumeEnabled(testReport: testReport)
        return try setup.enable(sink: LocalFileSink(directory: directory))
    }
}
