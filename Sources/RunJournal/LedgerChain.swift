import EnginePorts
import Foundation
import WireFormat

public enum LedgerVerification: Sendable, Equatable {
    case valid(head: String, count: Int)
    case invalid(sequence: Int)
}

public enum LedgerChain {
    public static let genesisHash = String(repeating: "0", count: 64)

    public static func seal(
        _ entry: EgressEntry,
        sequence: Int,
        previousHash: String
    ) -> EgressEntry {
        var sealed = entry
        sealed.sequence = sequence
        sealed.previousHash = previousHash
        sealed.entryHash = digest(sealed)
        return sealed
    }

    public static func verify(_ entries: [EgressEntry]) -> LedgerVerification {
        var previous = genesisHash
        for (index, entry) in entries.enumerated() {
            let expectedSequence = index + 1
            guard entry.sequence == expectedSequence,
                  entry.previousHash == previous,
                  entry.entryHash == digest(entry)
            else {
                return .invalid(sequence: entry.sequence)
            }
            previous = entry.entryHash
        }
        return .valid(head: previous, count: entries.count)
    }

    public static func digest(_ entry: EgressEntry) -> String {
        ContentSHA256.hex(Data(canonicalBytes(entry).utf8))
    }

    private static func canonicalBytes(_ entry: EgressEntry) -> String {
        [
            String(entry.sequence),
            field(entry.previousHash),
            field(entry.destination),
            String(entry.sampleCount),
            String(entry.byteCount),
            field(entry.outcomeKind),
            field(entry.detail),
            String(entry.wallTimeEpoch.bitPattern),
        ].joined(separator: "\n")
    }

    private static func field(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }
}
