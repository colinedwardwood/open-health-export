// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import NetEgress
import Testing

@Test func sec15PrivateApprovalRejectsPublicRepointBeforeConnect() throws {
    let resolver = RecordingResolver(["203.0.113.44"])

    let failure = #expect(throws: StreamError.self) {
        _ = try ConnectTimeAddressGate.connectionAddress(
            host: "homeassistant.local",
            policy: .requireLocal,
            resolver: resolver
        )
    }

    #expect(
        failure == .addressClassViolation(
            host: "homeassistant.local",
            address: "203.0.113.44",
            addressClass: .publicUnicast
        )
    )
    #expect(failure?.localizedDescription.contains("stopped before sending data") == true)
    #expect(failure?.localizedDescription.contains("homeassistant.local") == false)
    #expect(resolver.calls == ["homeassistant.local"])
}

@Test func sec15MixedPrivateAndPublicAnswersFailClosed() {
    let resolver = RecordingResolver(["192.168.1.20", "198.51.100.8"])

    #expect(throws: StreamError.self) {
        _ = try ConnectTimeAddressGate.connectionAddress(
            host: "nas.local",
            policy: .requireLocal,
            resolver: resolver
        )
    }
}

@Test func sec15PrivateAnswerReturnsNumericConnectionTarget() throws {
    let resolver = RecordingResolver(["192.168.1.20"])
    let address = try ConnectTimeAddressGate.connectionAddress(
        host: "nas.local",
        policy: .requireLocal,
        resolver: resolver
    )
    #expect(address == "192.168.1.20")
}

@Test func sec15PlaintextEndpointsAreAlwaysLocalOnly() throws {
    let mqtt = try StreamEndpoint.parse(
        "mqtt://broker.example",
        allowedHosts: ["broker.example"],
        allowInsecure: true
    )
    let http = try StreamEndpoint.parse(
        "http://ha.example",
        allowedHosts: ["ha.example"],
        allowInsecure: true
    )
    #expect(mqtt.addressPolicy == .requireLocal)
    #expect(http.addressPolicy == .requireLocal)
}

@Test func sec15PublicTLSRemainsUnrestrictedAndDoesNotResolveInGate() throws {
    let endpoint = try StreamEndpoint.parse(
        "https://example.com",
        allowedHosts: ["example.com"]
    )
    let resolver = RecordingResolver(["203.0.113.10"])
    let host = try ConnectTimeAddressGate.connectionAddress(
        host: endpoint.host,
        policy: endpoint.addressPolicy,
        resolver: resolver
    )
    #expect(endpoint.addressPolicy == .unrestricted)
    #expect(host == "example.com")
    #expect(resolver.calls.isEmpty)
}

@Test func sec15PlainHTTPTransportRejectsBeforeReadingOrSendingPayload() async {
    let resolver = RecordingResolver(["203.0.113.44"])
    let transport = URLSessionHTTPTransport(resolver: resolver)
    let request = OutboundHTTPRequest(
        method: "POST",
        url: URL(string: "http://homeassistant.local/api")!,
        headers: [:],
        bodyFile: URL(fileURLWithPath: "/definitely-not-readable/sec15-payload")
    )

    let failure = await #expect(throws: StreamError.self) {
        _ = try await transport.execute(request)
    }
    #expect(
        failure == .addressClassViolation(
            host: "homeassistant.local",
            address: "203.0.113.44",
            addressClass: .publicUnicast
        )
    )
}

@Test func sec15PrivateHTTPSIsRecheckedWithoutChangingPublicHTTPS() async {
    let privateResolver = RecordingResolver(["198.51.100.22"])
    let privateTransport = URLSessionHTTPTransport(resolver: privateResolver)
    let missingBody = URL(fileURLWithPath: "/definitely-not-readable/sec15-payload")
    let privateRequest = OutboundHTTPRequest(
        method: "POST",
        url: URL(string: "https://collector.local/ingest")!,
        headers: [:],
        bodyFile: missingBody
    )
    let failure = await #expect(throws: StreamError.self) {
        _ = try await privateTransport.execute(privateRequest)
    }
    #expect(
        failure == .addressClassViolation(
            host: "collector.local",
            address: "198.51.100.22",
            addressClass: .publicUnicast
        )
    )

    let publicResolver = RecordingResolver(["203.0.113.10"])
    let publicTransport = URLSessionHTTPTransport(resolver: publicResolver)
    let publicRequest = OutboundHTTPRequest(
        method: "POST",
        url: URL(string: "https://example.com/ingest")!,
        headers: [:],
        bodyFile: missingBody
    )
    do {
        _ = try await publicTransport.execute(publicRequest)
        Issue.record("missing payload unexpectedly produced a response")
    } catch {
        // The missing body proves execution reached its normal path without a SEC-15 lookup.
    }
    #expect(publicResolver.calls.isEmpty)
}

@Test func addressClassificationCoversIPv6LocalAndPublicRanges() {
    #expect(AddressClassifying.classify("::1") == .loopback)
    #expect(AddressClassifying.classify("fd12:3456::1") == .privateRFC1918)
    #expect(AddressClassifying.classify("fe80::1") == .linkLocal)
    #expect(AddressClassifying.classify("2001:4860:4860::8888") == .publicUnicast)
}

private final class RecordingResolver: AddressResolver, @unchecked Sendable {
    private let lock = NSLock()
    private let answers: [String]
    private var recordedCalls: [String] = []

    init(_ answers: [String]) {
        self.answers = answers
    }

    var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    func resolve(host: String) throws -> [String] {
        lock.lock()
        recordedCalls.append(host)
        lock.unlock()
        return answers
    }
}
