// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import EnginePorts
import Foundation
import MetricCatalog
import Testing
import Watchdog

/// #54: copy that `Sources/` owns reaches the app as catalog keys. This is the CI
/// check that none of it is missing from `Apps/Localizable.xcstrings` and that the
/// catalog holds nothing Sources no longer produces.
private let catalogMarker = "Sources copy (LocalizedCopy)"

private func catalogStrings() throws -> [String: [String: Any]] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Apps/Localizable.xcstrings")
    let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    return try #require(json["strings"] as? [String: [String: Any]])
}

private func flatten(_ copy: LocalizedCopy) -> [LocalizedCopy] {
    [copy] + copy.arguments.flatMap { argument -> [LocalizedCopy] in
        if case let .copy(inner) = argument { flatten(inner) } else { [] }
    }
}

private func event(_ kind: RunOutcome.Kind, errorClass: String?, trigger: RunTrigger, records: Int) -> RunEvent {
    var facts = RunHistoryFacts.empty
    facts.destinationID = "local-file"
    return RunEvent(
        runID: RunID(rawValue: "r"),
        outcomeKind: kind.rawValue,
        detail: "",
        trigger: trigger,
        samplesCommitted: records,
        wallTimeEpoch: 1,
        errorClass: errorClass,
        facts: facts
    )
}

/// Every fixed or parameterised sentence the live screens take from `Sources/`.
private func producedCopy() -> [LocalizedCopy] {
    var copy: [LocalizedCopy] = [
        HealthAuthorizationPriming.title, HealthAuthorizationPriming.continueTitle,
        HealthAuthorizationPriming.sheetFollows, HealthAuthorizationPriming.invisibility,
        About.copyright, About.licence, About.warranty, About.medical,
        About.versionLine(version: "1", build: "1", commit: "unspecified"),
        About.versionLine(version: "1", build: "1", commit: "0123456789"),
    ]
    copy += (0...2).map(HealthAuthorizationPriming.typeCountCopy)
    copy += About.links.map(\.title)

    let classes: [String?] = ErrorClass.allCases.map(\.rawValue) + [nil]
    for kind in RunOutcome.Kind.allCases {
        for errorClass in classes {
            for records in 0...2 {
                let row = HistoryPresentation.row(event(kind, errorClass: errorClass, trigger: .manual, records: records))
                copy += [row.result]
            }
        }
    }
    copy += RunTrigger.allCases.map(HistoryPresentation.trigger)
    let delivered = event(.success, errorClass: nil, trigger: .manual, records: 1)
    for count in 1...2 {
        copy.append(HistoryPresentation.emptyCopy(Array(repeating: delivered, count: count), filter: .problems))
    }
    copy.append(HistoryPresentation.emptyCopy([], filter: .problems))

    for state in DestinationDisplayState.allCases {
        for errorClass in classes {
            for lastSuccess in [nil, 1_000.0] as [TimeInterval?] {
                let snapshot = DestinationStatusSnapshot(
                    destinationID: "d", destinationLabel: "Archive", enabled: true, state: state,
                    lastSuccessEpoch: lastSuccess, errorClass: errorClass, writtenAtEpoch: 2_000
                )
                let rows = StatusDashboard.rows([snapshot], nowEpoch: 2_000) { _ in "5 min ago" }
                copy += rows.map(\.detail)
                for extra in [[], rows] {
                    copy.append(StatusDashboard.summary(rows + extra, lastSuccessEpoch: lastSuccess) { _ in "5 min ago" }.detail)
                    copy.append(StatusDashboard.summary(rows + extra, lastSuccessEpoch: lastSuccess) { _ in "5 min ago" }.headline)
                }
            }
        }
    }
    var changed = DestinationStatusSnapshot(destinationID: "d", destinationLabel: "A", enabled: true, writtenAtEpoch: 2)
    changed.unacknowledgedSecurityEventCount = 1
    copy += StatusDashboard.rows([changed], nowEpoch: 2) { _ in "" }.map(\.detail)
    copy.append(StatusDashboard.summary([], lastSuccessEpoch: nil) { _ in "" }.headline)
    copy.append(StatusDashboard.summary([], lastSuccessEpoch: nil) { _ in "" }.detail)
    copy += DestinationDisplayState.allCases.map { LocalizedCopy(verbatimKey: $0.label) }
    copy.append("All destinations")
    copy += UserFacingFixAction.allCases.map { LocalizedCopy(verbatimKey: $0.label) }

    let evidence = [
        UserFacingErrorEvidence(),
        UserFacingErrorEvidence(statusCode: 503, bytesSent: 1, retryAfterSeconds: 1),
        UserFacingErrorEvidence(statusCode: 413, bytesSent: 2, retryAfterSeconds: 2),
        UserFacingErrorEvidence(bytesSent: 0, retryAfterSeconds: 0),
    ]
    for archetype in UserFacingErrorArchetype.allCases {
        for evidence in evidence {
            let error = UserFacingErrorObject.make(archetype: archetype, destinationLabel: "Archive", evidence: evidence)
            copy += [error.title, error.cause, error.fix]
        }
    }
    return copy.flatMap(flatten)
}

