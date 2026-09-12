// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import MetricCatalog
import WireFormat

@main
struct CorpusGen {
    static func main() throws {
        let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
        var buffer = Data()
        buffer.append(try provenanceHeader(options: options))
        buffer.append(0x0A)
        for index in 0..<options.resolvedCount {
            let declaration = DemoCorpus.declaration(at: index, tier: options.tier)
            let sample = DemoCorpus.sample(
                at: index,
                seed: options.seed,
                declaration: declaration,
                tier: options.tier
            )
            let envelope = WireEnvelope(
                exporterId: "00000000-0000-4000-8000-000000000082",
                seq: index + 1,
                emittedAt: sample.observedAt,
                observedAt: sample.observedAt
            )
            buffer.append(
                Data(
                    try DemoCorpus.encodeRecord(
                        index: index,
                        sample: sample,
                        envelope: envelope,
                        tier: options.tier,
                        seed: options.seed
                    ).utf8
                )
            )
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

    private static func provenanceHeader(options: Options) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "batchId": "82000000-0000-4000-8000-000000000000",
                "emittedAt": "2020-01-01T00:00:00Z",
                "exporterId": "00000000-0000-4000-8000-000000000082",
                "generatorVersion": 1,
                "kind": "batch.header",
                "mode": "samples",
                "producer": ["name": "ohe-corpusgen", "version": "1"],
                "reason": "manual",
                "recordCount": options.resolvedCount,
                "seed": options.seed,
                "seq": 0,
                "spec": "ohe.wire/1",
                "specVersion": "1.0",
                "synthetic": true,
                "tier": options.tier.rawValue,
                "types": Array(
                    Set(
                        MetricCatalog.all.map(\.wireId)
                            + DemoCorpus.categoryTypes.map(\.metricID)
                            + ["blood_pressure", "workout", "state_of_mind",
                               "electrocardiogram", "audiogram", "medication_dose"]
                    )
                ).sorted(),
            ],
            options: [.sortedKeys]
        )
    }

}

private struct Options {
    var seed: UInt64 = 1
    var tier: SyntheticCorpusTier = .t0
    var count: Int?
    var resolvedCount: Int { count ?? tier.defaultCount }

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
            case "--tier":
                guard let parsed = SyntheticCorpusTier(
                    rawValue: arguments[index + 1].uppercased()
                ) else {
                    throw OptionError.invalidValue
                }
                tier = parsed
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
