import EnginePorts
import Foundation

public enum DestinationTestStep: String, Sendable, Equatable, Codable {
    case openFolder
    case writeCanary
    case readBack
    case confirmBytes
    case resolveHost
    case tlsHandshake
    case confirmCertificate
    case authenticate
    case sendCanary
    case readResponse
    case connect
    case subscribe
    case publishCanary
    case receiveEcho
}

public enum DestinationTestStepOutcome: String, Sendable, Equatable, Codable {
    case passed
    case failed
    case sentUnconfirmed
}

public enum DestinationTestVerdict: String, Sendable, Equatable, Codable {
    case passed
    case failed
    case sentUnconfirmed
}

public struct DestinationTestStepReport: Sendable, Equatable, Codable {
    public var name: DestinationTestStep
    public var outcome: DestinationTestStepOutcome
    public var detail: String

    public init(name: DestinationTestStep, outcome: DestinationTestStepOutcome, detail: String = "") {
        self.name = name
        self.outcome = outcome
        self.detail = detail
    }
}

public struct DestinationTestReport: Sendable, Equatable, Codable {
    public var verdict: DestinationTestVerdict
    public var steps: [DestinationTestStepReport]

    public init(verdict: DestinationTestVerdict, steps: [DestinationTestStepReport]) {
        self.verdict = verdict
        self.steps = steps
    }

    /// Failed tests cannot enable. Unconfirmable transports may enable but never as success.
    public var allowsEnablement: Bool {
        verdict == .passed || verdict == .sentUnconfirmed
    }

    public var failingStep: DestinationTestStep? {
        steps.first { $0.outcome == .failed }?.name
    }

    public static let passedLocalFile = DestinationTestReport(
        verdict: .passed,
        steps: [
            DestinationTestStepReport(name: .openFolder, outcome: .passed),
            DestinationTestStepReport(name: .writeCanary, outcome: .passed),
            DestinationTestStepReport(name: .readBack, outcome: .passed),
            DestinationTestStepReport(name: .confirmBytes, outcome: .passed),
        ]
    )

    public static func failed(at step: DestinationTestStep, prior: [DestinationTestStepReport] = []) -> DestinationTestReport {
        DestinationTestReport(
            verdict: .failed,
            steps: prior + [DestinationTestStepReport(name: step, outcome: .failed)]
        )
    }
}

public enum DestinationTest {
    /// MQTT QoS 0 can never produce a passing test (R-25).
    public static func mqttVerdict(confirmsDelivery: Bool) -> DestinationTestVerdict {
        confirmsDelivery ? .passed : .sentUnconfirmed
    }
}
