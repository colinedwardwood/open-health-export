// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

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

    public func loadWatch() throws -> CompanionReceiveWatch {
        let url = watchURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return CompanionReceiveWatch()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CompanionReceiveWatch.self, from: data)
    }

    public func saveWatch(_ watch: CompanionReceiveWatch) throws {
        try assertWritable()
        let encoded = try JSONEncoder().encode(watch)
        try FileWriteKit.writeAtomically(encoded, to: watchURL)
    }

    public func store(committed: CompanionCommitted, receivedAtEpoch: TimeInterval) throws {
        try assertWritable()
        try BatchPath.validate(committed.batchID)
        let payloadURL = directory.appendingPathComponent("\(committed.batchID).ndjson")
        try FileWriteKit.writeAtomically(committed.payload, to: payloadURL)
        var receipts = try loadReceipts()
        receipts[committed.batchID] = committed.digest
        let encoded = try JSONEncoder().encode(receipts)
        try FileWriteKit.writeAtomically(encoded, to: receiptsURL)
        var watch = try loadWatch()
        watch.lastReceivedEpoch = receivedAtEpoch
        try saveWatch(watch)
    }

    public func payloadURL(batchID: String) throws -> URL {
        try BatchPath.validate(batchID)
        return directory.appendingPathComponent("\(batchID).ndjson")
    }

    /// Deletes only payloads named by this archive's receipt ledger. It never
    /// glob-deletes `.ndjson` files from a user-selected folder.
    @discardableResult
    public func deleteEverythingReceived() throws -> Int {
        let receipts = try loadReceipts()
        for batchID in receipts.keys {
            let payload = try payloadURL(batchID: batchID)
            if FileManager.default.fileExists(atPath: payload.path) {
                try FileManager.default.removeItem(at: payload)
            }
        }
        if FileManager.default.fileExists(atPath: receiptsURL.path) {
            try FileManager.default.removeItem(at: receiptsURL)
        }
        if FileManager.default.fileExists(atPath: watchURL.path) {
            try FileManager.default.removeItem(at: watchURL)
        }
        return receipts.count
    }

    private var receiptsURL: URL {
        directory.appendingPathComponent(".ohe-receipts.json")
    }

    private var watchURL: URL {
        directory.appendingPathComponent(".ohe-receive-watch.json")
    }
}

public enum FolderRisk {
    /// True when writing here would put PHI in iCloud Drive / Desktop-Documents sync.
    /// `device` is the noun the warning uses for where the data stays ("this Mac").
    public static func iCloudSyncWarning(for url: URL, device: String = "this Mac") -> String? {
        isInICloud(url)
            ? "This folder is in iCloud. Health archives written here leave \(device)."
            : nil
    }

    /// The Mobile Documents path (iCloud Drive's container on macOS and iOS) is checked
    /// first because it needs no I/O; the ubiquity flag covers folders elsewhere.
    public static func isInICloud(_ url: URL) -> Bool {
        if url.path.contains("/Mobile Documents/") { return true }
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey])
        return values?.isUbiquitousItem == true
    }
}

/// The folder the person has said they accept being in iCloud, so the warning is asked
/// once per folder and a different folder asks again (App Review 5.1.3(ii)).
public struct ICloudFolderAcknowledgement {
    /// Where the acknowledged folder is kept. The app supplies its settings store; this
    /// module stays free of required-reason APIs so every bundle that links it is clean.
    public struct Storage {
        public var read: () -> String?
        public var write: (String?) -> Void

        public init(read: @escaping () -> String?, write: @escaping (String?) -> Void) {
            self.read = read
            self.write = write
        }
    }

    private let storage: Storage

    public init(storage: Storage) {
        self.storage = storage
    }

    public func isAcknowledged(_ url: URL) -> Bool {
        storage.read() == Self.identity(url)
    }

    public func acknowledge(_ url: URL) {
        storage.write(Self.identity(url))
    }

    public func clear() {
        storage.write(nil)
    }

    /// True when this folder is in iCloud and has not been acknowledged.
    public func needsAcknowledgement(_ url: URL) -> Bool {
        FolderRisk.isInICloud(url) && !isAcknowledged(url)
    }

    private static func identity(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
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
    private let nowEpoch: @Sendable () -> TimeInterval

    private let onPeerHello: (@Sendable (String) -> Void)?

    public init(
        stream: any ByteStream,
        archive: CompanionArchive,
        installationID: String,
        nowEpoch: @escaping @Sendable () -> TimeInterval = { 0 },
        onPeerHello: (@Sendable (String) -> Void)? = nil
    ) throws {
        let receipts = try archive.loadReceipts()
        self.stream = stream
        self.receiver = CompanionReceiver(installationID: installationID, receipts: receipts)
        self.archive = archive
        self.nowEpoch = nowEpoch
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
                    try archive.store(committed: committed, receivedAtEpoch: nowEpoch())
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
