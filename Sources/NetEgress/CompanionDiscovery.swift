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
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let names = results.compactMap { result -> String? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return name
            }
            Task { await self?.record(names: names) }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func record(names: [String]) {
        seen.formUnion(names)
        guard !seen.isEmpty else { return }
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
            waiter.resume(returning: names)
        }
    }
}
#endif
