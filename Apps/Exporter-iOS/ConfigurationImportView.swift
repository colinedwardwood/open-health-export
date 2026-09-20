// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationImportView: View {
    let refreshToken: Int
    let onConfigure: (ImportedDestinationDraftRecord) -> Void
    @State private var showingImporter = false
    @State private var review: DestinationConfigurationImportReview?
    @State private var confirmation = ""
    @State private var status = ""
    @State private var drafts: [ImportedDestinationDraftRecord] = []

    private let tributaryType = UTType(filenameExtension: "tributary") ?? .json

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configuration portability")
                .wrappingFillCaption()
                .fontWeight(.semibold)
                .accessibilityIdentifier("configuration-import-heading")
            Text("Imports never contain credentials and cannot replace or enable an existing destination.")
                .wrappingFillCaption()
                .accessibilityIdentifier("configuration-import-limits")
            Button {
                showingImporter = true
            } label: {
                Text("Review a .tributary configuration")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("configuration-import")

            if let review {
                Text("Review before importing")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                ForEach(
                    Array(review.destinations.enumerated()),
                    id: \.offset
                ) { _, destination in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(destination.displayName)
                        Text("\(destination.kind.rawValue): \(destination.endpoint)")
                            .wrappingFillCaption()
                        Text("\(destination.exportScope.metrics.count) metric grants; credentials omitted")
                            .wrappingFillCaption()
                    }
                }
                TextField(
                    "Type \(DestinationConfigurationImportReview.confirmationPhrase)",
                    text: $confirmation
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .accessibilityIdentifier("configuration-import-confirmation")
                confirmationHygiene
                Button {
                    confirm(review)
                } label: {
                    Text("Create disabled destination drafts")
                        .wrappingActionLabel()
                }
                .buttonStyle(.plain)
                .disabled(
                    CredentialFieldHygiene.secret(confirmation).normalized
                        != DestinationConfigurationImportReview.confirmationPhrase
                )
                .accessibilityIdentifier("configuration-import-create-drafts")
            }
            if !drafts.isEmpty {
                Text("Disabled imported drafts")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                ForEach(drafts, id: \.localIdentifier) { draft in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.configuration.displayName)
                        Text(
                            "\(draft.configuration.kind.rawValue): "
                                + draft.configuration.endpoint
                        )
                        .wrappingFillCaption()
                        Text("Disabled — destination test required")
                            .wrappingFillCaption()
                        if draft.configuration.kind == .https
                            || draft.configuration.kind == .homeAssistant
                            || draft.configuration.kind == .mqtt {
                            Button {
                                onConfigure(draft)
                            } label: {
                                Text("Add credentials and test")
                                    .wrappingActionLabel()
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(
                                "configuration-import-configure-\(draft.configuration.kind.rawValue)"
                            )
                        } else if draft.configuration.kind == .companion {
                            Button {
                                onConfigure(draft)
                            } label: {
                                Text("Add pairing and test")
                                    .wrappingActionLabel()
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(
                                "configuration-import-configure-\(draft.configuration.kind.rawValue)"
                            )
                        } else {
                            Text("This destination kind does not yet have an import setup path.")
                                .wrappingFillCaption()
                                .accessibilityIdentifier(
                                    "configuration-import-unsupported-\(draft.configuration.kind.rawValue)"
                                )
                        }
                        Button {
                            discard(draft.localIdentifier)
                        } label: {
                            Text("Discard draft")
                                .wrappingActionLabel()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "configuration-import-discard-\(draft.localIdentifier)"
                        )
                    }
                }
            }
            if !status.isEmpty {
                Text(status)
                    .wrappingFillCaption()
                    .accessibilityIdentifier("configuration-import-status")
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [tributaryType],
            allowsMultipleSelection: false
        ) { result in
            load(result)
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment[
                "OHE_SEED_IMPORTED_DRAFT"
            ] == "https" {
                try? ImportedDestinationDraftStore.seedHTTPSForUITests()
            }
            if ProcessInfo.processInfo.environment[
                "OHE_SEED_IMPORTED_DRAFT"
            ] == "companion" {
                try? ImportedDestinationDraftStore.seedCompanionForUITests()
            }
            if ProcessInfo.processInfo.environment[
                "OHE_SEED_IMPORTED_DRAFT"
            ] == "local-file" {
                try? ImportedDestinationDraftStore.seedLocalFileForUITests()
            }
            if ProcessInfo.processInfo.environment[
                "OHE_SEED_IMPORTED_DRAFT"
            ] == "home-assistant" {
                try? ImportedDestinationDraftStore.seedHomeAssistantForUITests()
            }
            #endif
            reloadDrafts()
        }
        .onChange(of: refreshToken) { _, _ in reloadDrafts() }
    }

    private func load(_ result: Result<[URL], any Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            review = try DestinationConfigurationDocument.reviewImport(
                Data(contentsOf: url)
            )
            confirmation = ""
            status = "Review every endpoint and metric grant before importing."
        } catch {
            review = nil
            status = "Configuration refused: \(error.localizedDescription)"
        }
    }

    private func confirm(_ review: DestinationConfigurationImportReview) {
        do {
            let confirmed = try review.confirm(
                typedConfirmation: CredentialFieldHygiene.secret(confirmation).normalized
            )
            let count = try ImportedDestinationDraftStore.append(confirmed)
            reloadDrafts()
            self.review = nil
            confirmation = ""
            status = "\(confirmed.drafts.count) disabled draft(s) created; \(count) total. Add credentials and pass the destination test before enabling each one."
        } catch {
            status = "Configuration refused: \(error.localizedDescription)"
        }
    }

    private func reloadDrafts() {
        do {
            drafts = try ImportedDestinationDraftStore.load()
        } catch {
            drafts = []
            status = "Stored drafts could not be read: \(error.localizedDescription)"
        }
    }

    private func discard(_ localIdentifier: String) {
        do {
            try ImportedDestinationDraftStore.remove(
                localIdentifier: localIdentifier
            )
            reloadDrafts()
            status = "Disabled draft discarded."
        } catch {
            status = "Draft could not be discarded: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var confirmationHygiene: some View {
        let hygiene = CredentialFieldHygiene.secret(confirmation)
        if hygiene.strippedWhitespace {
            Text(CredentialFieldHygiene.whitespaceNote)
                .wrappingFillCaption()
                .accessibilityIdentifier("configuration-import-confirmation-whitespace")
        }
        if hygiene.replacedSmartPunctuation {
            Text(CredentialFieldHygiene.smartPunctuationNote)
                .wrappingFillCaption()
                .accessibilityIdentifier("configuration-import-confirmation-smartquotes")
        }
    }
}

