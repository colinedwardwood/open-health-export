// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CompanionWire
import FileWriteKit
import Foundation
import NetEgress
import WireFormat

public enum CompanionArchiveError: Error, Equatable {
    case unsafeBatchID
    case iCloudFolder(String)
}

/// Receive-side persistence: NDJSON next to a receipt index, so O1 survives a restart.
public struct CompanionArchive: Sendable {
    public var directory: URL
    public var warnOnlyOnICloud: Bool

    public init(directory: URL, warnOnlyOnICloud: Bool = true) {
        self.directory = directory
        self.warnOnlyOnICloud = warnOnlyOnICloud
    }

    /// O-10: warn, do not refuse, unless the caller opts into refusal.
    public func iCloudWarning() -> String? {
        FolderRisk.iCloudSyncWarning(for: directory)
    }

    public func assertWritable() throws {
        if let warning = iCloudWarning(), !warnOnlyOnICloud {
            throw CompanionArchiveError.iCloudFolder(warning)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func loadReceipts() throws -> [String: String] {
        let url = receiptsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    public func store(committed: CompanionCommitted) throws {
        try assertWritable()
        try BatchPath.validate(committed.batchID)
        let payloadURL = directory.appendingPathComponent("\(committed.batchID).ndjson")
        try FileWriteKit.writeAtomically(committed.payload, to: payloadURL)
        var receipts = try loadReceipts()
        receipts[committed.batchID] = committed.digest
        let encoded = try JSONEncoder().encode(receipts)
        try FileWriteKit.writeAtomically(encoded, to: receiptsURL)
    }

    public func payloadURL(batchID: String) throws -> URL {
        try BatchPath.validate(batchID)
        return directory.appendingPathComponent("\(batchID).ndjson")
    }

    private var receiptsURL: URL {
        directory.appendingPathComponent(".ohe-receipts.json")
    }
}

public enum FolderRisk {
    /// True when writing here would put PHI in iCloud Drive / Desktop-Documents sync.
    public static func iCloudSyncWarning(for url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemContainerDisplayNameKey])
        if values?.isUbiquitousItem == true {
            return "This folder is in iCloud. Health archives written here leave this Mac."
        }
        let path = url.path
        if path.contains("/Library/Mobile Documents/") || path.contains("/Mobile Documents/") {
            return "This folder is in iCloud. Health archives written here leave this Mac."
        }
        return nil
    }
}

enum BatchPath {
    static func validate(_ batchID: String) throws {
        guard !batchID.isEmpty,
              !batchID.contains("/"),
              !batchID.contains("\\"),
              !batchID.contains(".."),
              batchID.utf8.allSatisfy({ $0 >= 0x2D && $0 <= 0x7A })
        else {
            throw CompanionArchiveError.unsafeBatchID
        }
    }
}

/// Mac-side session: read frames, drive `CompanionReceiver`, write committed batches, reply.
public actor CompanionInbound {
    private let stream: any ByteStream
    private var receiver: CompanionReceiver
    private let archive: CompanionArchive
    private var inbound = Data()

    private let onPeerHello: (@Sendable (String) -> Void)?

    public init(
        stream: any ByteStream,
        archive: CompanionArchive,
        installationID: String,
        onPeerHello: (@Sendable (String) -> Void)? = nil
    ) throws {
        let receipts = try archive.loadReceipts()
        self.stream = stream
        self.receiver = CompanionReceiver(installationID: installationID, receipts: receipts)
        self.archive = archive
        self.onPeerHello = onPeerHello
    }

    public func serve() async throws {
        try archive.assertWritable()
        try await stream.open()
        do {
            while true {
                let message = try await receive()
                let turn = receiver.process(message)
                if let peer = turn.peerInstallationID {
                    onPeerHello?(peer)
                }
                if let committed = turn.committed {
                    try archive.store(committed: committed)
                }
                for reply in turn.replies {
                    try await stream.send(try reply.encodedFrame())
                }
            }
        } catch StreamError.closedByPeer {
            return
        }
    }

    private func receive() async throws -> CompanionMessage {
        while true {
            if let decoded = try CompanionFrame.decodePrefix(inbound) {
                inbound.removeFirst(decoded.consumed)
                return try CompanionMessage.decode(decoded.frame)
            }
            let chunk = try await stream.receive(max: 4096)
            if chunk.isEmpty { throw CompanionError.truncated }
            inbound.append(chunk)
        }
    }
}

private enum CompanionError: Error {
    case truncated
}
