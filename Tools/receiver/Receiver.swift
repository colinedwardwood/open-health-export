import Foundation
import WireFormat

@main
struct Receiver {
    static func main() throws {
        let args = CommandLine.arguments.dropFirst().filter { $0 != "--" }
        guard let path = args.first else {
            FileHandle.standardError.write(Data("usage: receiver <file.ndjson>\n".utf8))
            exit(2)
        }
        let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        var receiver = ReferenceReceiver()
        try receiver.ingest(ndjson: text)
        let data = try JSONSerialization.data(
            withJSONObject: receiver.expectedState(),
            options: [.sortedKeys, .prettyPrinted]
        )
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
