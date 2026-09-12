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
                .font(.headline)
            Text("Imports never contain credentials and cannot replace or enable an existing destination.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Button("Review a .tributary configuration") {
                showingImporter = true
            }
            .frame(minHeight: 44)
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
                            .font(.footnote)
                        Text("\(destination.exportScope.metrics.count) metric grants; credentials omitted")
                            .font(.footnote)
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
                Button("Create disabled destination drafts") {
                    confirm(review)
                }
                .disabled(
                    confirmation
                        != DestinationConfigurationImportReview.confirmationPhrase
                )
                .frame(minHeight: 44)
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
                        .font(.footnote)
                        Text("Disabled — destination test required")
                            .font(.footnote)
                        if draft.configuration.kind == .https
                            || draft.configuration.kind == .mqtt {
                            Button("Add credentials and test") {
                                onConfigure(draft)
                            }
                            .accessibilityIdentifier(
                                "configuration-import-configure-\(draft.localIdentifier)"
                            )
                        } else {
                            Text("This destination kind does not yet have an import setup path.")
                                .font(.footnote)
                        }
                        Button("Discard draft") {
                            discard(draft.localIdentifier)
                        }
                        .accessibilityIdentifier(
                            "configuration-import-discard-\(draft.localIdentifier)"
                        )
                    }
                }
            }
            if !status.isEmpty {
                Text(status)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
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
            let confirmed = try review.confirm(typedConfirmation: confirmation)
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
}

struct ImportedDestinationDraftRecord: Codable, Equatable {
    let localIdentifier: String
    let configuration: PortableDestinationConfiguration
    let state: String
}

enum ImportedDestinationDraftStore {
    #if DEBUG
    static func seedHTTPSForUITests() throws {
        guard try load().isEmpty else { return }
        let configuration = try PortableDestinationConfiguration(
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
        _ = try append(confirmed)
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
