import CoreDomain
import Foundation
import MetricCatalog
import WireFormat

@main
struct CorpusGen {
    static func main() throws {
        let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
        var buffer = Data()
        for index in 0..<options.count {
            let declaration = MetricCatalog.all[index % MetricCatalog.all.count]
            let sample = sample(at: index, seed: options.seed, declaration: declaration)
            let envelope = WireEnvelope(
                exporterId: "00000000-0000-4000-8000-000000000082",
                seq: index + 1,
                emittedAt: sample.observedAt,
                observedAt: sample.observedAt
            )
            buffer.append(Data(try NativeWire.encode(sample, envelope: envelope).utf8))
            buffer.append(0x0A)
            if buffer.count >= 1_048_576 {
                try FileHandle.standardOutput.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            try FileHandle.standardOutput.write(contentsOf: buffer)
        }
    }

    static func sample(
        at index: Int,
        seed: UInt64,
        declaration: MetricDeclaration
    ) -> SampleRecord {
        let random = splitMix64(UInt64(index) &+ seed)
        let year = 2020 + (index / (12 * 28)) % 6
        let month = 1 + (index / 28) % 12
        let day = 1 + index % 28
        let hour = Int((random >> 8) % 24)
        let minute = Int((random >> 16) % 60)
        let timestamp = String(
            format: "%04d-%02d-%02dT%02d:%02d:00Z",
            year, month, day, hour, minute
        )
        let uuid = String(
            format: "%08x-0000-4000-8000-%012llx",
            index & 0xFFFF_FFFF,
            random & 0xFFFF_FFFF_FFFF
        )
        let value = Double(random % 100_000) / 100
        return SampleRecord(
            key: RecordKey(uuid: uuid),
            metric: declaration.id,
            start: timestamp,
            end: timestamp,
            timeZoneOffsetMinutes: 0,
            timeZoneSource: .unknown,
            value: value,
            unit: declaration.canonicalUnit,
            observedAt: timestamp
        )
    }

    static func splitMix64(_ input: UInt64) -> UInt64 {
        var value = input &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

private struct Options {
    var seed: UInt64 = 1
    var count: Int = 200

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            guard index + 1 < arguments.count else { throw OptionError.missingValue }
            switch arguments[index] {
            case "--seed":
                guard let parsed = UInt64(arguments[index + 1]) else { throw OptionError.invalidValue }
                seed = parsed
            case "--count":
                guard let parsed = Int(arguments[index + 1]), parsed >= 0 else {
                    throw OptionError.invalidValue
                }
                count = parsed
            default:
                throw OptionError.unknownOption
            }
            index += 2
        }
    }
}

private enum OptionError: Error {
    case missingValue
    case invalidValue
    case unknownOption
}
