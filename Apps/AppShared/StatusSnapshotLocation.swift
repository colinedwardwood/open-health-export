// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Watchdog

enum StatusSnapshotLocation {
    static var appGroupIdentifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "OHEAppGroupIdentifier") as? String
    }

    /// The shared container is what the widget reads, so that is where status belongs
    /// when it exists. When it does not — an unsigned build, a missing entitlement —
    /// the app still has to be able to show its own last success and last failure.
    /// Going blank there would hide exactly the silent failure this surface exists to
    /// reveal, so fall back to the app's own storage rather than showing nothing.
    static func directory(fileManager: FileManager = .default) -> URL? {
        if let appGroupIdentifier, !appGroupIdentifier.isEmpty,
           let shared = fileManager
           .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        {
            return shared.appendingPathComponent("DestinationStatus", isDirectory: true)
        }
        return try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("DestinationStatus", isDirectory: true)
    }

    static func url(
        destinationID: String,
        fileManager: FileManager = .default
    ) -> URL? {
        directory(fileManager: fileManager)?
            .appendingPathComponent(safeFilename(destinationID) + ".json")
    }

    static func readAll(fileManager: FileManager = .default) -> [DestinationStatusSnapshot] {
        guard let directory = directory(fileManager: fileManager),
              let files = try? fileManager.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil
              )
        else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? DestinationSnapshotFile.read(from: $0) }
            .sorted { $0.destinationLabel.localizedStandardCompare($1.destinationLabel) == .orderedAscending }
    }

    private static func safeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let safe = String(scalars)
        return safe.isEmpty ? "destination" : safe
    }
}