struct ImportedDestinationDraftRecord: Codable, Equatable {
    let localIdentifier: String
    let configuration: PortableDestinationConfiguration
    let state: String
}

enum ImportedDestinationDraftStore {
    #if DEBUG
    static func seedHTTPSForUITests() throws {
        try replaceStore(
            with: try PortableDestinationConfiguration(
                sourceIdentifier: "seed-https",
                displayName: "Imported HTTPS",
                kind: .https,
                endpoint: "https://collector.example/upload",
                settings: ["method": "POST"],
                exportScope: PortableDestinationExportScope(
                    metrics: [MetricID(rawValue: "heart_rate")],
                    startInclusive: Date(timeIntervalSince1970: 1)
                )
            )
        )
    }

    static func seedCompanionForUITests() throws {
        HarnessExport.resetCompanionSlotForUITests()
        try replaceStore(
            with: try PortableDestinationConfiguration(
                sourceIdentifier: "seed-companion",
                displayName: "Imported Mac",
                kind: .companion,
                endpoint: "OHE Lab Mac._ohe-companion._tcp",
                settings: ["serviceName": "OHE Lab Mac._ohe-companion._tcp"],
                exportScope: PortableDestinationExportScope(
                    metrics: [MetricID(rawValue: "heart_rate")],
                    startInclusive: Date(timeIntervalSince1970: 1)
                )
            )
        )
    }

    static func seedLocalFileForUITests() throws {
        try writeUnsupportedKindSeed(
            sourceIdentifier: "seed-local-file",
            displayName: "Imported archive",
            kind: .localFile,
            endpoint: "archive"
        )
    }

    static func seedHomeAssistantForUITests() throws {
        try writeUnsupportedKindSeed(
            sourceIdentifier: "seed-home-assistant",
            displayName: "Imported Home Assistant",
            kind: .homeAssistant,
            endpoint: "http://homeassistant.local:8123",
            settings: [
                "allowInsecureHTTP": "true",
                "mode": "webhook",
            ]
        )
    }

    private static func writeUnsupportedKindSeed(
        sourceIdentifier: String,
        displayName: String,
        kind: PortableDestinationKind,
        endpoint: String,
        settings: [String: String] = [:]
    ) throws {
        try replaceStore(
            with: try PortableDestinationConfiguration(
                sourceIdentifier: sourceIdentifier,
                displayName: displayName,
                kind: kind,
                endpoint: endpoint,
                settings: settings,
                exportScope: PortableDestinationExportScope(
                    metrics: [MetricID(rawValue: "heart_rate")],
                    startInclusive: Date(timeIntervalSince1970: 1)
                )
            )
        )
    }

    private static func replaceStore(
        with configuration: PortableDestinationConfiguration
    ) throws {
        let review = try DestinationConfigurationDocument(
            destinations: [configuration]
        )
        .encoded()
        let confirmed = try DestinationConfigurationDocument
            .reviewImport(review)
            .confirm(
                typedConfirmation:
                    DestinationConfigurationImportReview.confirmationPhrase
            )
        let records = confirmed.drafts.map {
            ImportedDestinationDraftRecord(
                localIdentifier: configuration.sourceIdentifier,
                configuration: $0.configuration,
                state: $0.state.rawValue
            )
        }
        try write(records, to: try fileURL())
    }
    #endif

    static func append(_ importValue: ConfirmedDestinationConfigurationImport) throws -> Int {
        let file = try fileURL()
        let existing = try load()
        let additions = importValue.drafts.map {
            ImportedDestinationDraftRecord(
                localIdentifier: UUID().uuidString,
                configuration: $0.configuration,
                state: $0.state.rawValue
            )
        }
        try write(existing + additions, to: file)
        return existing.count + additions.count
    }

    static func load() throws -> [ImportedDestinationDraftRecord] {
        let file = try fileURL()
        guard FileManager.default.fileExists(atPath: file.path) else {
            return []
        }
        return try JSONDecoder().decode(
            [ImportedDestinationDraftRecord].self,
            from: Data(contentsOf: file)
        )
    }

    static func remove(localIdentifier: String) throws {
        let remaining = try load().filter {
            $0.localIdentifier != localIdentifier
        }
        try write(remaining, to: try fileURL())
    }

    private static func write(
        _ records: [ImportedDestinationDraftRecord],
        to file: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(records).write(
            to: file,
            options: [
                .atomic,
                .completeFileProtectionUntilFirstUserAuthentication,
            ]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = file
        try mutable.setResourceValues(values)
    }

    static func fileURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent(
            "OpenHealthExporter",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [
                .protectionKey: FileProtectionType
                    .completeUntilFirstUserAuthentication
            ]
        )
        return directory.appendingPathComponent(
            "imported-destination-drafts.json"
        )
    }
}
