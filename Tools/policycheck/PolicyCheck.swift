// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import MetricCatalog
import WireFormat

@main
struct PolicyCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if CommandLine.arguments.dropFirst() == ["--string-catalog"] {
            try checkStringCatalog(root: root)
            return
        }
        let sources = root.appendingPathComponent("Sources")
        let forbidden = ["import HealthKit", "import UIKit", "import WidgetKit"]
        let allowedHealthKit = Set(["HealthKitSource"])
        let networkTokens = ["URLSession", "NWConnection", "NWListener", "NWBrowser"]
        let allowedNetwork = Set(["NetEgress"])
        let platformSecurity = "import Security"
        var violations: [String] = []
        guard let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            FileHandle.standardError.write(Data("no Sources/\n".utf8))
            exit(1)
        }
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let target = file.path.split(separator: "/").drop(while: { $0 != "Sources" }).dropFirst().first.map(String.init) ?? ""
            for token in forbidden {
                if text.contains(token) {
                    if token == "import HealthKit", allowedHealthKit.contains(target) { continue }
                    violations.append("\(file.path): \(token)")
                }
            }
            for token in networkTokens {
                if text.contains(token), !allowedNetwork.contains(target) {
                    violations.append("\(file.path): \(token)")
                }
            }
            if text.contains("import Logging") {
                violations.append("\(file.path): import Logging")
            }
            if (text.contains("Logger(") || text.contains("os_log(")),
               target != "Redaction" {
                violations.append("\(file.path): OBS-29 logging outside Redaction")
            }
            if text.contains("privacy: .public"),
               file.lastPathComponent != "OHELog.swift" {
                violations.append("\(file.path): OBS-29 unreviewed public log value")
            }
            if text.contains(platformSecurity), !allowedNetwork.contains(target) {
                violations.append("\(file.path): \(platformSecurity)")
            }
            for token in ["UIPasteboard", "NSPasteboard"] where text.contains(token) {
                violations.append("\(file.path): SEC-44 prohibited \(token)")
            }
        }
        if !violations.isEmpty {
            FileHandle.standardError.write(Data((violations.joined(separator: "\n") + "\n").utf8))
            exit(1)
        }
        print("policycheck imports: ok")
        // R-34/R-37/R-52: app targets use reviewed NetEgress adapters, never direct sockets.
        let apps = root.appendingPathComponent("Apps")
        var appNetworkBypasses: [String] = []
        var pasteboardBypasses: [String] = []
        var loggingBypasses: [String] = []
        if let appFiles = FileManager.default.enumerator(at: apps, includingPropertiesForKeys: nil) {
            for case let file as URL in appFiles where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                let sanitized = text.replacingOccurrences(
                    of: "handleEventsForBackgroundURLSession",
                    with: ""
                )
                for token in ["URLSession", "NWConnection", "NWListener", "NWBrowser"]
                    where sanitized.contains(token) {
                    appNetworkBypasses.append("\(file.path): \(token)")
                }
                for token in ["UIPasteboard", "NSPasteboard"] where text.contains(token) {
                    pasteboardBypasses.append("\(file.path): \(token)")
                }
                for token in ["import Logging", "Logger(", "os_log(", "privacy: .public"]
                    where text.contains(token) {
                    loggingBypasses.append("\(file.path): \(token)")
                }
            }
        }
        if !appNetworkBypasses.isEmpty {
            FileHandle.standardError.write(
                Data((appNetworkBypasses.joined(separator: "\n") + "\n").utf8)
            )
            exit(1)
        }
        print("policycheck app targets use no direct network APIs: ok")
        if !pasteboardBypasses.isEmpty {
            FileHandle.standardError.write(
                Data(
                    (
                        "SEC-44: general pasteboard use requires an approved local-only, expiring wrapper:\n"
                            + pasteboardBypasses.joined(separator: "\n")
                            + "\n"
                    ).utf8
                )
            )
            exit(1)
        }
        print("policycheck general pasteboard use is prohibited: ok")
        if !loggingBypasses.isEmpty {
            FileHandle.standardError.write(
                Data(
                    (
                        "OBS-29: app logging must use the reviewed OHELog boundary:\n"
                            + loggingBypasses.joined(separator: "\n")
                            + "\n"
                    ).utf8
                )
            )
            exit(1)
        }
        print("policycheck app logging uses the privacy-reviewed boundary: ok")

        var privateDataPreferences: [String] = []
        if let appFiles = FileManager.default.enumerator(
            at: apps,
            includingPropertiesForKeys: nil
        ) {
            for case let file as URL in appFiles where file.pathExtension == "plist" {
                let text = try String(contentsOf: file, encoding: .utf8)
                if text.contains("Enable-Private-Data") {
                    privateDataPreferences.append(file.path)
                }
            }
        }
        if !privateDataPreferences.isEmpty {
            FileHandle.standardError.write(
                Data(
                    (
                        "OBS-29: release app plists enable private OSLog data:\n"
                            + privateDataPreferences.joined(separator: "\n")
                            + "\n"
                    ).utf8
                )
            )
            exit(1)
        }
        print("policycheck release plists never enable private OSLog data: ok")

        let projectText = try String(
            contentsOf: root.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        let uiTestPath = root.appendingPathComponent(
            "Tests/ExporterUITests/ExporterUITests.swift"
        )
        guard projectText.contains("ExporteriOSUITests:"),
              projectText.contains("- ExporteriOSUITests"),
              FileManager.default.fileExists(atPath: uiTestPath.path)
        else {
            FileHandle.standardError.write(Data("iOS XCUITest target or suite is missing\n".utf8))
            exit(1)
        }
        print("policycheck iOS XCUITest target is wired: ok")
        let shortcutIntent = try String(
            contentsOf: root.appendingPathComponent(
                "Apps/Exporter-iOS/LastSuccessfulExportIntent.swift"
            ),
            encoding: .utf8
        )
        if !shortcutIntent.contains("struct ExportOnePageIntent")
            || !shortcutIntent.contains("trigger: .shortcut")
        {
            FileHandle.standardError.write(
                Data("R-68 export App Intent must run with RunTrigger.shortcut\n".utf8)
            )
            exit(1)
        }
        print("policycheck shortcut export intent uses RunTrigger.shortcut: ok")

        // QA-21: Swift Testing owns unit and integration tests. XCTest stays for UI
        // automation (and, if they appear, XCTMetric / ObjC exception targets).
        var xctestOutsideUI: [String] = []
        let testsRoot = root.appendingPathComponent("Tests")
        if let testFiles = FileManager.default.enumerator(
            at: testsRoot,
            includingPropertiesForKeys: nil
        ) {
            for case let file as URL in testFiles where file.pathExtension == "swift" {
                let relative = file.path.replacingOccurrences(of: testsRoot.path + "/", with: "")
                if relative.hasPrefix("ExporterUITests/") { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                if text.contains(": XCTestCase") {
                    xctestOutsideUI.append(relative)
                }
            }
        }
        if !xctestOutsideUI.isEmpty {
            FileHandle.standardError.write(
                Data(
                    (
                        "QA-21: XCTestCase belongs in UI or performance targets, not "
                            + xctestOutsideUI.joined(separator: ", ")
                            + "\n"
                    ).utf8
                )
            )
            exit(1)
        }
        print("policycheck XCTest stays in UI automation: ok")

        let exporterEntitlements = apps
            .appendingPathComponent("Exporter-iOS/Exporter.entitlements")
        let entitlementText = try String(contentsOf: exporterEntitlements, encoding: .utf8)
        guard entitlementText.contains(
            "<key>com.apple.developer.healthkit.background-delivery</key>"
        ) else {
            FileHandle.standardError.write(
                Data("HealthKit observer is missing background-delivery entitlement\n".utf8)
            )
            exit(1)
        }
        print("policycheck HealthKit background delivery entitlement: ok")

        let exporterInfo = apps.appendingPathComponent("Exporter-iOS/Info.plist")
        let exporterInfoText = try String(contentsOf: exporterInfo, encoding: .utf8)
        for required in [
            "BGTaskSchedulerPermittedIdentifiers",
            "app.openhealthexporter.refresh",
            "app.openhealthexporter.processing",
            "app.openhealthexporter.backfill",
        ] where !exporterInfoText.contains(required) {
            FileHandle.standardError.write(
                Data("iOS background task configuration is missing \(required)\n".utf8)
            )
            exit(1)
        }
        print("policycheck iOS background task identifiers: ok")
        let harnessExport = try String(
            contentsOf: apps.appendingPathComponent("Exporter-iOS/HarnessExport.swift"),
            encoding: .utf8
        )
        let sqliteStore = try String(
            contentsOf: sources.appendingPathComponent("StorageSQLite/SQLiteStateStore.swift"),
            encoding: .utf8
        )
        guard harnessExport.contains(
            ".protectionKey: FileProtectionType.completeUntilFirstUserAuthentication"
        ),
            harnessExport.contains("try fm.setAttributes("),
            harnessExport.contains("FileProtectionType.completeUnlessOpen"),
            harnessExport.contains("protectedPayloadDirectory(named:"),
            sqliteStore.contains(
                "SQLITE_OPEN_FILEPROTECTION_COMPLETEUNTILFIRSTUSERAUTHENTICATION"
            ),
            !harnessExport.contains(".protectionKey: FileProtectionType.none")
        else {
            FileHandle.standardError.write(
                Data("SEC-32: managed storage lost its Data Protection floor\n".utf8)
            )
            exit(1)
        }
        print("policycheck managed storage Data Protection floor: ok")
        var healthOnMac: [String] = []
        if let appFiles = FileManager.default.enumerator(at: apps, includingPropertiesForKeys: nil) {
            for case let file as URL in appFiles where file.pathExtension == "swift" {
                let path = file.path
                guard path.contains("Companion-macOS") else { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                if text.contains("HealthKit") || text.contains("HealthKitSource") {
                    healthOnMac.append(path)
                }
            }
        }
        if !healthOnMac.isEmpty {
            FileHandle.standardError.write(Data((healthOnMac.joined(separator: "\n") + "\n").utf8))
            exit(1)
        }
        print("policycheck Mac companion has no HealthKit: ok")
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        guard let product = manifest.range(of: ".library(name: \"ExportCore\"") else {
            FileHandle.standardError.write(Data("ExportCore product missing\n".utf8))
            exit(1)
        }
        let fromProduct = manifest[product.lowerBound...]
        guard let end = fromProduct.range(of: "]),") else {
            FileHandle.standardError.write(Data("ExportCore product unclosed\n".utf8))
            exit(1)
        }
        let block = fromProduct[fromProduct.startIndex..<end.upperBound]
        if block.contains("MQTTCodec") || block.contains("SinkMQTT") {
            FileHandle.standardError.write(Data("MQTT must not enter ExportCore (ADR-0003)\n".utf8))
            exit(1)
        }
        print("policycheck ExportCore quarantine: ok")
        let compactManifest = manifest.filter { !$0.isWhitespace }
        if compactManifest.contains(".package(url:") || compactManifest.contains(".binaryTarget(") {
            FileHandle.standardError.write(
                Data("third-party package or binary target requires R-36 review\n".utf8)
            )
            exit(1)
        }
        print("policycheck no third-party runtime package: ok")
        try checkNotice(root: root, manifest: manifest)
        try checkLicencesLock(root: root, manifest: manifest)
        try checkSponsorGating(root: root)
        let requiredPrivacyManifests = [
            apps.appendingPathComponent("Exporter-iOS/PrivacyInfo.xcprivacy"),
            apps.appendingPathComponent("StatusWidget/PrivacyInfo.xcprivacy"),
            apps.appendingPathComponent("Companion-macOS/PrivacyInfo.xcprivacy"),
        ]
        var privacyViolations: [String] = []
        for file in requiredPrivacyManifests {
            guard let data = try? Data(contentsOf: file),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let values = plist as? [String: Any]
            else {
                privacyViolations.append("\(file.path): missing or malformed")
                continue
            }
            if values["NSPrivacyTracking"] as? Bool != false {
                privacyViolations.append("\(file.path): tracking must be false")
            }
            if (values["NSPrivacyTrackingDomains"] as? [String])?.isEmpty != true {
                privacyViolations.append("\(file.path): tracking domains must be empty")
            }
            if (values["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty != true {
                privacyViolations.append("\(file.path): collected data types must be empty")
            }
        }
        if !privacyViolations.isEmpty {
            FileHandle.standardError.write(
                Data((privacyViolations.joined(separator: "\n") + "\n").utf8)
            )
            exit(1)
        }
        print("policycheck privacy manifests declare zero collection: ok")
        try checkLocalGovernance(root: root, manifest: manifest)
        try checkATS(root: root)
        let ambient = ["Date()", "Calendar.current", "TimeZone.current", "Locale.current"]
        let allowedAmbient = Set(["CoreTemporal", "HealthKitSource"])
        var ambientHits: [String] = []
        if let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) {
            for case let file as URL in files where file.pathExtension == "swift" {
                let target = file.path.split(separator: "/").drop(while: { $0 != "Sources" }).dropFirst().first.map(String.init) ?? ""
                if allowedAmbient.contains(target) { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                for token in ambient where text.contains(token) {
                    ambientHits.append("\(file.path): \(token)")
                }
            }
        }
        if !ambientHits.isEmpty {
            FileHandle.standardError.write(Data((ambientHits.joined(separator: "\n") + "\n").utf8))
            exit(1)
        }
        print("policycheck ambient clocks: ok")

        let workflows = root.appendingPathComponent(".github/workflows")
        if let files = FileManager.default.enumerator(at: workflows, includingPropertiesForKeys: nil) {
            for case let file as URL in files where file.pathExtension == "yml" || file.pathExtension == "yaml" {
                let text = try String(contentsOf: file, encoding: .utf8)
                let pullsOnPush = text.contains("pull_request:") || text.contains("pull_request ")
                let selfHosted = text.split(separator: "\n").contains {
                    $0.contains("runs-on:") && $0.contains("self-hosted")
                }
                if pullsOnPush, selfHosted {
                    FileHandle.standardError.write(
                        Data("\(file.path): self-hosted jobs must not use pull_request (QA-28)\n".utf8)
                    )
                    exit(1)
                }
            }
        }
        print("policycheck self-hosted runners stay off pull_request: ok")
        var disguise: [String] = []
        if let files = FileManager.default.enumerator(at: apps, includingPropertiesForKeys: nil) {
            for case let file as URL in files {
                let name = file.lastPathComponent
                guard name == "Info.plist" || file.pathExtension == "plist" else { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                if text.contains("CFBundleAlternateIcons") {
                    disguise.append("\(file.path): CFBundleAlternateIcons")
                }
            }
        }
        if !disguise.isEmpty {
            FileHandle.standardError.write(Data((disguise.joined(separator: "\n") + "\n").utf8))
            exit(1)
        }
        print("policycheck no alternate icons: ok")
        try checkStringCatalog(root: root)
        try checkNoHealthDenialClaims(root: root)
        try checkDisclaimerAndCopyDenylist(root: root)
        try checkUpstreamVersionPins(root: root)
        try checkAdjacency(root: root)
        try checkReceiverQuickstart(root: root)
        try checkHealthKitSymbolsStayInAdapter(sources: sources)
        try checkSpecArtifacts(root: root)
        try checkBackupExclusion(root: root)
        try checkHealthAuthorizationScope(root: root)
        try checkHostTZDataPin(root: root)
    }

    /// SEC-60/SEC-75/SEC-79/SEC-73: keep the public policies, the complete set of
    /// shipping privacy manifests, known first-party endpoints, and destination targets
    /// tied to one machine-readable inventory. App Store Connect remains an external
    /// declaration: the inventory may record an assessment, never claim submission.
    static func checkLocalGovernance(root: URL, manifest: String) throws {
        let inventoryRelative = "compliance/egress-inventory.json"
        let inventoryURL = root.appendingPathComponent(inventoryRelative)
        guard
            let inventory = try JSONSerialization.jsonObject(
                with: Data(contentsOf: inventoryURL)
            ) as? [String: Any],
            inventory["schemaVersion"] as? Int == 1,
            let flows = inventory["flows"] as? [[String: Any]],
            let firstPartyEndpoints = inventory["firstPartyNetworkEndpoints"] as? [String],
            let apple = inventory["applePrivacyMapping"] as? [String: Any],
            let declaredManifests = apple["privacyManifests"] as? [String],
            let label = apple["appPrivacyLabelAssessment"] as? [String: Any]
        else {
            FileHandle.standardError.write(
                Data("SEC-60 egress inventory is missing or malformed\n".utf8)
            )
            exit(1)
        }

        var problems: [String] = []
        let expectedFlowTargets: [String: Set<String>] = [
            "security-advisory-feed": ["NetEgress", "WireFormat"],
            "user-https-export": ["SinkHTTP"],
            "user-mqtt-export": ["SinkMQTT"],
            "user-otlp-export": ["OTLPExport"],
            "paired-companion-discovery": ["NetEgress"],
            "paired-companion-export": ["SinkCompanion", "NetEgress"],
            "user-local-file-export": ["SinkLocalFile"],
        ]
        let flowIDs = flows.compactMap { $0["id"] as? String }
        if flowIDs.count != flows.count || Set(flowIDs) != Set(expectedFlowTargets.keys) {
            problems.append(
                "SEC-60 flow IDs drifted; expected "
                    + expectedFlowTargets.keys.sorted().joined(separator: ", ")
            )
        }
        for flow in flows {
            guard let id = flow["id"] as? String else { continue }
            let targets = Set(flow["sourceTargets"] as? [String] ?? [])
            if targets != expectedFlowTargets[id] {
                problems.append("SEC-60 \(id) sourceTargets drifted")
            }
            if flow["destinationControl"] as? String == "project" {
                if flow["telemetry"] as? Bool != false || flow["healthData"] as? Bool != false {
                    problems.append("SEC-75 project-controlled flow \(id) carries telemetry or Health data")
                }
            }
        }
        let projectControlled = flows.filter { $0["destinationControl"] as? String == "project" }
            .compactMap { $0["id"] as? String }
        if projectControlled != ["security-advisory-feed"] {
            problems.append("SEC-75 project-controlled egress must be only security-advisory-feed")
        }

        if firstPartyEndpoints != [AdvisoryPinnedKeys.urlString] {
            problems.append(
                "SEC-60 first-party endpoints drifted from WireFormat.AdvisoryPinnedKeys"
            )
        }
        let advisoryDestination = flows.first {
            $0["id"] as? String == "security-advisory-feed"
        }?["destination"] as? String
        if advisoryDestination != AdvisoryPinnedKeys.urlString {
            problems.append("SEC-60 advisory flow endpoint drifted from its compiled endpoint")
        }

        let expectedManifests = [
            "Apps/Companion-macOS/PrivacyInfo.xcprivacy",
            "Apps/Exporter-iOS/PrivacyInfo.xcprivacy",
            "Apps/StatusWidget/PrivacyInfo.xcprivacy",
        ]
        if declaredManifests.sorted() != expectedManifests {
            problems.append("SEC-60 inventory privacy-manifest list drifted")
        }
        var foundManifests: [String] = []
        let apps = root.appendingPathComponent("Apps")
        if let files = FileManager.default.enumerator(at: apps, includingPropertiesForKeys: nil) {
            for case let file as URL in files where file.lastPathComponent == "PrivacyInfo.xcprivacy" {
                foundManifests.append(
                    file.path.replacingOccurrences(of: root.path + "/", with: "")
                )
            }
        }
        if foundManifests.sorted() != expectedManifests {
            problems.append("SEC-60 shipping privacy-manifest set drifted from the inventory")
        }
        if apple["tracking"] as? Bool != false
            || (apple["trackingDomains"] as? [Any])?.isEmpty != true
            || (apple["collectedDataTypes"] as? [Any])?.isEmpty != true
            || (label["dataCollected"] as? [Any])?.isEmpty != true
        {
            problems.append("SEC-60 inventory and privacy-label assessment must declare zero collection")
        }
        if label["status"] as? String
            != "repository assessment only; not an App Store Connect declaration"
        {
            problems.append("SEC-60 label status must not claim an App Store declaration")
        }

        let sinkPattern = try NSRegularExpression(
            pattern: #"\.target\(\s*name:\s*"(Sink[^"]+)""#
        )
        let targetPattern = try NSRegularExpression(
            pattern: #"\.target\(\s*name:\s*"([^"]+)""#
        )
        let nsManifest = manifest as NSString
        let sinkTargets = Set(sinkPattern.matches(
            in: manifest,
            range: NSRange(location: 0, length: nsManifest.length)
        ).map { nsManifest.substring(with: $0.range(at: 1)) })
        let packageTargets = Set(targetPattern.matches(
            in: manifest,
            range: NSRange(location: 0, length: nsManifest.length)
        ).map { nsManifest.substring(with: $0.range(at: 1)) })
        let inventoriedSinkTargets = Set(
            expectedFlowTargets.values.flatMap { $0 }.filter { $0.hasPrefix("Sink") }
        )
        if sinkTargets != inventoriedSinkTargets {
            problems.append("SEC-60 Package.swift sink targets drifted from the egress inventory")
        }
        let missingSourceTargets = Set(expectedFlowTargets.values.flatMap { $0 })
            .subtracting(packageTargets)
        if !missingSourceTargets.isEmpty {
            problems.append(
                "SEC-60 inventory names missing package targets: "
                    + missingSourceTargets.sorted().joined(separator: ", ")
            )
        }
        if label["submissionReadiness"] as? String
            != "blocked pending verification of the built privacy report, live advisory-host logging, and current App Store questions"
        {
            problems.append("SEC-60 privacy-label assessment must stay blocked pending live verification")
        }

        let requiredDocs: [(String, [String])] = [
            ("PRIVACY.md", [
                inventoryRelative,
                "does not collect, sell, or share personal information",
                AdvisoryPinnedKeys.urlString,
                "not an App Store Connect declaration",
            ]),
            ("CYBERSECURITY.md", [
                "Article 24",
                "not a claim of CRA compliance",
                "actively exploited vulnerability",
                inventoryRelative,
            ]),
            ("compliance/HIPAA-CONTEXT.md", [
                "must not contract with, provide the app to, or operate it for",
                "fresh, fact-specific legal review",
                "does not fabricate",
            ]),
            ("SECURITY.md", [
                "CYBERSECURITY.md",
                "PRIVACY.md",
                inventoryRelative,
                "compliance/HIPAA-CONTEXT.md",
            ]),
            ("README.md", [
                "CYBERSECURITY.md",
                "PRIVACY.md",
                inventoryRelative,
                "compliance/HIPAA-CONTEXT.md",
            ]),
        ]
        for (relative, needles) in requiredDocs {
            guard let text = try? String(
                contentsOf: root.appendingPathComponent(relative),
                encoding: .utf8
            ) else {
                problems.append("SEC governance artifact missing: \(relative)")
                continue
            }
            for needle in needles where !text.contains(needle) {
                problems.append("\(relative) does not contain \(needle)")
            }
        }

        if !problems.isEmpty {
            FileHandle.standardError.write(Data((problems.joined(separator: "\n") + "\n").utf8))
            exit(1)
        }
        print("policycheck SEC-60/SEC-75/SEC-79/SEC-73 governance mapping: ok")
    }

    /// R-35 / SEC-19: App Transport Security stays on. The only allowed exception is
    /// `NSAllowsLocalNetworking` on the iOS exporter. Arbitrary-loads keys fail even when false.
    static func checkATS(root: URL) throws {
        let arbitrary = [
            "NSAllowsArbitraryLoads",
            "NSAllowsArbitraryLoadsForMedia",
            "NSAllowsArbitraryLoadsInWebContent",
        ]
        let apps = root.appendingPathComponent("Apps")
        let ios = apps.appendingPathComponent("Exporter-iOS/Info.plist")
        let iosPlist = try loadInfoPlist(ios)
        guard let ats = iosPlist["NSAppTransportSecurity"] as? [String: Any] else {
            FileHandle.standardError.write(
                Data("R-35: NSAppTransportSecurity missing from Apps/Exporter-iOS/Info.plist\n".utf8)
            )
            exit(1)
        }
        for key in arbitrary where ats[key] != nil {
            FileHandle.standardError.write(
                Data("R-35 / SEC-19: \(key) must be absent from Exporter-iOS ATS\n".utf8)
            )
            exit(1)
        }
        let extras = Set(ats.keys).subtracting(["NSAllowsLocalNetworking"])
        if !extras.isEmpty {
            FileHandle.standardError.write(
                Data(
                    "R-35: undeclared ATS keys \(extras.sorted().joined(separator: ", "))\n".utf8
                )
            )
            exit(1)
        }
        guard ats["NSAllowsLocalNetworking"] as? Bool == true else {
            FileHandle.standardError.write(
                Data("R-35: NSAllowsLocalNetworking must be true and the sole ATS exception\n".utf8)
            )
            exit(1)
        }
        if let files = FileManager.default.enumerator(at: apps, includingPropertiesForKeys: nil) {
            for case let file as URL in files where file.lastPathComponent == "Info.plist" {
                if file.path.contains("Exporter-iOS/") { continue }
                let plist = try loadInfoPlist(file)
                guard let otherATS = plist["NSAppTransportSecurity"] as? [String: Any] else {
                    continue
                }
                for key in arbitrary where otherATS[key] != nil {
                    FileHandle.standardError.write(
                        Data("R-35 / SEC-19: \(key) must be absent from \(file.path)\n".utf8)
                    )
                    exit(1)
                }
            }
        }
        print("policycheck ATS local-networking only: ok")
    }

    static func loadInfoPlist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let plist = object as? [String: Any] else {
            FileHandle.standardError.write(Data("\(url.path): Info.plist is not a dictionary\n".utf8))
            exit(1)
        }
        return plist
    }

    static func checkStringCatalog(root: URL) throws {
        let catalogURL = root.appendingPathComponent("Apps/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sourceLanguage = json["sourceLanguage"] as? String,
            !sourceLanguage.isEmpty,
            let strings = json["strings"] as? [String: Any]
        else {
            FileHandle.standardError.write(
                Data("Apps/Localizable.xcstrings is missing or malformed\n".utf8)
            )
            exit(1)
        }

        // The source language and every locale represented in the shipping catalogue
        // are shipped locales. This deliberately makes an accidentally partial locale
        // fail instead of silently dropping it from the gate.
        var shipped = Set([sourceLanguage])
        for value in strings.values {
            let entry = value as? [String: Any]
            let localizations = entry?["localizations"] as? [String: Any] ?? [:]
            shipped.formUnion(localizations.keys)
        }
        guard !strings.isEmpty else {
            FileHandle.standardError.write(Data("string catalog contains no strings\n".utf8))
            exit(1)
        }
        for language in shipped.sorted() {
            let eligible = strings.values.compactMap { value -> [String: Any]? in
                guard let entry = value as? [String: Any],
                      entry["shouldTranslate"] as? Bool != false
                else { return nil }
                return entry
            }
            let translated = eligible.filter { entry in
                let localizations = entry["localizations"] as? [String: Any]
                guard let localization = localizations?[language] as? [String: Any] else {
                    return false
                }
                return catalogLocalizationIsTranslated(localization)
            }.count
            let ratio = eligible.isEmpty ? 0.0 : Double(translated) / Double(eligible.count)
            if ratio < 0.95 {
                FileHandle.standardError.write(
                    Data(
                        (
                            "QA-27 string catalog \(language) completeness "
                                + "\(translated)/\(eligible.count) "
                                + "(\(String(format: "%.1f", ratio * 100))%) is below 95%\n"
                        ).utf8
                    )
                )
                exit(1)
            }
            print(
                "policycheck string catalog \(language) completeness: "
                    + "\(translated)/\(eligible.count) "
                    + "(\(String(format: "%.1f", ratio * 100))%)"
            )
        }

        let apps = root.appendingPathComponent("Apps")
        var missing: [String] = []
        if let files = FileManager.default.enumerator(at: apps, includingPropertiesForKeys: nil) {
            for case let file as URL in files where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
                for literal in appUILiterals(in: text) + appLocalizedValueLiterals(in: text) {
                    if strings[literal.value] == nil {
                        missing.append(
                            "\(relative):\(literal.line): \(String(reflecting: literal.value))"
                        )
                    }
                }
            }
        }
        if !missing.isEmpty {
            FileHandle.standardError.write(
                Data(
                    (
                        "QA-27 app UI literals missing from Apps/Localizable.xcstrings:\n"
                            + missing.sorted().joined(separator: "\n")
                            + "\n"
                    ).utf8
                )
            )
            exit(1)
        }
        print("policycheck string catalog covers app UI literals: ok")
    }

    static func catalogLocalizationIsTranslated(_ localization: [String: Any]) -> Bool {
        var foundUnit = false
        func visit(_ value: Any) -> Bool {
            if let dictionary = value as? [String: Any] {
                if let unit = dictionary["stringUnit"] as? [String: Any] {
                    foundUnit = true
                    guard unit["state"] as? String == "translated",
                          let text = unit["value"] as? String,
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else { return false }
                }
                for (key, child) in dictionary where key != "stringUnit" {
                    if !visit(child) { return false }
                }
            } else if let array = value as? [Any] {
                for child in array where !visit(child) { return false }
            }
            return true
        }
        return visit(localization) && foundUnit
    }

    struct AppUILiteral {
        let value: String
        let line: Int
    }

    /// QA-27: inspect string literals passed to APIs that put copy on screen or expose
    /// it to accessibility. Matching the first argument avoids flagging technical
    /// values such as SF Symbol names, accessibility identifiers and URLs.
    static func appUILiterals(in source: String) -> [AppUILiteral] {
        let uiAPIs = [
            "Text", "Button", "Label", "TextField", "SecureField", "Toggle",
            "Section", "Picker", "Menu", "Link", "ContentUnavailableView",
            "IntentDescription",
            "navigationTitle", "alert", "confirmationDialog",
            "accessibilityLabel", "accessibilityHint",
            "configurationDisplayName", "description",
        ]
        let names = uiAPIs.map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let calls = try! NSRegularExpression(pattern: #"\b("# + names + #")\s*\("#)
        let ns = source as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var literals: [AppUILiteral] = []
        for call in calls.matches(in: source, range: fullRange) {
            let openParen = call.range.location + call.range.length - 1
            let argument = firstSwiftArgument(in: ns, afterOpenParen: openParen)
            guard argument.length > 0 else { continue }
            let argumentText = ns.substring(with: argument)
            // A Swift interpolation may itself contain quoted expressions. A regex
            // would misread those quotes and the suffix as separate literals. The
            // compiler/catalog owns substitution metadata for these dynamic keys.
            guard !argumentText.contains(#"\("#) else { continue }
            let argumentNS = argumentText as NSString
            let stringPattern = try! NSRegularExpression(pattern: #""((?:\\.|[^"\\])*)""#)
            for match in stringPattern.matches(
                in: argumentText,
                range: NSRange(location: 0, length: argumentNS.length)
            ) {
                let raw = argumentNS.substring(with: match.range(at: 1))
                let value = decodeSwiftStringLiteral(raw)
                guard !value.isEmpty else { continue }
                let absolute = argument.location + match.range.location
                let prefix = ns.substring(with: NSRange(location: 0, length: absolute))
                literals.append(
                    AppUILiteral(
                        value: value,
                        line: prefix.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
                    )
                )
            }
        }
        return literals
    }

    /// Values passed through a named UI property are not direct SwiftUI arguments at
    /// their declaration site (for example `Text(state.label)`). Keep those computed
    /// labels and explicitly localized resource declarations inside the same gate.
    static func appLocalizedValueLiterals(in source: String) -> [AppUILiteral] {
        let ns = source as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let declarations = try! NSRegularExpression(
            pattern: #"\b(?:let|var)\s+\w+\s*:\s*(?:LocalizedStringResource|LocalizedStringKey)\s*="#
        )
        let properties = try! NSRegularExpression(
            pattern: #"\bvar\s+(?:label|title|copy|message|hint|errorDescription)\s*:\s*String\??\s*\{"#,
            options: [.caseInsensitive]
        )
        var ranges: [NSRange] = []
        for match in declarations.matches(in: source, range: fullRange) {
            let remainder = NSRange(
                location: match.range.location + match.range.length,
                length: ns.length - match.range.location - match.range.length
            )
            let newline = ns.range(of: "\n", options: [], range: remainder)
            let end = newline.location == NSNotFound ? ns.length : newline.location
            ranges.append(NSRange(location: remainder.location, length: end - remainder.location))
        }
        for match in properties.matches(in: source, range: fullRange) {
            let openBrace = match.range.location + match.range.length - 1
            if let body = balancedSwiftBlock(in: ns, afterOpenBrace: openBrace) {
                ranges.append(body)
            }
        }

        let stringPattern = try! NSRegularExpression(pattern: #""((?:\\.|[^"\\])*)""#)
        var literals: [AppUILiteral] = []
        for range in ranges {
            let text = ns.substring(with: range)
            guard !text.contains(#"\("#) else { continue }
            let textNS = text as NSString
            for match in stringPattern.matches(
                in: text,
                range: NSRange(location: 0, length: textNS.length)
            ) {
                let value = decodeSwiftStringLiteral(textNS.substring(with: match.range(at: 1)))
                guard !value.isEmpty else { continue }
                let absolute = range.location + match.range.location
                let prefix = ns.substring(with: NSRange(location: 0, length: absolute))
                literals.append(
                    AppUILiteral(
                        value: value,
                        line: prefix.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
                    )
                )
            }
        }
        return literals
    }

    static func balancedSwiftBlock(in text: NSString, afterOpenBrace openBrace: Int) -> NSRange? {
        var index = openBrace + 1
        let start = index
        var nesting = 0
        var inString = false
        var escaped = false
        while index < text.length {
            let scalar = text.character(at: index)
            if inString {
                if escaped {
                    escaped = false
                } else if scalar == 92 {
                    escaped = true
                } else if scalar == 34 {
                    inString = false
                }
            } else if scalar == 34 {
                inString = true
            } else if scalar == 123 {
                nesting += 1
            } else if scalar == 125 {
                if nesting == 0 {
                    return NSRange(location: start, length: index - start)
                }
                nesting -= 1
            }
            index += 1
        }
        return nil
    }

    static func firstSwiftArgument(in text: NSString, afterOpenParen openParen: Int) -> NSRange {
        var index = openParen + 1
        let start = index
        var nesting = 0
        var inString = false
        var escaped = false
        while index < text.length {
            let scalar = text.character(at: index)
            if inString {
                if escaped {
                    escaped = false
                } else if scalar == 92 {
                    escaped = true
                } else if scalar == 34 {
                    inString = false
                }
            } else {
                switch scalar {
                case 34:
                    inString = true
                case 40, 91, 123:
                    nesting += 1
                case 41:
                    if nesting == 0 {
                        return NSRange(location: start, length: index - start)
                    }
                    nesting -= 1
                case 93, 125:
                    nesting = max(0, nesting - 1)
                case 44 where nesting == 0:
                    return NSRange(location: start, length: index - start)
                default:
                    break
                }
            }
            index += 1
        }
        return NSRange(location: start, length: max(0, text.length - start))
    }

    static func decodeSwiftStringLiteral(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\""#, with: #"""#)
            .replacingOccurrences(of: #"\\n"#, with: "\n")
            .replacingOccurrences(of: #"\\t"#, with: "\t")
            .replacingOccurrences(of: #"\\r"#, with: "\r")
            .replacingOccurrences(of: #"\\\\"#, with: #"\"#)
    }

    /// R-60: Apple guarantees a denied HealthKit read is indistinguishable from absent
    /// data, so no user-facing string may claim one. Positively detectable denials —
    /// Local Network, notifications — say so in their own words and carry no Health term,
    /// which is why the gate requires both a denial verb and a Health noun to fire.
    static func checkNoHealthDenialClaims(root: URL) throws {
        let denialTerms = [
            "denied", "denial", "refused", "rejected",
            "not authorized", "not authorised", "unauthorized", "unauthorised",
            "no permission", "permission was", "you declined",
        ]
        let healthTerms = ["health"]
        // Naming the ambiguity is the requirement, not a breach of it: copy may say that
        // we cannot know whether a type was allowed or denied. It may not say it was.
        let ambiguityPhrases = [
            "does not tell us", "doesn't tell us", "cannot tell", "can't tell",
            "no way to know", "indistinguishable", "whether you allowed or denied",
        ]
        let literal = try NSRegularExpression(pattern: #""([^"\\\n]{12,})""#)
        var claims: [String] = []
        for directory in ["Sources", "Apps"] {
            let base = root.appendingPathComponent(directory)
            guard let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let file as URL in files where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                let ns = text as NSString
                for match in literal.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    let value = ns.substring(with: match.range(at: 1))
                    let lowered = value.lowercased()
                    guard healthTerms.contains(where: { lowered.contains($0) }) else { continue }
                    guard denialTerms.contains(where: { lowered.contains($0) }) else { continue }
                    guard !ambiguityPhrases.contains(where: { lowered.contains($0) }) else { continue }
                    claims.append("\(file.lastPathComponent): \(value)")
                }
            }
        }
        if !claims.isEmpty {
            FileHandle.standardError.write(
                Data(("R-60 forbids claiming a Health read was denied:\n"
                    + claims.joined(separator: "\n") + "\n").utf8)
            )
            exit(1)
        }
        print("policycheck no copy claims a Health read was denied: ok")
    }

    /// R-109: the canonical disclaimer must appear on every public surface we have.
    /// R-113: published copy must not claim medical, diagnostic, clinical, FDA/CE or
    /// HIPAA status unless the sentence also negates the claim, or the remaining hit
    /// is listed in compliance/allowlist.txt with a reason.
    static func checkDisclaimerAndCopyDenylist(root: URL) throws {
        let disclaimer = try String(
            contentsOf: root.appendingPathComponent("compliance/disclaimer.txt"),
            encoding: .utf8
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !disclaimer.isEmpty else {
            FileHandle.standardError.write(Data("compliance/disclaimer.txt is empty\n".utf8))
            exit(1)
        }
        var missingDisclaimer: [String] = []
        for relative in [
            "README.md",
            "landing/index.html",
            "Apps/Exporter-iOS/HarnessView.swift",
            "Apps/Localizable.xcstrings",
            "receiver/README.md",
        ] {
            let text = try String(
                contentsOf: root.appendingPathComponent(relative),
                encoding: .utf8
            )
            if !text.contains(disclaimer) {
                missingDisclaimer.append(relative)
            }
        }
        if !missingDisclaimer.isEmpty {
            FileHandle.standardError.write(
                Data(
                    (
                        "R-109 disclaimer missing from: "
                            + missingDisclaimer.joined(separator: ", ")
                            + "\n"
                    ).utf8
                )
            )
            exit(1)
        }
        print("policycheck canonical disclaimer is on public surfaces: ok")
        try checkStoreCopy(root: root, disclaimer: disclaimer)

        let allowlistURL = root.appendingPathComponent("compliance/allowlist.txt")
        let allowlistText = try String(contentsOf: allowlistURL, encoding: .utf8)
        var allowlist: [(phrase: String, reason: String)] = []
        for raw in allowlistText.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                FileHandle.standardError.write(
                    Data("compliance/allowlist.txt line needs phrase<TAB>reason: \(line)\n".utf8)
                )
                exit(1)
            }
            allowlist.append((phrase: String(parts[0]).lowercased(), reason: String(parts[1])))
        }

        let denylist = [
            #"diagnos\w*"#,
            #"clinical\w*"#,
            #"\btreat(?:s|ed|ing|ment)?\b"#,
            #"\bscreening\b"#,
            #"\bscreen for\b"#,
            #"medical device"#,
            #"\bFDA\b"#,
            #"510\(k\)"#,
            #"CE mark\w*"#,
            #"\bHIPAA\b"#,
            #"\bPHI\b"#,
            #"prescription"#,
            #"therap\w*"#,
            #"monitor your condition"#,
            #"\bsymptom\w*"#,
            #"\bdisease\b"#,
        ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        let negation = try NSRegularExpression(
            pattern: #"\b(not a|is not|does not|do not|we do not|never)\b"#,
            options: [.caseInsensitive]
        )

        var hits: [String] = []
        var suppressions = 0
        func consider(source: String, text: String) {
            let ns = text as NSString
            let full = NSRange(location: 0, length: ns.length)
            for pattern in denylist {
                for match in pattern.matches(in: text, range: full) {
                    let start = max(0, match.range.location - 48)
                    let end = min(ns.length, match.range.location + match.range.length + 48)
                    let window = ns.substring(
                        with: NSRange(location: start, length: end - start)
                    )
                    let windowRange = NSRange(location: 0, length: (window as NSString).length)
                    if negation.firstMatch(in: window, range: windowRange) != nil {
                        continue
                    }
                    let lowered = window.lowercased()
                    if allowlist.contains(where: { lowered.contains($0.phrase) }) {
                        suppressions += 1
                        continue
                    }
                    let snippet = window.replacingOccurrences(of: "\n", with: " ")
                    hits.append("\(source): \(snippet)")
                }
            }
        }

        for relative in [
            "README.md",
            "landing/index.html",
            "CONTINUITY.md",
            "CHANGELOG.md",
            "CONTRIBUTING.md",
            "SECURITY.md",
            "SUPPORT.md",
            "GOVERNANCE.md",
            "CODE_OF_CONDUCT.md",
            "MAINTAINERS.md",
            "VERSIONING.md",
            "PROVENANCE.md",
            "dependencies/policy.md",
            "qa/energy-protocol.md",
            "qa/community-device-matrix/CHECKLIST.md",
            "docs/03-implementation/r27-failure-taxonomy.md",
            "receiver/README.md",
            "receiver/grafana/dashboards/ohe-receiver.json",
        ] {
            let url = root.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            consider(
                source: relative,
                text: try String(contentsOf: url, encoding: .utf8)
            )
        }
        let catalogURL = root.appendingPathComponent("Apps/Localizable.xcstrings")
        if let data = try? Data(contentsOf: catalogURL),
           let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let strings = json["strings"] as? [String: Any]
        {
            for (key, value) in strings {
                let entry = value as? [String: Any]
                let locales = entry?["localizations"] as? [String: Any]
                let unit = (locales?["en"] as? [String: Any])?["stringUnit"] as? [String: Any]
                let shown = (unit?["value"] as? String) ?? key
                consider(source: "Localizable.xcstrings", text: shown)
            }
        }
        let changes = root.appendingPathComponent("changes/unreleased")
        if let files = FileManager.default.enumerator(at: changes, includingPropertiesForKeys: nil) {
            for case let file as URL in files where file.pathExtension == "md" {
                consider(
                    source: "changes/unreleased/\(file.lastPathComponent)",
                    text: try String(contentsOf: file, encoding: .utf8)
                )
            }
        }
        let store = root.appendingPathComponent("store")
        if let files = FileManager.default.enumerator(at: store, includingPropertiesForKeys: nil) {
            for case let file as URL in files where file.pathExtension == "txt" {
                let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
                consider(
                    source: relative,
                    text: try String(contentsOf: file, encoding: .utf8)
                )
            }
        }
        if !hits.isEmpty {
            FileHandle.standardError.write(
                Data(
                    (
                        "R-113 published copy matches a medical-claim denylist term:\n"
                            + hits.joined(separator: "\n")
                            + "\n"
                    ).utf8
                )
            )
            exit(1)
        }
        print("policycheck published copy denylist: ok (\(suppressions) allowlisted)")
        try checkGovernanceArtifacts(root: root)
    }

    /// R-113: App Store / TestFlight copy lives in-repo so the denylist can see it.
    /// Fielding it only in App Store Connect would make the gate unenforceable.
    static func checkStoreCopy(root: URL, disclaimer: String) throws {
        let brand = try String(contentsOf: root.appendingPathComponent("Brand.xcconfig"), encoding: .utf8)
        var displayName = "Open Health Exporter"
        for raw in brand.split(whereSeparator: \.isNewline) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("DISPLAY_NAME") {
                displayName = line.split(separator: "=", maxSplits: 1)
                    .last?
                    .trimmingCharacters(in: .whitespaces) ?? displayName
            }
        }
        let limits: [(String, Int)] = [
            ("name", 30),
            ("subtitle", 30),
            ("keywords", 100),
            ("promotional-text", 170),
            ("description", 4000),
            ("whats-new", 4000),
            ("what-to-test", 4000),
        ]
        let disclaimerFields: Set<String> = [
            "description",
            "promotional-text",
            "whats-new",
            "what-to-test",
        ]
        var problems: [String] = []
        let locale = "en"
        for (field, limit) in limits {
            let relative = "store/\(locale)/\(field).txt"
            let url = root.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path) else {
                problems.append("missing \(relative)")
                continue
            }
            let text = try String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                problems.append("\(relative) is empty")
            }
            if text.count > limit {
                problems.append("\(relative) is \(text.count) characters; App Store limit is \(limit)")
            }
            if disclaimerFields.contains(field), !text.contains(disclaimer) {
                problems.append("\(relative) is missing the canonical disclaimer")
            }
            if field == "name", text != displayName {
                problems.append("\(relative) must match Brand.xcconfig DISPLAY_NAME (\(displayName))")
            }
        }
        if !problems.isEmpty {
            FileHandle.standardError.write(Data((problems.joined(separator: "\n") + "\n").utf8))
            exit(1)
        }
        print("policycheck store/\(locale) listing copy: ok")
    }

    /// OSS-07: the files a stranger looks for before trusting a health-data project.
    static func checkGovernanceArtifacts(root: URL) throws {
        let required: [(String, [String])] = [
            ("CONTRIBUTING.md", ["git commit -s", "inbound licence equals outbound"]),
            ("CODE_OF_CONDUCT.md", ["Enforcement contact"]),
            ("SECURITY.md", ["14 days"]),
            ("SUPPORT.md", ["best-effort"]),
            ("GOVERNANCE.md", ["consent of all copyright holders", "90"]),
            ("MAINTAINERS.md", ["colinedwardwood"]),
            ("CHANGELOG.md", ["changes/unreleased"]),
            ("NOTICE", ["no third-party Swift packages", "sqlite3", "zlib"]),
            ("VERSIONING.md", ["The streams do not imply each other", "policycheck spec-freeze"]),
            ("PROVENANCE.md", ["Auditable source", "R-84 is about export output", "gh attestation verify"]),
            ("dependencies/policy.md", ["90 days", "licences.lock"]),
            ("dependencies/licences.lock", ["sqlite3", "zlib"]),
            ("CODEOWNERS", ["@colinedwardwood"]),
            (".github/PULL_REQUEST_TEMPLATE.md", ["DCO"]),
            (".github/ISSUE_TEMPLATE/bug.yml", ["Do not paste real HealthKit"]),
            ("docs/03-implementation/r27-failure-taxonomy.md", ["age_seconds", "jq"]),
            ("qa/community-device-matrix/CHECKLIST.md", ["results.csv", "Do not paste real HealthKit"]),
            ("qa/community-device-matrix/results.csv", ["device_class", "os_version", "outcome"]),
            ("qa/energy-protocol.md", ["not a CI gate", "Instruments"]),
        ]
        var missing: [String] = []
        for (relative, needles) in required {
            let url = root.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: url.path) else {
                missing.append("missing \(relative)")
                continue
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            let lowered = text.lowercased()
            for needle in needles where !lowered.contains(needle.lowercased()) {
                missing.append("\(relative) does not contain \(needle)")
            }
        }
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        for linked in [
            "CONTRIBUTING.md",
            "SECURITY.md",
            "SUPPORT.md",
            "CODE_OF_CONDUCT.md",
            "NOTICE",
            "VERSIONING.md",
            "PROVENANCE.md",
            "docs/03-implementation/r27-failure-taxonomy.md",
            "qa/community-device-matrix/CHECKLIST.md",
            "qa/energy-protocol.md",
        ]
            where !readme.contains(linked)
        {
            missing.append("README.md does not link \(linked)")
        }
        let compatibility = root.appendingPathComponent("spec/compatibility.json")
        guard let data = try? Data(contentsOf: compatibility),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["defaultSpec"] as? String == "1.0.0"
        else {
            missing.append("spec/compatibility.json missing or defaultSpec is not 1.0.0")
            FileHandle.standardError.write(Data((missing.joined(separator: "\n") + "\n").utf8))
            exit(1)
        }
        let provenanceSentence =
            "You cannot verify that the App Store binary matches"
        if !readme.contains(provenanceSentence) {
            missing.append("README.md does not contain the R-108 provenance sentence")
        }
        let provenance = try String(contentsOf: root.appendingPathComponent("PROVENANCE.md"), encoding: .utf8)
        if !provenance.contains(provenanceSentence) {
            missing.append("PROVENANCE.md does not contain the R-108 provenance sentence")
        }
        if !missing.isEmpty {
            FileHandle.standardError.write(Data((missing.joined(separator: "\n") + "\n").utf8))
            exit(1)
        }
        let coverageData = try Data(
            contentsOf: root.appendingPathComponent("qa/coverage-policy.json")
        )
        let coveragePolicy = try JSONSerialization.jsonObject(with: coverageData)
            as? [String: Any]
        let transition = coveragePolicy?["transitionCoverage"] as? [String: Any]
        let evidence = transition?["evidence"] as? String
        let evidenceParts = evidence?.components(separatedBy: "::") ?? []
        guard (transition?["minimum"] as? NSNumber)?.doubleValue == 100,
              evidenceParts.count == 2,
              let evidenceSource = try? String(
                  contentsOf: root.appendingPathComponent(evidenceParts[0]),
                  encoding: .utf8
              ),
              evidenceSource.contains("func \(evidenceParts[1])")
        else {
            FileHandle.standardError.write(
                Data("QA-33: 100% transition evidence is missing or stale\n".utf8)
            )
            exit(1)
        }
        print("policycheck governance artifacts: ok")
        try checkMutationCatalog(root: root)
        try checkFlakeQuarantinePolicy(root: root)
        try checkLicenceTexts(root: root)
    }

    /// QA-33: committed mutants must remain unique, weekly, and not a required PR check.
    static func checkMutationCatalog(root: URL) throws {
        let coverageData = try Data(
            contentsOf: root.appendingPathComponent("qa/coverage-policy.json")
        )
        guard
            let coveragePolicy = try JSONSerialization.jsonObject(with: coverageData)
                as? [String: Any],
            let mutation = coveragePolicy["mutationTesting"] as? [String: Any],
            let catalogPath = mutation["catalog"] as? String,
            let workflowPath = mutation["workflow"] as? String,
            let checkerPath = mutation["checker"] as? String
        else {
            FileHandle.standardError.write(
                Data("QA-33: coverage-policy.json mutationTesting catalog is missing\n".utf8)
            )
            exit(1)
        }
        let catalogURL = root.appendingPathComponent(catalogPath)
        guard
            let catalogData = try? Data(contentsOf: catalogURL),
            let catalog = try JSONSerialization.jsonObject(with: catalogData) as? [String: Any],
            (catalog["schemaVersion"] as? NSNumber)?.intValue == 1,
            let mutants = catalog["mutants"] as? [[String: Any]],
            mutants.count >= 3
        else {
            FileHandle.standardError.write(
                Data("QA-33: qa/mutants.json must declare schemaVersion 1 and at least 3 mutants\n".utf8)
            )
            exit(1)
        }
        var ids = Set<String>()
        for mutant in mutants {
            guard
                let ident = mutant["id"] as? String, !ident.isEmpty,
                let file = mutant["file"] as? String, !file.isEmpty,
                let find = mutant["find"] as? String, !find.isEmpty,
                let replace = mutant["replace"] as? String, !replace.isEmpty,
                let filter = mutant["filter"] as? String, !filter.isEmpty
            else {
                FileHandle.standardError.write(Data("QA-33: mutant is missing required fields\n".utf8))
                exit(1)
            }
            if !ids.insert(ident).inserted {
                FileHandle.standardError.write(Data("QA-33: duplicate mutant id \(ident)\n".utf8))
                exit(1)
            }
            if find == replace {
                FileHandle.standardError.write(Data("QA-33: \(ident) find and replace are identical\n".utf8))
                exit(1)
            }
            if let host = mutant["host"] as? String, host != "darwin", host != "linux" {
                FileHandle.standardError.write(
                    Data("QA-33: \(ident) host must be darwin or linux\n".utf8)
                )
                exit(1)
            }
            let source = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            let occurrences = source.components(separatedBy: find).count - 1
            if occurrences != 1 {
                FileHandle.standardError.write(
                    Data("QA-33: \(ident) find must occur exactly once in \(file)\n".utf8)
                )
                exit(1)
            }
            if source.contains(replace) {
                FileHandle.standardError.write(
                    Data("QA-33: \(ident) replace is already present in \(file)\n".utf8)
                )
                exit(1)
            }
        }
        var foundFilters = Set<String>()
        let testsRoot = root.appendingPathComponent("Tests")
        let enumerator = FileManager.default.enumerator(
            at: testsRoot,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for mutant in mutants {
                guard let filter = mutant["filter"] as? String else { continue }
                if text.contains("func \(filter)") {
                    foundFilters.insert(filter)
                }
            }
        }
        for mutant in mutants {
            guard let filter = mutant["filter"] as? String else { continue }
            if !foundFilters.contains(filter) {
                FileHandle.standardError.write(
                    Data("QA-33: no test named \(filter) for mutant \(mutant["id"] ?? "")\n".utf8)
                )
                exit(1)
            }
        }
        let workflow = try String(
            contentsOf: root.appendingPathComponent(workflowPath),
            encoding: .utf8
        )
        if workflow.contains("pull_request:") || workflow.contains("push:") {
            FileHandle.standardError.write(
                Data("QA-33: mutation workflow must not run on pull_request or push\n".utf8)
            )
            exit(1)
        }
        if !workflow.contains("schedule:") || !workflow.contains("workflow_dispatch:") {
            FileHandle.standardError.write(
                Data("QA-33: mutation workflow must be weekly and dispatchable\n".utf8)
            )
            exit(1)
        }
        let checker = root.appendingPathComponent(checkerPath)
        guard FileManager.default.isReadableFile(atPath: checker.path) else {
            FileHandle.standardError.write(Data("QA-33: mutation checker is missing\n".utf8))
            exit(1)
        }
        let selfTest = Process()
        selfTest.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        selfTest.arguments = [checker.path, "--self-test", "--root", root.path]
        try selfTest.run()
        selfTest.waitUntilExit()
        guard selfTest.terminationStatus == 0 else {
            FileHandle.standardError.write(Data("QA-33: mutation-check.py --self-test failed\n".utf8))
            exit(1)
        }
        print("policycheck mutation catalog: ok")
    }

    /// QA-32: skipped tests must cite a quarantine issue and expiry; the issue template
    /// carries the one-business-day SLA.
    static func checkFlakeQuarantinePolicy(root: URL) throws {
        let policyURL = root.appendingPathComponent("qa/flake-quarantine.json")
        guard
            let data = try? Data(contentsOf: policyURL),
            let policy = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            (policy["schemaVersion"] as? NSNumber)?.intValue == 1,
            (policy["slaBusinessDays"] as? NSNumber)?.intValue == 1,
            let templatePath = policy["issueTemplate"] as? String,
            let checkerPath = policy["checker"] as? String
        else {
            FileHandle.standardError.write(
                Data("QA-32: qa/flake-quarantine.json is missing or incomplete\n".utf8)
            )
            exit(1)
        }
        let template = try String(
            contentsOf: root.appendingPathComponent(templatePath),
            encoding: .utf8
        )
        for token in ["flake", "quarantine", "expires", "one business day"] {
            if !template.lowercased().contains(token) && token != "one business day" {
                FileHandle.standardError.write(
                    Data("QA-32: issue template is missing \(token)\n".utf8)
                )
                exit(1)
            }
        }
        if !template.contains("one business day") {
            FileHandle.standardError.write(
                Data("QA-32: issue template must state the one-business-day SLA\n".utf8)
            )
            exit(1)
        }
        let checker = root.appendingPathComponent(checkerPath)
        let selfTest = Process()
        selfTest.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        selfTest.arguments = [checker.path, "--self-test", "--root", root.path]
        try selfTest.run()
        selfTest.waitUntilExit()
        guard selfTest.terminationStatus == 0 else {
            FileHandle.standardError.write(Data("QA-32: quarantine-check.py --self-test failed\n".utf8))
            exit(1)
        }
        print("policycheck flake quarantine: ok")
    }

    /// OSS-15: `reuse lint` proves every file is annotated, but it cannot tell that the
    /// copy of the licence under `LICENSES/` still says what the root grant says. Two
    /// copies of the same text is what REUSE asks for, so the identity is asserted here
    /// rather than left to whoever edits one of them.
    static func checkLicenceTexts(root: URL) throws {
        var problems: [String] = []
        let manifest = root.appendingPathComponent("REUSE.toml")
        guard let toml = try? String(contentsOf: manifest, encoding: .utf8) else {
            FileHandle.standardError.write(Data("REUSE.toml is missing\n".utf8))
            exit(1)
        }

        let grant = try String(contentsOf: root.appendingPathComponent("LICENSE"), encoding: .utf8)
        let copy = root.appendingPathComponent("LICENSES/AGPL-3.0-or-later.txt")
        if (try? String(contentsOf: copy, encoding: .utf8)) != grant {
            problems.append("LICENSES/AGPL-3.0-or-later.txt is not byte-identical to LICENSE")
        }

        // Every identifier the manifest names needs its verbatim text on disk, or the
        // lint passes locally and fails for whoever packages a release.
        for line in toml.split(whereSeparator: \.isNewline)
            where line.contains("SPDX-License-Identifier")
        {
            guard let quoted = line.split(separator: "\"").dropFirst().first else { continue }
            let identifier = String(quoted)
            let text = root.appendingPathComponent("LICENSES/\(identifier).txt")
            if !FileManager.default.fileExists(atPath: text.path) {
                problems.append("REUSE.toml names \(identifier) with no LICENSES/\(identifier).txt")
            }
        }

        if !problems.isEmpty {
            FileHandle.standardError.write(Data((problems.joined(separator: "\n") + "\n").utf8))
            exit(1)
        }
        print("policycheck licence texts: ok")
    }

    static func checkHostTZDataPin(root: URL) throws {
        #if os(Linux)
        let platform = "linux"
        #else
        let platform = "darwin"
        #endif
        let pinURL = root.appendingPathComponent(
            "spec/v1.0.0/fixtures/host-tzdata-\(platform).txt"
        )
        let allowed = try String(contentsOf: pinURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let observed = TimeZone.timeZoneDataVersion
        guard allowed.contains(observed) else {
            FileHandle.standardError.write(
                Data(
                    (
                        "host tzdata drift on \(platform): allowed \(allowed.joined(separator: ", ")), "
                            + "observed \(observed); review frozen outputs before updating the pin\n"
                    ).utf8
                )
            )
            exit(1)
        }
        print("policycheck host tzdata \(platform) pin \(observed): ok")
    }

    static func checkUpstreamVersionPins(root: URL) throws {
        let pinsURL = root.appendingPathComponent("spec/v1.0.0/fixtures/ha-ci/versions.json")
        guard
            let pins = try JSONSerialization.jsonObject(with: Data(contentsOf: pinsURL)) as? [String: Any],
            let current = pins["currentStable"] as? String, !current.isEmpty,
            let oldest = pins["oldestInWindow"] as? String, !oldest.isEmpty,
            let mosquitto = pins["mosquittoTag"] as? String, !mosquitto.isEmpty,
            let otelCollector = pins["otelCollectorTag"] as? String, !otelCollector.isEmpty
        else {
            FileHandle.standardError.write(Data("ha-ci/versions.json is missing required pins\n".utf8))
            exit(1)
        }
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/container-contracts.yml"),
            encoding: .utf8
        )
        for token in [current, oldest, mosquitto, otelCollector] where !workflow.contains(token) {
            FileHandle.standardError.write(
                Data("container-contracts.yml does not pin declared upstream version \(token)\n".utf8)
            )
            exit(1)
        }
        let canary = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/upstream-canary.yml"),
            encoding: .utf8
        )
        if canary.contains("pull_request:") || canary.contains("push:") {
            FileHandle.standardError.write(
                Data("upstream-canary must not run on pull_request or push (QA-22)\n".utf8)
            )
            exit(1)
        }
        if !canary.contains("schedule:") || !canary.contains("workflow_dispatch:") {
            FileHandle.standardError.write(Data("upstream-canary must be nightly and dispatchable\n".utf8))
            exit(1)
        }
        print("policycheck upstream version pins match container contracts: ok")
    }

    /// OSS-18: NOTICE is generated from Package.swift and must match the committed file.
    static func checkNotice(root: URL, manifest: String) throws {
        let expected = generatedNotice(from: manifest)
        let observed = try String(contentsOf: root.appendingPathComponent("NOTICE"), encoding: .utf8)
        guard observed == expected else {
            FileHandle.standardError.write(
                Data("NOTICE is stale; regenerate from Package.swift:\n\(expected)".utf8)
            )
            exit(1)
        }
        let harness = try String(
            contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/HarnessView.swift"),
            encoding: .utf8
        )
        if !harness.contains("acknowledgements-body") || !harness.contains("forResource: \"NOTICE\"") {
            FileHandle.standardError.write(
                Data("in-app Acknowledgements must load NOTICE from the app bundle\n".utf8)
            )
            exit(1)
        }
        let companion = try String(
            contentsOf: root.appendingPathComponent("Apps/Companion-macOS/CompanionApp.swift"),
            encoding: .utf8
        )
        if !companion.contains("acknowledgements-body") || !companion.contains("forResource: \"NOTICE\"") {
            FileHandle.standardError.write(
                Data("Mac companion Acknowledgements must load NOTICE from the app bundle\n".utf8)
            )
            exit(1)
        }
        print("policycheck NOTICE matches Package.swift: ok")
    }

    static func generatedLicencesLock(from manifest: String) -> String {
        var rows = ["# Generated from Package.swift. Do not edit by hand."]
        if manifest.contains("name: \"CSQLite\"") {
            rows.append("sqlite3\tsystem\tCSQLite")
        }
        if manifest.contains("name: \"CZlib\"") {
            rows.append("zlib\tsystem\tCZlib")
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func checkLicencesLock(root: URL, manifest: String) throws {
        let expected = generatedLicencesLock(from: manifest)
        let observed = try String(
            contentsOf: root.appendingPathComponent("dependencies/licences.lock"),
            encoding: .utf8
        )
        guard observed == expected else {
            FileHandle.standardError.write(
                Data("dependencies/licences.lock is stale; regenerate from Package.swift:\n\(expected)".utf8)
            )
            exit(1)
        }
        print("policycheck licences.lock matches Package.swift: ok")
    }

    static func generatedNotice(from manifest: String) -> String {
        var libraries: [String] = []
        if manifest.contains("name: \"CSQLite\"") {
            libraries.append("- sqlite3 (CSQLite)")
        }
        if manifest.contains("name: \"CZlib\"") {
            libraries.append("- zlib (CZlib)")
        }
        return """
        Open Health Exporter
        Copyright (c) 2026 Colin Edward Wood and contributors

        Licensed under AGPL-3.0-or-later with the additional permission in COPYING.

        This binary contains no third-party Swift packages.

        System libraries declared in Package.swift:
        \(libraries.joined(separator: "\n"))

        """
    }

    static func checkSponsorGating(root: URL) throws {
        let forbidden = [
            "storekit",
            "sponsor",
            "donat",
            "patron",
            "supporter",
            "backer",
            "premium",
            "entitlementreceipt",
        ]
        let roots = [
            root.appendingPathComponent("Sources"),
            root.appendingPathComponent("Apps"),
        ]
        var hits: [String] = []
        for scanRoot in roots {
            guard let files = FileManager.default.enumerator(
                at: scanRoot,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }
            for case let file as URL in files {
                guard let values = try? file.resourceValues(
                    forKeys: [.isRegularFileKey]
                ),
                    values.isRegularFile == true,
                    let text = try? String(contentsOf: file, encoding: .utf8)
                else {
                    continue
                }
                let folded = text.lowercased()
                for token in forbidden where folded.contains(token) {
                    hits.append(
                        "\(file.path.replacingOccurrences(of: root.path + "/", with: "")): \(token)"
                    )
                }
            }
        }
        for relative in ["Package.swift", "project.yml"] {
            let file = root.appendingPathComponent(relative)
            let folded = try String(contentsOf: file, encoding: .utf8)
                .lowercased()
            for token in forbidden where folded.contains(token) {
                hits.append("\(relative): \(token)")
            }
        }
        if !hits.isEmpty {
            FileHandle.standardError.write(
                Data(
                    (
                        "R-110 sponsor-gating token in shipped source:\n"
                            + hits.sorted().joined(separator: "\n")
                            + "\n"
                    ).utf8
                )
            )
            exit(1)
        }
        print("policycheck no sponsor-gated feature or StoreKit reference: ok")
    }

    static func checkHealthKitSymbolsStayInAdapter(sources: URL) throws {
        let forbidden = ["HKHealthStore", "HKQuantitySample", "HKObserverQuery", "HKAnchoredObjectQuery"]
        var hits: [String] = []
        guard let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            return
        }
        for case let file as URL in files where file.pathExtension == "swift" {
            let target = file.path.split(separator: "/").drop(while: { $0 != "Sources" }).dropFirst().first.map(String.init) ?? ""
            if target == "HealthKitSource" { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden where text.contains(token) {
                hits.append("\(file.path): \(token)")
            }
        }
        if !hits.isEmpty {
            FileHandle.standardError.write(Data((hits.joined(separator: "\n") + "\n").utf8))
            exit(1)
        }
        print("policycheck HealthKit types stay in HealthKitSource: ok")
    }

    /// SEC-30: the app's storage root holds the state database, the journal and queued
    /// payloads. Creating it without excluding it from backup is the whole of T-16, and
    /// the omission is invisible in review because the protection class next to it looks
    /// like the mitigation. Asserted where the directory is made, not where it is used.
    static func checkBackupExclusion(root: URL) throws {
        let file = root.appendingPathComponent("Apps/Exporter-iOS/HarnessExport.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        guard let body = text.range(of: "applicationSupportRoot() throws -> URL") else {
            FileHandle.standardError.write(
                Data("HarnessExport.applicationSupportRoot is gone; SEC-30 gate needs rewiring\n".utf8)
            )
            exit(1)
        }
        // The call has to be inside the function that creates the directory.
        let remainder = text[body.upperBound...]
        let end = remainder.range(of: "\n    }")?.lowerBound ?? remainder.endIndex
        guard remainder[..<end].contains("excludeFromBackup") else {
            FileHandle.standardError.write(
                Data("SEC-30: applicationSupportRoot does not exclude the storage root from backup\n".utf8)
            )
            exit(1)
        }
        print("policycheck SEC-30 storage root excluded from backup: ok")
    }

    /// R-62: authorisation is requested per feature, for the types that feature will
    /// actually read. Asking for the whole catalogue trains people to say no to
    /// everything, and it is the request a reviewer cannot justify. The existing test
    /// only watched one file; a new call site anywhere else is the realistic way this
    /// regresses, so the scan is repo-wide.
    static func checkHealthAuthorizationScope(root: URL) throws {
        let wholeCatalogue = ["MetricCatalog.all", "MetricCatalog.selectable"]
        var hits: [String] = []
        for directory in ["Sources", "Apps"] {
            let base = root.appendingPathComponent(directory)
            guard let files = FileManager.default.enumerator(
                at: base,
                includingPropertiesForKeys: nil
            ) else { continue }
            for case let file as URL in files where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                var searched = text.startIndex
                while let call = text.range(of: "requestReadAccess", range: searched ..< text.endIndex) {
                    // The argument list, not the rest of the file.
                    let window = text[call.upperBound...].prefix(240)
                    let arguments = window.prefix(while: { $0 != ")" })
                    for token in wholeCatalogue where arguments.contains(token) {
                        hits.append("\(file.lastPathComponent): requestReadAccess asks for \(token)")
                    }
                    searched = call.upperBound
                }
            }
        }
        if !hits.isEmpty {
            FileHandle.standardError.write(Data((hits.joined(separator: "\n") + "\n").utf8))
            exit(1)
        }
        print("policycheck R-62 authorisation stays per-feature: ok")
    }

    static func checkSpecArtifacts(root: URL) throws {
        let spec = root.appendingPathComponent("spec/v1.0.0")
        for relative in [
            "README.md",
            "adjacency.json",
            "fixtures/fix-catalogue.json",
            "fixtures/receiver-expected-state.json",
            "catalogue/hk-statistics-exceptions.json",
            "catalogue/metrics.json",
            "schema/ohe.wire.1.json",
        ] {
            let url = spec.appendingPathComponent(relative)
            let data = try Data(contentsOf: url)
            _ = try JSONSerialization.jsonObject(with: data)
        }
        let corpus = spec.appendingPathComponent("fixtures/tier0.ndjson")
        let size = try FileManager.default.attributesOfItem(atPath: corpus.path)[.size] as? Int ?? 0
        guard size > 0 else {
            FileHandle.standardError.write(Data("tier0 corpus missing\n".utf8))
            exit(1)
        }

        let schemaURL = spec.appendingPathComponent("schema/ohe.wire.1.json")
        let schema = try WireJSONSchema.load(Data(contentsOf: schemaURL))
        let corpusText = try String(contentsOf: corpus, encoding: .utf8)
        try WireJSONSchema.validateNDJSON(corpusText, schema: schema)
        let corpusObjects = try corpusText.split(whereSeparator: \.isNewline).map {
            try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        guard let provenance = corpusObjects.first ?? nil,
              provenance["synthetic"] as? Bool == true,
              provenance["tier"] as? String == "T0",
              provenance["seed"] as? Int == 1,
              provenance["generatorVersion"] as? Int == 1,
              provenance["recordCount"] as? Int == 200,
              corpusObjects.count == 201
        else {
            FileHandle.standardError.write(
                Data("tier-zero provenance or record count is invalid\n".utf8)
            )
            exit(1)
        }
        let corpusKinds = Set(corpusObjects.compactMap { $0?["kind"] as? String })
        let requiredKinds: Set<String> = [
            "sample.quantity", "sample.category", "sample.correlation", "workout",
            "sample.stateOfMind", "sample.ecg", "series.ecgVoltage", "series.heartbeat",
            "series.workoutRoute", "series.workoutMetric", "sample.audiogram", "medicationDose",
        ]
        let sourceBundles = Set(corpusObjects.compactMap {
            ($0?["source"] as? [String: Any])?["bundleId"] as? String
        })
        let declaredTypes = provenance["types"] as? [String] ?? []
        guard corpusKinds.isSuperset(of: requiredKinds),
              sourceBundles.count >= 6,
              declaredTypes.count >= 60
        else {
            FileHandle.standardError.write(
                Data("tier-zero structural/source/type coverage is incomplete\n".utf8)
            )
            exit(1)
        }

        try checkFixtureProvenance(fixtures: spec.appendingPathComponent("fixtures"))

        let receiverInput = try String(
            contentsOf: spec.appendingPathComponent("fixtures/receiver-sequence.ndjson"),
            encoding: .utf8
        )
        var receiver = ReferenceReceiver()
        try receiver.ingest(ndjson: receiverInput)
        let expected = try JSONSerialization.jsonObject(
            with: Data(contentsOf: spec.appendingPathComponent("fixtures/receiver-expected-state.json"))
        )
        let actualData = try JSONSerialization.data(
            withJSONObject: receiver.expectedState(),
            options: [.sortedKeys]
        )
        let expectedData = try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys])
        guard actualData == expectedData else {
            FileHandle.standardError.write(Data("reference receiver final state drift\n".utf8))
            exit(1)
        }

        let catalogueURL = spec.appendingPathComponent("catalogue/metrics.json")
        let catalogue = try JSONSerialization.jsonObject(
            with: Data(contentsOf: catalogueURL)
        ) as? [String: Any]
        let committedMetrics = catalogue?["metrics"] as? [[String: Any]] ?? []
        let actualMetrics: [[String: Any]] = MetricCatalog.all.map {
            [
                "metricId": $0.wireId,
                "kind": "sample.quantity",
                "canonicalUnit": $0.wireUnit,
            ]
        }
        let committedMetricData = try JSONSerialization.data(
            withJSONObject: committedMetrics,
            options: [.sortedKeys]
        )
        let actualMetricData = try JSONSerialization.data(
            withJSONObject: actualMetrics,
            options: [.sortedKeys]
        )
        guard committedMetricData == actualMetricData else {
            FileHandle.standardError.write(
                Data("wire metric IDs, kinds, or canonical units drifted from the spec catalogue\n".utf8)
            )
            exit(1)
        }

        let exceptions = try JSONSerialization.jsonObject(
            with: Data(
                contentsOf: spec.appendingPathComponent(
                    "catalogue/hk-statistics-exceptions.json"
                )
            )
        ) as? [String: Any]
        let exceptionRows = exceptions?["exceptions"] as? [[String: Any]] ?? []
        let committedExceptionIDs = exceptionRows.compactMap { $0["metricId"] as? String }
            .sorted()
        let actualExceptionIDs = MetricCatalog.hkStatisticsExceptions.compactMap {
            MetricCatalog.declaration(for: $0)?.wireId
        }.sorted()
        guard committedExceptionIDs == actualExceptionIDs else {
            FileHandle.standardError.write(
                Data("hkStatistics exception list drifted from its committed golden\n".utf8)
            )
            exit(1)
        }
        let initialADR001: Set<String> = [
            "active_energy", "basal_energy", "cycling_distance", "dietary_water",
            "exercise_time", "flights_climbed", "stand_time", "step_count",
            "walking_running_distance",
        ]
        let decisions = root.appendingPathComponent("docs/02-design/decisions")
        let decisionNames = try FileManager.default.contentsOfDirectory(atPath: decisions.path)
        for row in exceptionRows {
            guard let metricID = row["metricId"] as? String,
                  let adr = row["adr"] as? String,
                  let reason = row["reason"] as? String,
                  !reason.isEmpty,
                  decisionNames.contains(where: { $0.hasPrefix("\(adr)-") })
            else {
                FileHandle.standardError.write(
                    Data("hkStatistics exception lacks a reason or accepted ADR\n".utf8)
                )
                exit(1)
            }
            if adr == "ADR-001", !initialADR001.contains(metricID) {
                FileHandle.standardError.write(
                    Data("new hkStatistics exception reuses the initial ADR\n".utf8)
                )
                exit(1)
            }
        }

        let vectors = try JSONSerialization.jsonObject(
            with: Data(
                contentsOf: spec.appendingPathComponent(
                    "fixtures/hk-statistics-reference-vectors.json"
                )
            )
        ) as? [String: Any]
        let vectorRows = vectors?["vectors"] as? [[String: Any]] ?? []
        let vectorIDs = vectorRows.compactMap { $0["metricId"] as? String }.sorted()
        guard vectors?["kind"] as? String == "synthetic-pipeline-reference",
              vectors?["canonicality"] as? String == "pending-R-87-device-pass",
              vectorIDs == committedExceptionIDs
        else {
            FileHandle.standardError.write(
                Data("hkStatistics Linux reference vectors drifted from the exception list\n".utf8)
            )
            exit(1)
        }

        let frozenMarker = spec.appendingPathComponent("FROZEN")
        if FileManager.default.fileExists(atPath: frozenMarker.path) {
            let frozenURL = spec.appendingPathComponent("schema/ohe.wire.1.frozen.json")
            guard FileManager.default.fileExists(atPath: frozenURL.path) else {
                FileHandle.standardError.write(Data("frozen spec is missing its schema baseline\n".utf8))
                exit(1)
            }
            let frozen = try WireJSONSchema.load(Data(contentsOf: frozenURL))
            if let failure = WireJSONSchema.freezeGate(
                frozen: frozen,
                current: schema,
                markedFrozen: true
            ) {
                FileHandle.standardError.write(Data(("breaking frozen schema change:\n" + failure + "\n").utf8))
                exit(1)
            }
            print("policycheck spec-freeze: ok")
        } else {
            print("policycheck spec-freeze: ok (spec/v1.0.0 not marked FROZEN)")
        }
        try checkG1Fixtures(spec: spec)
        try checkFaultSeamsAbsentOutsideDebug(root: root)
        print("policycheck schema, corpus, receiver, freeze, G1, and R-83 source gate: ok")
    }

    /// QA-09: every committed NDJSON fixture is synthetic. Frozen encoder outputs cannot
    /// grow a batch.header field without breaking G1, so those files carry a sibling
    /// provenance document instead.
    static func checkFixtureProvenance(fixtures: URL) throws {
        var missing: [String] = []
        guard let files = FileManager.default.enumerator(
            at: fixtures,
            includingPropertiesForKeys: nil
        ) else {
            FileHandle.standardError.write(Data("spec fixtures directory missing\n".utf8))
            exit(1)
        }
        for case let file as URL in files where file.pathExtension == "ndjson" {
            if hasInlineSyntheticHeader(file) { continue }
            let sibling = file.deletingPathExtension().appendingPathExtension("provenance.json")
            guard let data = try? Data(contentsOf: sibling),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["synthetic"] as? Bool == true,
                  (json["licence"] as? String)?.uppercased().contains("CC0") == true,
                  json["role"] as? String != nil || json["seed"] != nil
            else {
                missing.append(
                    file.path.replacingOccurrences(of: fixtures.path + "/", with: "")
                )
                continue
            }
        }
        if !missing.isEmpty {
            FileHandle.standardError.write(
                Data(
                    (
                        "QA-09 fixture provenance missing for:\n"
                            + missing.joined(separator: "\n")
                            + "\n"
                    ).utf8
                )
            )
            exit(1)
        }
        print("policycheck fixture provenance headers: ok")
    }

    static func hasInlineSyntheticHeader(_ file: URL) -> Bool {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let first = text.split(whereSeparator: \.isNewline).first,
              let json = try? JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any]
        else {
            return false
        }
        return json["synthetic"] as? Bool == true
    }

    static func checkG1Fixtures(spec: URL) throws {
        let g1 = spec.appendingPathComponent("fixtures/g1")
        let input = try Data(contentsOf: g1.appendingPathComponent("logical-input.json"))
        let artifacts = try FrozenEncoder.artifacts(fromLogicalInput: input)
        if ProcessInfo.processInfo.environment["WRITE_G1"] == "1" {
            try artifacts.ndjson.write(to: g1.appendingPathComponent("expected.ndjson"))
            try artifacts.json.write(to: g1.appendingPathComponent("expected.json"))
            try artifacts.prettyJSON.write(to: g1.appendingPathComponent("expected.pretty.json"))
            let csvDir = g1.appendingPathComponent("expected.csv")
            try FileManager.default.createDirectory(at: csvDir, withIntermediateDirectories: true)
            try artifacts.csvQuantity.write(to: csvDir.appendingPathComponent(artifacts.csvFileName))
            try artifacts.csvMeta.write(to: csvDir.appendingPathComponent("_meta.json"))
        }
        let expectedNDJSON = try Data(contentsOf: g1.appendingPathComponent("expected.ndjson"))
        let expectedJSON = try Data(contentsOf: g1.appendingPathComponent("expected.json"))
        let expectedPretty = try Data(contentsOf: g1.appendingPathComponent("expected.pretty.json"))
        let csvDir = g1.appendingPathComponent("expected.csv")
        let expectedCSV = try Data(contentsOf: csvDir.appendingPathComponent(artifacts.csvFileName))
        let expectedMeta = try Data(contentsOf: csvDir.appendingPathComponent("_meta.json"))
        guard artifacts.ndjson == expectedNDJSON,
              artifacts.json == expectedJSON,
              artifacts.prettyJSON == expectedPretty,
              artifacts.csvQuantity == expectedCSV,
              artifacts.csvMeta == expectedMeta
        else {
            FileHandle.standardError.write(Data("G1 frozen encoder output drifted\n".utf8))
            exit(1)
        }
        try WireJSONSchema.validateNDJSON(
            String(decoding: artifacts.ndjson, as: UTF8.self),
            schema: try WireJSONSchema.load(
                Data(contentsOf: spec.appendingPathComponent("schema/ohe.wire.1.json"))
            )
        )
        let tzIdentity = try String(
            contentsOf: spec.appendingPathComponent("fixtures/tz-database-version.txt"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard tzIdentity == "2024a" else {
            FileHandle.standardError.write(Data("injected tz-database identity must stay 2024a\n".utf8))
            exit(1)
        }
        print("policycheck G1 fixtures and injected tzdata identity: ok")
    }

    static func checkFaultSeamsAbsentOutsideDebug(root: URL) throws {
        let engine = root.appendingPathComponent("Sources/CorrectnessEngine")
        guard let files = FileManager.default.enumerator(at: engine, includingPropertiesForKeys: nil) else {
            FileHandle.standardError.write(Data("CorrectnessEngine missing\n".utf8))
            exit(1)
        }
        var hits: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let stripped = withoutDebugCompilationBlocks(text)
            if stripped.contains("ExportFaultLocation") || stripped.contains("ExportFaultInjector") {
                hits.append(file.path)
            }
        }
        if !hits.isEmpty {
            FileHandle.standardError.write(
                Data(("R-83 fault seams visible outside #if DEBUG:\n" + hits.joined(separator: "\n") + "\n").utf8)
            )
            exit(1)
        }
        print("policycheck R-83 seams stay inside DEBUG: ok")
    }

    static func withoutDebugCompilationBlocks(_ text: String) -> String {
        var emitted = ""
        var stack: [Bool] = []
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#if DEBUG") {
                stack.append(true)
                continue
            }
            if trimmed.hasPrefix("#if") {
                stack.append(false)
                continue
            }
            if trimmed.hasPrefix("#endif") {
                if !stack.isEmpty { _ = stack.removeLast() }
                continue
            }
            if stack.contains(true) { continue }
            emitted.append(contentsOf: line)
            emitted.append("\n")
        }
        return emitted
    }

    static func checkAdjacency(root: URL) throws {
        let expectedURL = root.appendingPathComponent("spec/v1.0.0/adjacency.json")
        let expectedData = try Data(contentsOf: expectedURL)
        let expected = try JSONSerialization.jsonObject(with: expectedData)
        let dumped = try dumpPackageJSON(root: root)
        let actual = try adjacencyManifest(fromDump: dumped)
        let expectedObject = expected as? [String: Any]
        guard
            let expectedTargets = expectedObject?["targets"] as? [[String: Any]],
            let actualTargets = actual["targets"] as? [[String: Any]]
        else {
            FileHandle.standardError.write(Data("adjacency manifest shape mismatch\n".utf8))
            exit(1)
        }
        let expectedNorm = try canonicalJSON(expectedTargets)
        let actualNorm = try canonicalJSON(actualTargets)
        if expectedNorm != actualNorm {
            FileHandle.standardError.write(
                Data(
                    "adjacency drift vs spec/v1.0.0/adjacency.json\nexpected:\n\(expectedNorm)\nactual:\n\(actualNorm)\n".utf8
                )
            )
            exit(1)
        }
        print("policycheck adjacency matches dump-package: ok")
    }

    /// R-115 in-repo stack: Classic Grafana dashboard plus compose. Catalogue upload is external.
    static func checkReceiverQuickstart(root: URL) throws {
        let compose = root.appendingPathComponent("receiver/compose.yaml")
        let dashboard = root.appendingPathComponent("receiver/grafana/dashboards/ohe-receiver.json")
        let readme = root.appendingPathComponent("receiver/README.md")
        for url in [compose, dashboard, readme] {
            guard FileManager.default.fileExists(atPath: url.path) else {
                FileHandle.standardError.write(Data("R-115 missing \(url.path)\n".utf8))
                exit(1)
            }
        }
        let composeText = try String(contentsOf: compose, encoding: .utf8)
        if !composeText.contains("grafana") || !composeText.contains("prometheus") {
            FileHandle.standardError.write(Data("R-115 compose.yaml must run Grafana and Prometheus\n".utf8))
            exit(1)
        }
        let data = try Data(contentsOf: dashboard)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let schemaVersion = json["schemaVersion"] as? Int,
            let title = json["title"] as? String,
            let description = json["description"] as? String
        else {
            FileHandle.standardError.write(Data("R-115 dashboard JSON is missing Classic fields\n".utf8))
            exit(1)
        }
        if schemaVersion < 30 || schemaVersion > 38 {
            FileHandle.standardError.write(
                Data("R-115 dashboard schemaVersion \(schemaVersion) is not Classic (30–38)\n".utf8)
            )
            exit(1)
        }
        if title.isEmpty {
            FileHandle.standardError.write(Data("R-115 dashboard title is empty\n".utf8))
            exit(1)
        }
        let disclaimer = try String(
            contentsOf: root.appendingPathComponent("compliance/disclaimer.txt"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.contains(disclaimer) {
            FileHandle.standardError.write(
                Data("R-115 dashboard description is missing the canonical disclaimer\n".utf8)
            )
            exit(1)
        }
        let readmeText = try String(contentsOf: readme, encoding: .utf8)
        if !readmeText.contains("docker compose up") {
            FileHandle.standardError.write(Data("receiver/README.md must document docker compose up\n".utf8))
            exit(1)
        }
        if readmeText.lowercased().contains("published to the grafana") {
            FileHandle.standardError.write(
                Data("do not claim the Grafana catalogue listing; that upload is external\n".utf8)
            )
            exit(1)
        }
        print("policycheck R-115 compose and Classic dashboard: ok")
    }

    static func dumpPackageJSON(root: URL) throws -> Any {
        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "package", "dump-package"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            FileHandle.standardError.write(Data("swift package dump-package failed: \(err)\n".utf8))
            exit(1)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func adjacencyManifest(fromDump dump: Any) throws -> [String: Any] {
        let darwinOnly: Set<String> = ["HealthKitSource", "HealthKitSourceTests"]
        guard let package = dump as? [String: Any],
              let targets = package["targets"] as? [[String: Any]]
        else {
            throw AdjacencyError.unreadableDump
        }
        var rows: [[String: Any]] = []
        for target in targets {
            guard let name = target["name"] as? String else { continue }
            if darwinOnly.contains(name) { continue }
            var deps: [String] = []
            if let dependencies = target["dependencies"] as? [[String: Any]] {
                for dependency in dependencies {
                    if let byName = dependency["byName"] as? [Any], let first = byName.first as? String {
                        deps.append(first)
                    } else if let product = dependency["product"] as? [Any], let first = product.first as? String {
                        deps.append(first)
                    } else if let targetName = dependency["target"] as? [Any], let first = targetName.first as? String {
                        deps.append(first)
                    }
                }
            }
            rows.append([
                "name": name,
                "type": target["type"] as? String ?? "regular",
                "dependencies": deps.sorted(),
            ])
        }
        rows.sort { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
        return ["package": "open-health-exporter", "targets": rows]
    }

    static func canonicalJSON(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum AdjacencyError: Error {
    case unreadableDump
}
