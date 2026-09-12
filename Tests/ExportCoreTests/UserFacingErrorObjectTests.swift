// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Testing

@Test func everyUserFacingErrorArchetypeHasFivePartsAndOwnedFixes() {
    #expect(UserFacingErrorArchetype.allCases.count == 15)
    for archetype in UserFacingErrorArchetype.allCases {
        let error = UserFacingErrorObject.make(
            archetype: archetype,
            destinationLabel: "homeassistant.local",
            evidence: UserFacingErrorEvidence(
                statusCode: 413,
                method: "POST",
                host: "homeassistant.local",
                path: "/api/webhook/abcdef0123456789",
                bytesSent: 8_400_000,
                retryAfterSeconds: 900,
                traceID: "4f2a91c8",
                buildHash: "a91c8e"
            )
        )
        #expect(!error.title.isEmpty)
        #expect(!error.cause.isEmpty)
        #expect(!error.fix.isEmpty)
        #expect((1...2).contains(error.actions.count))
        #expect(error.lines.count == 5)
        #expect(error.lines[0].hasPrefix("①"))
        #expect(error.lines[1].hasPrefix("②"))
        #expect(error.lines[2].hasPrefix("③"))
        #expect(error.lines[3].hasPrefix("④"))
        #expect(error.lines[4].hasPrefix("⑤"))
        #expect(error.copyDiagnostics.contains("Copy diagnostics"))
        #expect(!error.title.contains("401") || archetype == .http401)
        #expect(!error.title.hasPrefix("Error"))
        let blob = ([error.title, error.cause, error.fix, error.copyDiagnostics] + error.actions.map(\.label))
            .joined(separator: "\n")
        #expect(UserFacingErrorCopy.violations(in: blob).isEmpty)
        #expect(!blob.localizedCaseInsensitiveContains("please try again"))
        #expect(!blob.localizedCaseInsensitiveContains("sync"))
        #expect(!error.copyDiagnostics.contains("Bearer"))
        #expect(!error.copyDiagnostics.contains("abcdef0123456789"))
    }

    #expect(
        UserFacingErrorObject.make(archetype: .http413, destinationLabel: "nas")
            .actions.contains(.shortenWindow)
    )
    #expect(
        UserFacingErrorObject.make(archetype: .http429, destinationLabel: "nas")
            .actions.contains(.lowerFreshness)
    )
    #expect(
        UserFacingErrorObject.make(archetype: .mqttQoS0, destinationLabel: "broker")
            .actions.contains(.setQoS1)
    )
    #expect(UserFacingErrorArchetype.fromHTTPStatus(413) == .http413)
    #expect(UserFacingErrorArchetype.fromHTTPStatus(429) == .http429)
    #expect(UserFacingErrorArchetype.fromHTTPStatus(502) == .http5xx)
    #expect(
        UserFacingErrorObject.make(archetype: .healthLocked, destinationLabel: "Health")
            .nonActionable
    )
}

@Test func applyingOwnedFixesResolves413429AndQoS0() {
    var settings = OwnedExportSettings(windowHours: 24, freshnessIntervalMinutes: 15, mqttQoS: 0)
    let before413 = settings
    UserFacingFixApplier.apply(.shortenWindow, to: &settings)
    #expect(
        UserFacingFixApplier.http413Resolved(
            bytesSent: 3_600_000,
            fromHours: before413.windowHours,
            toHours: settings.windowHours,
            serverLimitBytes: 1_000_000
        )
    )

    settings = OwnedExportSettings(windowHours: 24, freshnessIntervalMinutes: 15, mqttQoS: 0)
    let before429 = settings
    UserFacingFixApplier.apply(.lowerFreshness, to: &settings)
    #expect(
        UserFacingFixApplier.http429Resolved(
            fromMinutes: before429.freshnessIntervalMinutes,
            toMinutes: settings.freshnessIntervalMinutes,
            retryAfterMinutes: 30
        )
    )

    settings = OwnedExportSettings(mqttQoS: 0)
    let beforeQoS = settings.mqttQoS
    UserFacingFixApplier.apply(.setQoS1, to: &settings)
    #expect(UserFacingFixApplier.mqttQoS0Resolved(from: beforeQoS, to: settings.mqttQoS))
    #expect(
        UserFacingErrorArchetype.fromErrorClass(.deviceLocked) == .healthLocked
    )
}

@Test func errorClassManifestCopyAvoidsUX28Phrases() {
    for errorClass in ErrorClass.allCases {
        let copy = ErrorClassManifest.record(for: errorClass).userFacingCopy
        #expect(UserFacingErrorCopy.violations(in: copy).isEmpty)
    }
}
