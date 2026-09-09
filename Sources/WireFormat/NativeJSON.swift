import Foundation

enum NativeJSON {
    static func document(fromNDJSON data: Data) throws -> (canonical: Data, pretty: Data) {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map(String.init)
        var headerLine: String?
        var footerLine: String?
        var recordLines: [String] = []
        for line in lines {
            guard let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let kind = object["kind"] as? String
            else {
                throw WireError.utf8
            }
            switch kind {
            case "batch.header":
                headerLine = line
            case "batch.footer":
                footerLine = line
            default:
                recordLines.append(line)
            }
        }
        guard let headerLine, let footerLine else { throw WireError.utf8 }
        let canonical = "{\"footer\":\(footerLine),\"header\":\(headerLine),\"records\":[\(recordLines.joined(separator: ","))]}\n"
        let parsed = try JSONSerialization.jsonObject(with: Data(canonical.utf8))
        let pretty = try CanonicalJSON.parse(parsed).prettySerialized()
        return (Data(canonical.utf8), Data(pretty.utf8))
    }
}
