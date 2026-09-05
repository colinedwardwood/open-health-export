import Foundation

public enum FileWriteKit {
    /// Write bytes via a sibling temp file then `replace`. Survives a crash mid-write:
    /// the destination is the previous complete file or absent, never a torn file.
    public static func writeAtomically(_ data: Data, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temp, options: .withoutOverwriting)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
        } else {
            try FileManager.default.moveItem(at: temp, to: destination)
        }
    }

    public static func copyAtomically(from source: URL, to destination: URL) throws {
        let data = try Data(contentsOf: source)
        try writeAtomically(data, to: destination)
    }
}
