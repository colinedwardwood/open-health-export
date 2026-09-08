import CoreDomain
import Foundation
import HealthKit

public struct HealthAuthorizationGrant: Sendable, Equatable {
    public var id: String
    public var metrics: [MetricID]

    public init(id: String, metrics: [MetricID]) {
        self.id = id
        self.metrics = metrics
    }
}

public enum HealthAuthorizationRequestState: String, Sendable, Codable {
    case unknown
    case unnecessary
    case shouldRequest
}

public struct HealthAuthorizationChange: Sendable, Equatable {
    public var grant: HealthAuthorizationGrant
    public var observedAtEpoch: TimeInterval

    public init(grant: HealthAuthorizationGrant, observedAtEpoch: TimeInterval) {
        self.grant = grant
        self.observedAtEpoch = observedAtEpoch
    }
}

public protocol HealthAuthorizationStatusProvider: Sendable {
    func requestState(for metrics: [MetricID]) async throws -> HealthAuthorizationRequestState
}

public struct HealthKitAuthorizationStatusProvider: HealthAuthorizationStatusProvider {
    private let store: HKHealthStore

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    public func requestState(
        for metrics: [MetricID]
    ) async throws -> HealthAuthorizationRequestState {
        let readTypes = Set(metrics.compactMap(SampleConversion.quantityType(for:)))
        let status: HKAuthorizationRequestStatus = try await withCheckedThrowingContinuation {
            continuation in
            store.getRequestStatusForAuthorization(
                toShare: Set<HKSampleType>(),
                read: readTypes
            ) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
        switch status {
        case .unknown:
            return .unknown
        case .shouldRequest:
            return .shouldRequest
        case .unnecessary:
            return .unnecessary
        @unknown default:
            return .unknown
        }
    }
}

public actor HealthAuthorizationObserver {
    private let provider: any HealthAuthorizationStatusProvider
    private let recordURL: URL

    public init(
        provider: any HealthAuthorizationStatusProvider = HealthKitAuthorizationStatusProvider(),
        recordURL: URL
    ) {
        self.provider = provider
        self.recordURL = recordURL
    }

    /// R-44's observable revocation signal is a transition from `.unnecessary`
    /// to `.shouldRequest`; it is not evidence that an empty read means denial.
    public func observe(
        grants: [HealthAuthorizationGrant],
        atEpoch: TimeInterval
    ) async throws -> [HealthAuthorizationChange] {
        var prior = load()
        var changes: [HealthAuthorizationChange] = []
        for grant in grants {
            let observed = try await provider.requestState(for: grant.metrics)
            if prior[grant.id] == .unnecessary, observed == .shouldRequest {
                changes.append(
                    HealthAuthorizationChange(grant: grant, observedAtEpoch: atEpoch)
                )
            }
            if observed != .unknown {
                prior[grant.id] = observed
            }
        }
        try persist(prior)
        return changes
    }

    private func load() -> [String: HealthAuthorizationRequestState] {
        guard let data = try? Data(contentsOf: recordURL),
              let states = try? JSONDecoder().decode(
                  [String: HealthAuthorizationRequestState].self,
                  from: data
              )
        else {
            return [:]
        }
        return states
    }

    private func persist(
        _ states: [String: HealthAuthorizationRequestState]
    ) throws {
        try FileManager.default.createDirectory(
            at: recordURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(states).write(to: recordURL, options: .atomic)
    }
}

public enum HealthKitBackgroundDelivery {
    public static func disable(
        metrics: [MetricID],
        store: HKHealthStore = HKHealthStore()
    ) async {
        for metric in metrics {
            guard let type = SampleConversion.quantityType(for: metric) else { continue }
            try? await store.disableBackgroundDelivery(for: type)
        }
    }
}
