import CoreDomain
import CoreTemporal
import EnginePorts
import Foundation

public struct StalenessPolicy: Sendable {
    public var defaultInterval: TimeInterval
    public init(defaultInterval: TimeInterval = 6 * 3600) {
        self.defaultInterval = defaultInterval
    }

    public func shouldEscalate(lastSuccess: Date?, now: Date) -> Bool {
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= defaultInterval
    }
}
