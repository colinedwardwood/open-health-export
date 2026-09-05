import CoreDomain
import EnginePorts
import Redaction

public struct BundleAssembler: Sendable {
    public var maxRuns: Int
    public init(maxRuns: Int = 30) {
        self.maxRuns = maxRuns
    }

    public func previewLines(events: [RunEvent]) -> [String] {
        events.suffix(maxRuns).map { event in
            let fields = ["outcome": event.outcomeKind, "runID": event.runID.rawValue]
            return fields.keys.filter { Allowlist.permitted($0) }.sorted()
                .map { "\($0)=\(fields[$0] ?? "")" }
                .joined(separator: " ")
        }
    }
}
