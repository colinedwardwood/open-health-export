// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain

public enum RedactionSink: String, Sendable, Hashable, CaseIterable {
    case journal
    case ui
    case bundle
    case otlp
    case notification
    case widget
}

public struct FieldPermission: Sendable, Equatable {
    public var key: String
    public var sinks: Set<RedactionSink>
    public var healthDerived: Bool

    public init(key: String, sinks: Set<RedactionSink>, healthDerived: Bool) {
        self.key = key
        self.sinks = sinks
        self.healthDerived = healthDerived
    }
}

public enum Allowlist {
    public static let manifest: [FieldPermission] = [
        FieldPermission(key: "runID", sinks: [.journal, .ui, .bundle], healthDerived: false),
        FieldPermission(key: "outcome", sinks: [.journal, .ui, .bundle, .otlp], healthDerived: false),
        FieldPermission(key: "trigger", sinks: [.journal, .ui, .bundle, .otlp], healthDerived: false),
        FieldPermission(key: "samplesRead", sinks: [.journal, .ui, .bundle], healthDerived: true),
        FieldPermission(key: "samplesCommitted", sinks: [.journal, .ui, .bundle], healthDerived: true),
        FieldPermission(key: "samplesAcked", sinks: [.journal, .ui, .bundle], healthDerived: true),
        FieldPermission(key: "metric", sinks: [.journal, .ui], healthDerived: true),
        FieldPermission(key: "count", sinks: [.journal, .ui], healthDerived: true),
        FieldPermission(key: "errorClass", sinks: [.journal, .ui, .bundle], healthDerived: false),
        FieldPermission(key: "destinationID", sinks: [.journal, .ui], healthDerived: false),
        FieldPermission(key: "windowStartDay", sinks: [.journal, .ui], healthDerived: true),
        FieldPermission(key: "windowEndDay", sinks: [.journal, .ui], healthDerived: true),
        FieldPermission(key: "byteCount", sinks: [.journal, .ui, .bundle], healthDerived: true),
        FieldPermission(key: "durationMillis", sinks: [.journal, .ui, .bundle], healthDerived: false),
        FieldPermission(key: "payloadSHA256", sinks: [.journal, .ui, .bundle], healthDerived: false),
    ]

    public static var journalFields: Set<String> {
        Set(manifest.filter { $0.sinks.contains(.journal) }.map(\.key))
    }

    public static func permitted(_ field: String) -> Bool {
        permitted(field, in: .journal)
    }

    public static func permitted(_ field: String, in sink: RedactionSink) -> Bool {
        manifest.contains { $0.key == field && $0.sinks.contains(sink) }
    }
}
