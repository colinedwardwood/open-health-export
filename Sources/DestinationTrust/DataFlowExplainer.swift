// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import CoreDomain
/// UX-45: the data-flow explainer is rendered from the person's actual
/// destinations. Hosts, protocols, and credential *kinds* appear; secrets do not.
public struct DataFlowHop: Sendable, Equatable, Identifiable {
    public var id: String
    public var host: String
    public var transport: String
    public var credential: LocalizedCopy

    public init(id: String, host: String, transport: String, credential: LocalizedCopy) {
        self.id = id
        self.host = host
        self.transport = transport
        self.credential = credential
    }

    public static let noNetwork: LocalizedCopy = "no network"
    public static let bearerToken: LocalizedCopy = "bearer token"
    public static let usernamePassword: LocalizedCopy = "username + password"
    public static let clientCertificate: LocalizedCopy = "client certificate"
    public static let pairing: LocalizedCopy = "pairing"
    public static let webhookSecret: LocalizedCopy = "webhook secret"
    public static let noCredential: LocalizedCopy = "no credential"
}

public enum DataFlowExplainer {
    public static var title: LocalizedCopy {
        LocalizedCopy("Where %@ sends health data", .text(DeviceNoun.thisDevice))
    }
    public static var source: LocalizedCopy {
        LocalizedCopy("Apple Health on %@", .text(DeviceNoun.thisDevice))
    }
    public static let transform: LocalizedCopy =
        "This app transforms to JSON. Nothing stays after a successful send."
    public static let nowhereElse: LocalizedCopy =
        "Nowhere else. No account. No analytics. No crash reporting."
    public static var empty: LocalizedCopy {
        LocalizedCopy(
            "No destinations yet. Health stays on %@ until you add one.",
            .text(DeviceNoun.thisDevice)
        )
    }

    public static func typeCountCopy(_ count: Int) -> LocalizedCopy {
        if count <= 0 {
            return "No types selected yet."
        }
        return LocalizedCopy(
            "We read %lld types you chose.",
            .number(count),
            singular: "We read 1 type you chose."
        )
    }

    public static func hopLine(_ hop: DataFlowHop) -> LocalizedCopy {
        LocalizedCopy("%@ · %@ · %@", .text(hop.host), .text(hop.transport), .copy(hop.credential))
    }
}
