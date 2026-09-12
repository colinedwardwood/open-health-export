// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(HealthKit)
@preconcurrency import HealthKit
import Foundation
import MetricCatalog
import Testing

private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

@Test func hk03LiveSDKHeaderMatchesTheCommittedIdentifierPin() throws {
    let sdkRoot = try sdkPath()
    let header = sdkRoot
        .appendingPathComponent("System/Library/Frameworks/HealthKit.framework/Headers/HKTypeIdentifiers.h")
    let live = Set(HealthKitCoverage.identifiers(fromHeader: try String(contentsOf: header, encoding: .utf8)))
    let data = try Data(
        contentsOf: repoRoot().appendingPathComponent("qa/healthkit-sdk-identifiers.json")
    )
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let pinned = Set(object?["identifiers"] as? [String] ?? [])
    #expect(live == pinned, "SDK identifiers drifted; refresh qa/healthkit-sdk-identifiers.json and exclusions")
}

@Test func hk03CatalogueQuantityTypesHaveLegalAggregationStyles() throws {
    for declaration in MetricCatalog.selectable
        where declaration.hkIdentifier.hasPrefix("HKQuantityTypeIdentifier")
    {
        let identifier = HKQuantityTypeIdentifier(rawValue: declaration.hkIdentifier)
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            Issue.record("SDK rejected catalogue identifier \(declaration.hkIdentifier)")
            continue
        }
        if declaration.cumulative {
            #expect(
                type.aggregationStyle == .cumulative,
                "\(declaration.hkIdentifier) is cumulative in the catalogue"
            )
        } else {
            #expect(
                type.aggregationStyle != .cumulative,
                "\(declaration.hkIdentifier) is discrete in the catalogue"
            )
        }
    }
}

private func sdkPath() throws -> URL {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["--sdk", "macosx", "--show-sdk-path"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CocoaError(.fileReadUnknown)
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let path = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return URL(fileURLWithPath: path)
}
#endif
