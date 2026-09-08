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
    }
}
