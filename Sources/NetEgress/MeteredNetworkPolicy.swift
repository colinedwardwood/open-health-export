// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation

/// AR-31 / O18: cellular and other expensive or constrained paths are off by
/// default. A destination must opt in before any application byte is written.
public struct MeteredNetworkPolicy: Sendable, Equatable {
    public var allowsExpensive: Bool
    public var allowsConstrained: Bool

    public init(allowsExpensive: Bool, allowsConstrained: Bool) {
        self.allowsExpensive = allowsExpensive
        self.allowsConstrained = allowsConstrained
    }

    public static let refuseMetered = MeteredNetworkPolicy(
        allowsExpensive: false,
        allowsConstrained: false
    )
    public static let allowAll = MeteredNetworkPolicy(
        allowsExpensive: true,
        allowsConstrained: true
    )

    public static func fromAllowsMetered(_ allows: Bool) -> MeteredNetworkPolicy {
        allows ? .allowAll : .refuseMetered
    }
}

public struct NetworkPathConditions: Sendable, Equatable {
    public var isExpensive: Bool
    public var isConstrained: Bool

    public init(isExpensive: Bool, isConstrained: Bool) {
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }

    public static let clear = NetworkPathConditions(isExpensive: false, isConstrained: false)
}

public enum MeteredNetworkGate {
    public static func allows(
        path: NetworkPathConditions,
        policy: MeteredNetworkPolicy
    ) -> Bool {
        if path.isExpensive, !policy.allowsExpensive { return false }
        if path.isConstrained, !policy.allowsConstrained { return false }
        return true
    }

    public static func require(
        path: NetworkPathConditions,
        policy: MeteredNetworkPolicy
    ) throws {
        guard allows(path: path, policy: policy) else {
            throw DestinationSendError.awaitingUnmetered
        }
    }
}
