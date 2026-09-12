// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// UX-45: the data-flow explainer is rendered from the person's actual
/// destinations. Hosts, protocols, and credential *kinds* appear; secrets do not.
public struct DataFlowHop: Sendable, Equatable, Identifiable {
    public var id: String
    public var host: String
    public var transport: String
    public var credential: String

    public init(id: String, host: String, transport: String, credential: String) {
        self.id = id
        self.host = host
        self.transport = transport
        self.credential = credential
    }

    public static let noNetwork = "no network"
    public static let bearerToken = "bearer token"
    public static let usernamePassword = "username + password"
    public static let clientCertificate = "client certificate"
    public static let pairing = "pairing"
    public static let noCredential = "no credential"
}

public enum DataFlowExplainer {
    public static let title = "Where this iPhone sends health data"
    public static let source = "Apple Health on this iPhone"
    public static let transform =
        "This app transforms to JSON. Nothing stays after a successful send."
    public static let nowhereElse =
        "Nowhere else. No account. No analytics. No crash reporting."
    public static let empty =
        "No destinations yet. Health stays on this iPhone until you add one."

    public static func typeCountCopy(_ count: Int) -> String {
        if count <= 0 {
            return "No types selected yet."
        }
        if count == 1 {
            return "We read 1 type you chose."
        }
        return "We read \(count) types you chose."
    }

    public static func hopLine(_ hop: DataFlowHop) -> String {
        "\(hop.host) · \(hop.transport) · \(hop.credential)"
    }
}