@Test func everyCopyKeyFromSourcesIsInTheCatalogAndNoneIsStale() throws {
    let strings = try catalogStrings()
    let keys = Set(producedCopy().map(\.key))
    #expect(keys.count > 30)
    let missing = keys.subtracting(strings.keys).sorted()
    #expect(missing.isEmpty, "not in Apps/Localizable.xcstrings: \(missing)")
    let tagged = Set(strings.filter { $0.value["comment"] as? String == catalogMarker }.keys)
    let stale = tagged.subtracting(keys).sorted()
    #expect(stale.isEmpty, "stale Sources entries in the catalog: \(stale)")
    for (key, entry) in strings where tagged.contains(key) {
        let units = (entry["localizations"] as? [String: Any])?["en"] as? [String: Any]
        #expect(units != nil, "\(key) has no English localisation")
    }
}

/// Substitutes arguments into a catalog template the way the app's formatter does.
private func render(_ template: String, _ arguments: [LocalizedCopy.Argument]) -> String {
    var result = template
    for argument in arguments {
        let (token, value): (String, String) = switch argument {
        case let .text(text): ("%@", text)
        case let .number(number): ("%lld", number.formatted())
        case let .copy(inner): ("%@", inner.english)
        }
        if let range = result.range(of: token) { result.replaceSubrange(range, with: value) }
    }
    return result
}

@Test func pluralCopyHasCatalogVariantsAndEnglishForZeroOneAndTwo() throws {
    let strings = try catalogStrings()
    let plurals = producedCopy().filter(\.isPlural)
    #expect(Set(plurals.map(\.key)).count >= 5)
    for copy in plurals {
        let key = copy.key
        let english = try #require((strings[key]?["localizations"] as? [String: Any])?["en"] as? [String: Any])
        let variations = try #require(english["variations"] as? [String: Any], "\(key)")
        let plural = try #require(variations["plural"] as? [String: [String: Any]], "\(key)")
        #expect(Set(plural.keys) == ["one", "other"], "\(key)")
        func text(_ category: String) -> String {
            (plural[category]?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
        }
        let first = copy.arguments.compactMap { argument -> Int? in
            if case let .number(number) = argument { number } else { nil }
        }.first
        let form = first == 1 ? "one" : "other"
        #expect(copy.english == render(text(form), copy.arguments), "\(key) as \(form)")
    }
    let counts = (0...2).map { HealthAuthorizationPriming.typeCountCopy($0).english }
    #expect(counts[0].contains("0 types"))
    #expect(counts[1].contains("1 type of"))
    #expect(counts[2].contains("2 types"))
}
