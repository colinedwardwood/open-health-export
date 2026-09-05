import Foundation

enum CanonicalJSON {
    case object([String: CanonicalJSON])
    case array([CanonicalJSON])
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case null

    func serialized() throws -> String {
        var out = ""
        try write(to: &out)
        return out
    }

    private func write(to out: inout String) throws {
        switch self {
        case .null:
            out.append("null")
        case .bool(let value):
            out.append(value ? "true" : "false")
        case .integer(let value):
            out.append(String(value))
        case .number(let value):
            out.append(try Self.renderNumber(value))
        case .string(let value):
            out.append("\"")
            out.append(Self.escape(value))
            out.append("\"")
        case .array(let items):
            out.append("[")
            for (i, item) in items.enumerated() {
                if i > 0 { out.append(",") }
                try item.write(to: &out)
            }
            out.append("]")
        case .object(let members):
            out.append("{")
            for (i, key) in members.keys.sorted().enumerated() {
                if i > 0 { out.append(",") }
                out.append("\"")
                out.append(Self.escape(key))
                out.append("\":")
                try members[key]!.write(to: &out)
            }
            out.append("}")
        }
    }

    private static func renderNumber(_ value: Double) throws -> String {
        guard value.isFinite else { throw WireError.nonFiniteNumber }
        if value == 0 { return "0" }
        let truncated = value.rounded(.towardZero)
        if truncated == value, value >= Double(Int64.min), value <= Double(Int64.max) {
            return String(Int64(value))
        }
        return String(format: "%.17g", value)
    }

    private static func escape(_ value: String) -> String {
        var out = ""
        for ch in value.unicodeScalars {
            switch ch {
            case "\"": out.append("\\\"")
            case "\\": out.append("\\\\")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\t": out.append("\\t")
            default:
                if ch.value < 0x20 {
                    out.append(String(format: "\\u%04x", ch.value))
                } else {
                    out.append(String(ch))
                }
            }
        }
        return out
    }
}
