import Foundation

@main
struct PolicyCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
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
            if text.contains(platformSecurity), !allowedNetwork.contains(target) {
                violations.append("\(file.path): \(platformSecurity)")
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
        if let appFiles = FileManager.default.enumerator(at: apps, includingPropertiesForKeys: nil) {
            for case let file as URL in appFiles where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                for token in ["URLSession", "NWConnection", "NWListener", "NWBrowser"]
                    where text.contains(token) {
                    appNetworkBypasses.append("\(file.path): \(token)")
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
        ] where !exporterInfoText.contains(required) {
            FileHandle.standardError.write(
                Data("iOS background task configuration is missing \(required)\n".utf8)
            )
            exit(1)
        }
        print("policycheck iOS background task identifiers: ok")
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
        try checkAdjacency(root: root)
        try checkHealthKitSymbolsStayInAdapter(sources: sources)
        try checkSpecArtifacts(root: root)
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

    static func checkSpecArtifacts(root: URL) throws {
        let spec = root.appendingPathComponent("spec/v1.0.0")
        for relative in ["README.md", "adjacency.json", "fixtures/fix-catalogue.json"] {
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
        if FileManager.default.fileExists(atPath: spec.appendingPathComponent("FROZEN").path) {
            FileHandle.standardError.write(
                Data("spec/v1.0.0 is marked FROZEN; freeze diffs are not implemented in this check\n".utf8)
            )
            exit(1)
        }
        print("policycheck spec artifacts parse and remain unfrozen: ok")
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
