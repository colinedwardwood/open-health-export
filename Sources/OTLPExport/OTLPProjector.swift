// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation
import Redaction
import WireFormat

/// Journal → OTLP/HTTP protobuf projection (R-53). No span objects on the export hot path.
public enum OTLPProjector {
    public static let spanName = "export.run"
    public static let serviceName = "open-health-exporter"

    public static func traces(events: [RunEvent]) -> Data {
        var spans = Data()
        for event in events {
            spans.append(ProtoWriter.field(2, bytes: span(event)))
        }
        let scopeSpans = ProtoWriter.field(2, bytes: spans)
        let resource = ProtoWriter.field(
            1,
            bytes: ProtoWriter.field(1, bytes: stringAttribute("service.name", serviceName))
        )
        let resourceSpans = resource + scopeSpans
        return ProtoWriter.field(1, bytes: resourceSpans)
    }

    public static func attributeKeys(in payload: Data) -> Set<String> {
        var keys: Set<String> = []
        let text = String(decoding: payload, as: UTF8.self)
        if text.contains("service.name") { keys.insert("service.name") }
        if text.contains("outcome") { keys.insert("outcome") }
        if text.contains("trigger") { keys.insert("trigger") }
        if text.contains(OTLPMetricsProjector.destinationIDAttribute) {
            keys.insert(OTLPMetricsProjector.destinationIDAttribute)
        }
        return keys
    }

    static func span(_ event: RunEvent) -> Data {
        let digest = ContentSHA256.bytes(Data(event.runID.rawValue.utf8))
        let traceID = Data(digest.prefix(16))
        let spanID = Data(digest.suffix(8))
        let startNano = UInt64(max(0, event.wallTimeEpoch) * 1_000_000_000)
        var body = Data()
        body.append(ProtoWriter.field(1, bytes: traceID))
        body.append(ProtoWriter.field(2, bytes: spanID))
        body.append(ProtoWriter.field(5, string: spanName))
        body.append(ProtoWriter.fieldFixed64(7, value: startNano))
        body.append(ProtoWriter.fieldFixed64(8, value: startNano))
        if Allowlist.permitted("outcome", in: .otlp) {
            body.append(ProtoWriter.field(9, bytes: stringAttribute("outcome", event.outcomeKind)))
        }
        if Allowlist.permitted("trigger", in: .otlp) {
            body.append(ProtoWriter.field(9, bytes: stringAttribute("trigger", event.trigger.rawValue)))
        }
        return body
    }

    static func stringAttribute(_ key: String, _ value: String) -> Data {
        let any = ProtoWriter.field(1, string: value)
        return ProtoWriter.field(1, string: key) + ProtoWriter.field(2, bytes: any)
    }
}
