// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import DestinationTrust
import Foundation
import Testing

@Test func newDestinationScopeIsFailClosed() throws {
    let scope = try DestinationExportScope(destinationID: "https")
    #expect(scope.metrics.isEmpty)
    #expect(scope.startInclusive == nil)
    #expect(!scope.isConfigured)
    #expect(
        !scope.allows(
            metric: MetricID(rawValue: "heart_rate"),
            sampleStart: Date(timeIntervalSince1970: 10)
        )
    )
}

@Test func destinationScopeRequiresBothTypeAndDateRange() throws {
    let heart = MetricID(rawValue: "heart_rate")
    let steps = MetricID(rawValue: "step_count")
    let scope = try DestinationExportScope(
        destinationID: "mqtt",
        metrics: [heart],
        startInclusive: Date(timeIntervalSince1970: 100),
        endExclusive: Date(timeIntervalSince1970: 200)
    )

    #expect(scope.isConfigured)
    #expect(!scope.allows(metric: steps, sampleStart: Date(timeIntervalSince1970: 150)))
    #expect(!scope.allows(metric: heart, sampleStart: Date(timeIntervalSince1970: 99)))
    #expect(scope.allows(metric: heart, sampleStart: Date(timeIntervalSince1970: 100)))
    #expect(scope.allows(metric: heart, sampleStart: Date(timeIntervalSince1970: 199)))
    #expect(!scope.allows(metric: heart, sampleStart: Date(timeIntervalSince1970: 200)))
}

@Test func destinationScopeRejectsEmptyOrReversedDateIntervals() {
    #expect(throws: DestinationScopeError.invalidDateRange) {
        _ = try DestinationExportScope(
            destinationID: "https",
            startInclusive: Date(timeIntervalSince1970: 200),
            endExclusive: Date(timeIntervalSince1970: 200)
        )
    }
    #expect(throws: DestinationScopeError.invalidDateRange) {
        _ = try DestinationExportScope(
            destinationID: "https",
            startInclusive: Date(timeIntervalSince1970: 201),
            endExclusive: Date(timeIntervalSince1970: 200)
        )
    }
}

@Test func destinationScopeDocumentRoundTripsDeterministically() throws {
    let scope = try DestinationExportScope(
        destinationID: "https",
        metrics: [MetricID(rawValue: "heart_rate")],
        startInclusive: Date(timeIntervalSince1970: 100)
    )
    var document = DestinationScopeDocument()
    document.set(scope)

    let first = try document.encoded()
    let second = try DestinationScopeDocument.decoded(first).encoded()
    #expect(first == second)
    #expect(try DestinationScopeDocument.decoded(first).scope(for: "https") == scope)
    #expect(try DestinationScopeDocument.decoded(first).scope(for: "new").metrics.isEmpty)
}

@Test func destinationScopeEncodingSortsMetricsIndependentlyOfSetIterationOrder() throws {
    let ascending = [
        MetricID(rawValue: "heart_rate"),
        MetricID(rawValue: "sleep_analysis"),
        MetricID(rawValue: "step_count"),
    ]
    let first = try DestinationScopeDocument(
        scopes: [
            "https": DestinationExportScope(
                destinationID: "https",
                metrics: Set(ascending),
                startInclusive: Date(timeIntervalSince1970: 100)
            ),
        ]
    ).encoded()
    let second = try DestinationScopeDocument(
        scopes: [
            "https": DestinationExportScope(
                destinationID: "https",
                metrics: Set(ascending.reversed()),
                startInclusive: Date(timeIntervalSince1970: 100)
            ),
        ]
    ).encoded()

    #expect(first == second)
    #expect(String(decoding: first, as: UTF8.self).contains(
        #""metrics":["heart_rate","sleep_analysis","step_count"]"#
    ))
}
