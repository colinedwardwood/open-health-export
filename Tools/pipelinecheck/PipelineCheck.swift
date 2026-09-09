import Foundation
import WireFormat

/// Stream `ohe.wire/1` NDJSON from stdin and validate every line against the committed schema.
@main
struct PipelineCheck {
    static func main() throws {
        let schemaPath = CommandLine.arguments.dropFirst().first
            ?? "spec/v1.0.0/schema/ohe.wire.1.json"
        let schema = try WireJSONSchema.load(Data(contentsOf: URL(fileURLWithPath: schemaPath)))
        var count = 0
        while let line = readLine(strippingNewline: true) {
            if line.isEmpty { continue }
            try WireJSONSchema.validateNDJSON(line, schema: schema)
            count += 1
        }
        FileHandle.standardOutput.write(Data("pipelinecheck lines=\(count)\n".utf8))
        if count == 0 {
            FileHandle.standardError.write(Data("pipelinecheck received no records\n".utf8))
            exit(1)
        }
    }
}
