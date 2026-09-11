// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import FileWriteKit
import Foundation
import NetEgress
import RequestTemplate
import WireFormat

public struct HTTPSSink: DestinationSink, Sendable {
    public var destination: HTTPSDestination
    public var transport: any HTTPTransport
    public var headerTemplates: [String: String]
    public var bodyTemplate: String?
    public var secrets: (any TemplateSecrets)?
    public var traceparent: TraceparentEmission?

    public init(
        destination: HTTPSDestination,
        transport: any HTTPTransport,
        headerTemplates: [String: String] = [:],
        bodyTemplate: String? = nil,
        secrets: (any TemplateSecrets)? = nil,
        traceparent: TraceparentEmission? = nil
    ) {
        self.destination = destination
        self.transport = transport
        self.headerTemplates = headerTemplates
        self.bodyTemplate = bodyTemplate
        self.secrets = secrets
        self.traceparent = traceparent
    }

    public func send(fileHandle: String, idempotencyKey: BatchID) async throws -> DeliveryReceipt {
        let payloadFile = URL(fileURLWithPath: fileHandle)
        let payloadText = String(decoding: try Data(contentsOf: payloadFile), as: UTF8.self)
        let recordCount = NativeWire.countRecords(in: payloadText)
        let context = TemplateContext(
            values: [
                "batchId": idempotencyKey.rawValue,
                "idempotencyKey": idempotencyKey.rawValue,
                "contentType": "application/x-ndjson; profile=\"ohe.wire/1\"",
                "recordCount": String(recordCount),
            ],
            payload: payloadText,
            secrets: secrets
        )
        var headers = [
            "Content-Type": "application/x-ndjson; profile=\"ohe.wire/1\"",
            "Idempotency-Key": idempotencyKey.rawValue,
        ]
        if let bearer = destination.authorizationBearer {
            try TemplateDirective.validateHeaderValue(bearer)
            headers["Authorization"] = "Bearer " + bearer
        }
        for (name, template) in headerTemplates {
            try HeaderName.validate(name)
            headers[name] = try RequestTemplate(template).renderHeaderValue(context: context)
        }
        var bodyFile = payloadFile
        if let bodyTemplate {
            let rendered = try RequestTemplate(bodyTemplate).render(context: context)
            let renderedURL = payloadFile.deletingLastPathComponent()
                .appendingPathComponent("\(idempotencyKey.rawValue).body")
            try FileWriteKit.writeAtomically(Data(rendered.utf8), to: renderedURL)
            bodyFile = renderedURL
        }
        let uncompressed = try Data(contentsOf: bodyFile)
        let gzipped = try Gzip.compress(uncompressed)
        let gzipURL = bodyFile.deletingLastPathComponent()
            .appendingPathComponent("\(idempotencyKey.rawValue).gz")
        try FileWriteKit.writeAtomically(gzipped, to: gzipURL)
        headers["Content-Encoding"] = "gzip"
        headers = Traceparent.stripForbidden(headers)
        let emitted = traceparent?.header(seed: idempotencyKey.rawValue)
        if let emitted {
            headers[Traceparent.headerName] = emitted
        }
        let response: OutboundHTTPResponse
        var autoDisabled = false
        do {
            response = try await execute(headers: headers, bodyFile: gzipURL)
        } catch {
            guard emitted != nil, Traceparent.isHeaderPlausibleFailure(error) else {
                throw error
            }
            let retryHeaders = Traceparent.stripForbidden(headers)
            response = try await execute(headers: retryHeaders, bodyFile: gzipURL)
            traceparent?.noteAutoDisabled()
            autoDisabled = true
        }
        if let accepted = parseAccepted(response.body) {
            return DeliveryReceipt(
                batchID: idempotencyKey,
                accepted: accepted,
                statusOnly: false,
                traceparentAutoDisabled: autoDisabled
            )
        }
        return DeliveryReceipt(
            batchID: idempotencyKey,
            accepted: recordCount,
            statusOnly: true,
            traceparentAutoDisabled: autoDisabled
        )
    }

    private func execute(
        headers: [String: String],
        bodyFile: URL
    ) async throws -> OutboundHTTPResponse {
        let request = OutboundHTTPRequest(
            method: "POST",
            url: destination.url,
            headers: headers,
            bodyFile: bodyFile
        )
        let response = try await transport.execute(request)
        guard (200..<300).contains(response.status) else {
            if let seconds = HTTPRetryAfter.parseDelta(response.header("Retry-After")) {
                throw EgressError.httpRetryAfter(status: response.status, seconds: seconds)
            }
            throw EgressError.httpStatus(response.status)
        }
        return response
    }
}

private func parseAccepted(_ body: Data) -> Int? {
    guard let text = String(data: body, encoding: .utf8) else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }
    guard let obj = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] else {
        return nil
    }
    if let value = obj["accepted"] as? Int {
        return value
    }
    if let value = obj["accepted"] as? NSNumber {
        return value.intValue
    }
    return nil
}
