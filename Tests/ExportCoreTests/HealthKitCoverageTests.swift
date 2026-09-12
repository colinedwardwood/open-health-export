// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import MetricCatalog
import Testing

private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func loadJSON(_ relative: String) throws -> [String: Any] {
    let data = try Data(contentsOf: repoRoot().appendingPathComponent(relative))
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CoverageFixtureError.malformed
    }
    return object
}

private enum CoverageFixtureError: Error {
    case malformed
}

@Test func hk03CatalogueAndExclusionsCoverThePinnedSDKIdentifiers() throws {
    let sdkObject = try loadJSON("qa/healthkit-sdk-identifiers.json")
    let exclusionObject = try loadJSON("qa/healthkit-coverage-exclusions.json")
    let sdk = Set(sdkObject["identifiers"] as? [String] ?? [])
    let exclusions = (exclusionObject["exclusions"] as? [[String: String]] ?? []).compactMap {
        $0["identifier"]
    }
    let reasons = (exclusionObject["exclusions"] as? [[String: String]] ?? []).compactMap {
        $0["reason"]
    }
    let catalog = HealthKitCoverage.catalogIdentifiers()
    let excluded = Set(exclusions)
    #expect(!sdk.isEmpty)
    #expect(sdk == catalog.union(excluded))
    #expect(HealthKitCoverage.uncovered(sdk: sdk, catalog: catalog, excluded: excluded).isEmpty)
    #expect(HealthKitCoverage.overlap(catalog: catalog, excluded: excluded).isEmpty)
    #expect(reasons.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    #expect(Set(exclusions).count == exclusions.count)
    #expect(Set(catalog).count == catalog.count)
}

@Test func hk03HeaderParserExtractsQuantityAndWorkoutIdentifiers() {
    let header = """
    HK_EXTERN HKQuantityTypeIdentifier const HKQuantityTypeIdentifierHeartRate API_AVAILABLE(ios(8.0));
    HK_EXTERN NSString * const HKWorkoutTypeIdentifier API_AVAILABLE(ios(8.0));
    """
    #expect(
        HealthKitCoverage.identifiers(fromHeader: header)
            == ["HKQuantityTypeIdentifierHeartRate", "HKWorkoutTypeIdentifier"]
    )
}
