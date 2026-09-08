import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum FileWriteKit {
    /// Write bytes via a sibling temp file then POSIX `rename`. Survives a crash mid-write:
    /// the destination is the previous complete file or absent, never a torn file.
    /// `FileManager.replaceItemAt` is not reliable on swift-corelibs-foundation.
    public static func writeAtomically(_ data: Data, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temp, options: .withoutOverwriting)
        if rename(temp.path, destination.path) != 0 {
            let code = Int(errno)
            try? FileManager.default.removeItem(at: temp)
            throw NSError(domain: NSPOSIXErrorDomain, code: code)
        }
    }

    public static func copyAtomically(from source: URL, to destination: URL) throws {
        let data = try Data(contentsOf: source)
        try writeAtomically(data, to: destination)
    }
}
