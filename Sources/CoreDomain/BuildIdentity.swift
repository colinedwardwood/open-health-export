// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// UX-31: Copy diagnostics names the running build so a GitHub issue is actionable
/// without carrying a destination secret.
public struct BuildIdentity: Sendable, Equatable {
    public var sourceCommit: String
    public var buildHash: String

    public init(sourceCommit: String, buildHash: String) {
        self.sourceCommit = sourceCommit
        self.buildHash = buildHash
    }

    public static var current: BuildIdentity {
        let commit = bundleValue("OHESourceCommit") ?? repositoryCommit() ?? "unspecified"
        let version = bundleValue("CFBundleShortVersionString") ?? "0.1.0"
        return BuildIdentity(
            sourceCommit: commit,
            buildHash: fingerprint(version: version, commit: commit)
        )
    }

    public static func fingerprint(version: String, commit: String) -> String {
        fnv1aHex("\(version)+\(commit)")
    }

    public static func traceID(seed: String) -> String {
        fnv1aHex(seed) + fnv1aHex("span+" + seed).prefix(16)
    }

    public static func publicDestinationLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "this destination" }
        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            return host
        }
        if trimmed.contains("://") || trimmed.contains("@") || trimmed.contains("?") {
            return "this destination"
        }
        return trimmed
    }

    private static func bundleValue(_ key: String) -> String? {
        #if canImport(Darwin)
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("$(") { return nil }
        return trimmed
        #else
        return nil
        #endif
    }

    private static func repositoryCommit() -> String? {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            directory.deleteLastPathComponent()
            let git = directory.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: git.appendingPathComponent("HEAD").path) {
                return commit(inGitDirectory: git)
            }
            if let gitfile = try? String(contentsOf: git, encoding: .utf8),
               gitfile.hasPrefix("gitdir:")
            {
                let relative = gitfile.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
                let gitDir = directory.appendingPathComponent(relative)
                return commit(inGitDirectory: gitDir)
            }
        }
        return nil
    }

    private static func commit(inGitDirectory git: URL) -> String? {
        let head = git.appendingPathComponent("HEAD")
        guard let raw = try? String(contentsOf: head, encoding: .utf8) else { return nil }
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref: ") {
            let ref = String(line.dropFirst(5))
            let refURL = git.appendingPathComponent(ref)
            let value = try? String(contentsOf: refURL, encoding: .utf8)
            return value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return line.isEmpty ? nil : line
    }

    private static func fnv1aHex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
