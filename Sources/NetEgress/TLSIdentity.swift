import Foundation

public enum AddressClass: String, Sendable, Equatable {
    case loopback
    case privateRFC1918
    case linkLocal
    case publicUnicast
    case unknown
}

public struct TLSIdentity: Sendable, Equatable {
    public var leafSPKISha256: String
    public var issuerSPKISha256: String
    public var tlsVersion: String
    public var cipherSuite: String
    public var leafSubject: String
    public var leafIssuer: String
    public var notBefore: String
    public var notAfter: String
    public var resolvedAddress: String
    public var addressClass: AddressClass
    public var trustAnchorKind: String

    public init(
        leafSPKISha256: String,
        issuerSPKISha256: String,
        tlsVersion: String,
        cipherSuite: String,
        leafSubject: String,
        leafIssuer: String,
        notBefore: String,
        notAfter: String,
        resolvedAddress: String,
        addressClass: AddressClass,
        trustAnchorKind: String
    ) {
        self.leafSPKISha256 = leafSPKISha256
        self.issuerSPKISha256 = issuerSPKISha256
        self.tlsVersion = tlsVersion
        self.cipherSuite = cipherSuite
        self.leafSubject = leafSubject
        self.leafIssuer = leafIssuer
        self.notBefore = notBefore
        self.notAfter = notAfter
        self.resolvedAddress = resolvedAddress
        self.addressClass = addressClass
        self.trustAnchorKind = trustAnchorKind
    }

    public var groupedLeafFingerprint: String { Self.grouped(leafSPKISha256) }

    /// Grouped hex for VoiceOver / visual compare (R-31 part 2). One implementation, so a
    /// displayed pin and a displayed identity can never group differently.
    public static func grouped(_ spkiSha256: String) -> String {
        let compact = spkiSha256.replacingOccurrences(of: " ", with: "")
        var groups: [String] = []
        var i = compact.startIndex
        while i < compact.endIndex {
            let j = compact.index(i, offsetBy: 4, limitedBy: compact.endIndex) ?? compact.endIndex
            groups.append(String(compact[i..<j]))
            i = j
        }
        return groups.joined(separator: " ")
    }
}

public enum AddressClassifying {
    /// mDNS Home Assistant hosts are valid destinations; classification uses the resolved IP.
    public static func hostnameLooksLikeMDNS(_ host: String) -> Bool {
        host.lowercased().hasSuffix(".local") || host.lowercased().hasSuffix(".local.")
    }

    public static func classify(_ address: String) -> AddressClass {
        let parts = address.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return .unknown }
        if parts[0] == 127 { return .loopback }
        if parts[0] == 10 { return .privateRFC1918 }
        if parts[0] == 192, parts[1] == 168 { return .privateRFC1918 }
        if parts[0] == 172, parts[1] >= 16, parts[1] <= 31 { return .privateRFC1918 }
        if parts[0] == 169, parts[1] == 254 { return .linkLocal }
        return .publicUnicast
    }
}
