// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(Network)
import Foundation
import Network

/// Finds the paired Mac companion on the local network. Discovery is not authorization: the
/// browser reports names, and only a name equal to the one captured at pairing may be dialled.
public actor CompanionDiscovery {
    private let queue = DispatchQueue(label: "app.openhealthexporter.discovery")
    private var browser: NWBrowser?
    private var waiters: [CheckedContinuation<[String], Error>] = []
    private var seen: Set<String> = []
    /// R-21: set when the browser reports the Local Network grant is off. Without this a
    /// denial is indistinguishable from an empty network and reports `serviceNotFound`,
    /// which tells the user to wake a Mac that was never the problem.
    private var denial: StreamError?

    public init() {}

    /// Names currently advertising `_ohx-recv._tcp`, or an empty list when the window elapses.
    public func browse(for duration: Duration = .seconds(3)) async throws -> [String] {
        start()
        let names = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
            waiters.append(continuation)
            armWindow(duration)
        }
        return names.sorted()
    }

    public func find(pairedName: String, for duration: Duration = .seconds(3)) async throws -> BonjourService {
        let candidates = try await browse(for: duration)
        guard let matched = BonjourService.match(candidates: candidates, pairedName: pairedName) else {
            throw StreamError.serviceNotFound
        }
        return try BonjourService(name: matched)
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }

    private func start() {
        guard browser == nil else { return }
        EgressAttemptLog.record(kind: .discovery, host: BonjourService.companionType)
        let descriptor = NWBrowser.Descriptor.bonjour(type: BonjourService.companionType, domain: nil)
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: descriptor, using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let names = results.compactMap { result -> String? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return name
            }
            Task { await self?.record(names: names) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            // A denied grant surfaces here, not as an empty result set. Browsing always
            // needs the grant, so the DNS policy error is conclusive on its own.
            let error: NWError?
            switch state {
            case .failed(let failure): error = failure
            case .waiting(let failure): error = failure
            default: error = nil
            }
            guard let error, LocalNetworkDenial.isDenial(error, needsLocalGrant: true) else { return }
            Task { await self?.recordDenial() }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func record(names: [String]) {
        seen.formUnion(names)
        guard !seen.isEmpty else { return }
        deliver()
    }

    /// Delivered without waiting out the browse window: once the grant is known to be off,
    /// nothing can arrive and holding the user on a spinner adds no information.
    private func recordDenial() {
        denial = .localNetworkDenied
        deliver()
    }

    private func armWindow(_ duration: Duration) {
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            await self?.deliver()
        }
    }

    private func deliver() {
        guard !waiters.isEmpty else { return }
        let names = Array(seen)
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            if let denial {
                waiter.resume(throwing: denial)
            } else {
                waiter.resume(returning: names)
            }
        }
    }
}
#endif
