import Foundation
import Watchdog

enum StatusSnapshotLocation {
    static var appGroupIdentifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "OHEAppGroupIdentifier") as? String
    }

    static func directory(fileManager: FileManager = .default) -> URL? {
        guard let appGroupIdentifier, !appGroupIdentifier.isEmpty else { return nil }
        return fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
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
