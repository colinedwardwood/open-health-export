// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The address class approved for a destination. `.requireLocal` is deliberately stricter
/// than "not public": an unclassified result also fails closed.
public enum ConnectTimeAddressPolicy: Sendable, Equatable {
    case unrestricted
    case requireLocal
}

public protocol AddressResolver: Sendable {
    func resolve(host: String) throws -> [String]
}

public struct SystemAddressResolver: AddressResolver {
    public init() {}

    public func resolve(host: String) throws -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        #if os(Linux)
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #else
        hints.ai_socktype = SOCK_STREAM
        #endif
        var info: UnsafeMutablePointer<addrinfo>?
        let status = host.withCString { getaddrinfo($0, nil, &hints, &info) }
        guard status == 0, let info else {
            throw StreamError.transport("getaddrinfo")
        }
        defer { freeaddrinfo(info) }

        var addresses: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = info
        while let current = cursor {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                current.pointee.ai_addr,
                current.pointee.ai_addrlen,
                &buffer,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let address = String(cString: buffer)
                    .split(separator: "%", maxSplits: 1)
                    .first
                    .map(String.init) ?? ""
                if !address.isEmpty, !addresses.contains(address) {
                    addresses.append(address)
                }
            }
            cursor = current.pointee.ai_next
        }
        guard !addresses.isEmpty else {
            throw StreamError.transport("getaddrinfo returned no addresses")
        }
        return addresses
    }
}

public enum ConnectTimeAddressGate {
    /// Resolves immediately before connection and returns a numeric address. Returning a
    /// numeric address is important: the connector must not perform a second DNS lookup.
    public static func connectionAddress(
        host: String,
        policy: ConnectTimeAddressPolicy,
        resolver: any AddressResolver
    ) throws -> String {
        guard policy == .requireLocal else { return host }
        let addresses = try resolver.resolve(host: host)
        guard !addresses.isEmpty else {
            throw StreamError.addressClassViolation(
                host: host,
                address: "",
                addressClass: .unknown
            )
        }
        for address in addresses {
            let addressClass = AddressClassifying.classify(address)
            guard addressClass == .loopback
                    || addressClass == .privateRFC1918
                    || addressClass == .linkLocal
            else {
                throw StreamError.addressClassViolation(
                    host: host,
                    address: address,
                    addressClass: addressClass
                )
            }
        }
        return addresses[0]
    }
}
