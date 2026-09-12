// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HK-18: iOS export payloads use a background `URLSession` so the transfer can
/// finish after suspension. ADR-R5 splits first attempts from discretionary retries.
public enum HTTPBackgroundSession {
    public static let immediateIdentifier = "app.openhealthexporter.https.immediate"
    public static let retryIdentifier = "app.openhealthexporter.https.retry"

    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var sessions: [String: URLSession] = [:]
        var completionHandlers: [String: @Sendable () -> Void] = [:]
        var pins: [String: PinRecord] = [:]
    }

    private static let storage = Storage()

    public static func identifier(for schedule: HTTPTransferSchedule) -> String {
        switch schedule {
        case .immediate: immediateIdentifier
        case .discretionaryRetry: retryIdentifier
        }
    }

    static func storePin(_ pin: PinRecord, host: String) {
        storage.lock.lock()
        storage.pins[host.lowercased()] = pin
        storage.lock.unlock()
    }

    static func pin(for host: String) -> PinRecord? {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.pins[host.lowercased()]
    }

    static func payloadSession(
        schedule: HTTPTransferSchedule,
        pin: PinRecord?,
        resolver: any AddressResolver
    ) -> URLSession {
        let identifier = identifier(for: schedule)
        #if os(iOS)
        storage.lock.lock()
        if let existing = storage.sessions[identifier] {
            storage.lock.unlock()
            return existing
        }
        let delegate = HTTPSessionDelegate(pin: pin, resolver: resolver)
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.isDiscretionary = schedule == .discretionaryRetry
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        storage.sessions[identifier] = session
        storage.lock.unlock()
        return session
        #else
        _ = identifier
        let delegate = HTTPSessionDelegate(pin: pin, resolver: resolver)
        return URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
        #endif
    }

    public static func finishEvents(
        for identifier: String,
        completionHandler: @escaping @Sendable () -> Void
    ) {
        storage.lock.lock()
        storage.completionHandlers[identifier] = completionHandler
        storage.lock.unlock()
    }

    static func completeEvents(for session: URLSession) {
        let identifier = session.configuration.identifier ?? ""
        storage.lock.lock()
        let handler = storage.completionHandlers.removeValue(forKey: identifier)
        storage.lock.unlock()
        guard let handler else { return }
        DispatchQueue.main.async(execute: handler)
    }
}
