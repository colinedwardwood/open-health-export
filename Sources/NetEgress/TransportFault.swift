// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation

#if canImport(Network)
import Network
#endif

/// R-21 / TA-01: tells a revoked Local Network grant apart from a Mac that is simply not
/// there. The two produce the same silence at the socket and carry opposite instructions —
/// "allow Local Network in Settings" versus "wake the Mac and check the network" — so
/// guessing between them is the dishonesty FIX-A07 names.
public enum LocalNetworkDenial {
    /// mDNS refuses a browse under a denied grant with a policy error rather than an empty
    /// result set. Values from `dns_sd.h`; `NWError.dns` carries the raw code.
    static let policyDenied: Int32 = -65570 // kDNSServiceErr_PolicyDenied
    static let notPermitted: Int32 = -65571 // kDNSServiceErr_NotPermitted

    /// `EPERM` is a denial verdict only on a dial that needs the grant in the first place.
    /// The same code on public unicast means something else, so the caller has to say
    /// whether this endpoint is local — we do not infer it from the error alone.
    public static func isDenial(dnsCode: Int32) -> Bool {
        dnsCode == policyDenied || dnsCode == notPermitted
    }

    #if canImport(Network)
    public static func isDenial(_ error: NWError, needsLocalGrant: Bool) -> Bool {
        switch error {
        case .dns(let code):
            // Browsing and resolving `.local` always needs the grant, whatever the target.
            return isDenial(dnsCode: code)
        case .posix(let code):
            return needsLocalGrant && code == .EPERM
        default:
            return false
        }
    }
    #endif
}

/// Normalizes a transport failure onto a closed `DestinationSendError` so `ExportRun` and
/// `DeliveryExecutor` record a real outcome. Without this every non-`DestinationSendError`
/// reaches `DeliveryExecutor` as `.transientNetwork` and gets retried, which is the wrong
/// answer for a permission the user has to change in Settings.
public enum TransportFault {
    /// `nil` means the error already owns a dedicated path that must not be flattened into a
    /// send failure: a pin mismatch is an R-31/R-40 trust event and an address-class
    /// violation is a SEC-15 stop. Both are worse than unreachable and are handled elsewhere.
    public static func normalize(_ error: Error) -> DestinationSendError? {
        if let closed = error as? DestinationSendError {
            return closed
        }
        if let stream = error as? StreamError {
            switch stream {
            case .localNetworkDenied:
                return .localNetworkDenied
            case .serviceNotFound, .closedByPeer, .connectTimeout, .readTimeout, .notOpen, .transport:
                return .destinationUnreachable
            case .badPort, .badServiceName, .badPreSharedKey, .unsupportedPlatform:
                // Misconfiguration we produced, not a network verdict; never retried as one.
                return .internalFault(String(describing: stream))
            case .pinMismatch, .addressClassViolation:
                return nil
            }
        }
        if let egress = error as? EgressError {
            switch egress {
            case .transport:
                return .destinationUnreachable
            case .invalidURL, .credentialsInURL, .forbiddenScheme, .insecureHTTP,
                 .notAllowlisted, .notHTTP:
                return .internalFault(String(describing: egress))
            case .httpStatus, .httpRetryAfter, .pinMismatch:
                // A response from a reached peer, Retry-After (whose delay must survive),
                // and trust failures all own dedicated paths.
                return nil
            }
        }
        if let url = error as? URLError {
            switch url.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                 .dnsLookupFailed, .notConnectedToInternet, .internationalRoamingOff,
                 .callIsActive, .dataNotAllowed, .resourceUnavailable:
                return .destinationUnreachable
            default:
                // Cancellation and TLS policy failures need more context than URLError
                // carries here; keep their existing dedicated/raw paths.
                return nil
            }
        }
        return nil
    }

    /// Runs `body` and rethrows any transport failure as its closed equivalent, leaving the
    /// errors that own a dedicated path untouched.
    public static func normalizing<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            throw normalize(error) ?? error
        }
    }
}
