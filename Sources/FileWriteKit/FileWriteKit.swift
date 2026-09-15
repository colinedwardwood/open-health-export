// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum FileWriteError: Error, Equatable {
    case injectedFault
}

public enum FileWriteKit {
    #if DEBUG
    public enum Fault: Sendable {
        case none
        case abortBeforeRename
        case abortAfterTruncatingTemp(to: Int)
    }

    @TaskLocal public static var fault: Fault = .none
    #endif

    /// SEC-30 / OBS-33 / T-16: a Data Protection class is inherited by new files in a
    /// directory, but backup exclusion is not — it has to be set on the directory
    /// itself. Without it, queued payloads and the journal are swept into an iCloud or
    /// encrypted Finder backup and can be restored onto a device that was never
    /// authorised to read this Health data.
    ///
    /// Not applied to a folder the user chose as an export destination: excluding
    /// someone's own Files folder from their backups is not ours to decide.
    public static func excludeFromBackup(_ url: URL) throws {
        #if canImport(Darwin)
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try target.setResourceValues(values)
        #endif
    }

    /// Write bytes via a sibling temp file then POSIX `rename`. Survives a crash mid-write:
    /// the destination is the previous complete file or absent, never a torn file.
    /// `FileManager.replaceItemAt` is not reliable on swift-corelibs-foundation.
    public static func writeAtomically(_ data: Data, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: temp, options: .withoutOverwriting)
        #if DEBUG
        try injectWriteFault(temp: temp, intended: data)
        #endif
        if rename(temp.path, destination.path) != 0 {
            let code = Int(errno)
            try? FileManager.default.removeItem(at: temp)
            throw NSError(domain: NSPOSIXErrorDomain, code: code)
        }
    }

    private static let copyChunkBytes = 64 * 1_024

    /// Copy a payload file without materialising it. R-74 forbids `Data(contentsOf:)`
    /// on the delivery path: a 10k-record page plus sidecars already saturates the
    /// background ceiling if the NDJSON is held as bytes.
    public static func copyAtomically(from source: URL, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try copyStreaming(from: source, to: temp)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        #if DEBUG
        switch fault {
        case .none:
            break
        case .abortBeforeRename, .abortAfterTruncatingTemp:
            try injectWriteFault(temp: temp, intended: try Data(contentsOf: source))
        }
        #endif
        if rename(temp.path, destination.path) != 0 {
            let code = Int(errno)
            try? FileManager.default.removeItem(at: temp)
            throw NSError(domain: NSPOSIXErrorDomain, code: code)
        }
    }

    public static func contentsEqual(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let leftAttrs = try FileManager.default.attributesOfItem(atPath: lhs.path)
        let rightAttrs = try FileManager.default.attributesOfItem(atPath: rhs.path)
        guard (leftAttrs[.size] as? NSNumber)?.int64Value
            == (rightAttrs[.size] as? NSNumber)?.int64Value
        else {
            return false
        }
        let left = try FileHandle(forReadingFrom: lhs)
        let right = try FileHandle(forReadingFrom: rhs)
        defer {
            try? left.close()
            try? right.close()
        }
        while true {
            let a = try left.read(upToCount: copyChunkBytes) ?? Data()
            let b = try right.read(upToCount: copyChunkBytes) ?? Data()
            if a != b { return false }
            if a.isEmpty { return true }
        }
    }

    private static func copyStreaming(from source: URL, to destination: URL) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }
        while true {
            let chunk = try input.read(upToCount: copyChunkBytes) ?? Data()
            if chunk.isEmpty { break }
            try output.write(contentsOf: chunk)
        }
    }

    #if DEBUG
    private static func injectWriteFault(temp: URL, intended: Data) throws {
        switch fault {
        case .none:
            return
        case .abortBeforeRename:
            try? FileManager.default.removeItem(at: temp)
            throw FileWriteError.injectedFault
        case .abortAfterTruncatingTemp(let count):
            try Data(intended.prefix(max(0, count))).write(to: temp)
            throw FileWriteError.injectedFault
        }
    }
    #endif
}
