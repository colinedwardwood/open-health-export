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
            let sample = DemoCorpus.sample(at: index, seed: options.seed, declaration: declaration)
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
