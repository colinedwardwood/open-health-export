import Foundation
import MetricCatalog
import WireFormat

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
        try checkHealthKitSymbolsStayInAdapter(sources: sources)
        try checkSpecArtifacts(root: root)
        try checkHostTZDataPin(root: root)
    }

    static func checkStringCatalog(root: URL) throws {
        let catalogURL = root.appendingPathComponent("Apps/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            json["sourceLanguage"] as? String == "en",
            let strings = json["strings"] as? [String: Any]
        else {
            FileHandle.standardError.write(Data("Apps/Localizable.xcstrings is missing or not English\n".utf8))
            exit(1)
        }
        let shipped = ["en"]
        for language in shipped {
            var translated = 0
            for value in strings.values {
                let entry = value as? [String: Any]
                let locales = entry?["localizations"] as? [String: Any]
                let unit = (locales?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                if unit?["state"] as? String == "translated" || unit?["state"] as? String == "needs_review" {
                    translated += 1
                }
            }
            let ratio = strings.isEmpty ? 0.0 : Double(translated) / Double(strings.count)
            if ratio < 0.95 {
                FileHandle.standardError.write(
                    Data("string catalog \(language) completeness \(ratio) is below 0.95\n".utf8)
                )
                exit(1)
            }
        }

        let apps = root.appendingPathComponent("Apps")
        let patterns = [
            #"(?:Text|Button|Label|TextField|SecureField|Toggle|Section|Picker|navigationTitle|configurationDisplayName|description)\(\s*"([^"\\]*)""#,
            #"\? "([^"\\]*)" : "([^"\\]*)""#,
            #"\?\? "([^"\\]*)""#,
            #"case \.[A-Za-z]+: "([^"\\]*)""#,
        ].map { try! NSRegularExpression(pattern: $0) }
        var missing: [String] = []
        if let files = FileManager.default.enumerator(at: apps, includingPropertiesForKeys: nil) {
            for case let file as URL in files where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                let ns = text as NSString
                let range = NSRange(location: 0, length: ns.length)
                for pattern in patterns {
                    for match in pattern.matches(in: text, range: range) {
                        for index in 1 ..< match.numberOfRanges {
                            let captured = match.range(at: index)
                            guard captured.location != NSNotFound else { continue }
                            let key = ns.substring(with: captured)
                            if key.isEmpty { continue }
                            if key == key.lowercased() { continue }
                            if strings[key] == nil {
                                missing.append("\(file.lastPathComponent): \(key)")
                            }
                        }
                    }
                }
            }
        }
        if !missing.isEmpty {
            FileHandle.standardError.write(Data((missing.joined(separator: "\n") + "\n").utf8))
            exit(1)
        }
        print("policycheck string catalog covers app UI literals: ok")
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
            "Apps/Exporter-iOS/HarnessView.swift",
            "Apps/Localizable.xcstrings",
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
        print("policycheck governance artifacts: ok")
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
        let expected = try String(contentsOf: pinURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let observed = TimeZone.timeZoneDataVersion
        guard observed == expected else {
            FileHandle.standardError.write(
                Data(
                    (
                        "host tzdata drift on \(platform): expected \(expected), "
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
            let mosquitto = pins["mosquittoTag"] as? String, !mosquitto.isEmpty
        else {
            FileHandle.standardError.write(Data("ha-ci/versions.json is missing required pins\n".utf8))
            exit(1)
        }
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/container-contracts.yml"),
            encoding: .utf8
        )
        for token in [current, oldest, mosquitto] where !workflow.contains(token) {
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
            "sample.stateOfMind", "series.ecgVoltage", "sample.audiogram", "medicationDose",
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
