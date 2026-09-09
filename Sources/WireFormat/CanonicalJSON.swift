import Foundation
#if canImport(CoreFoundation) && !os(Linux)
import CoreFoundation
#endif

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

    func prettySerialized() throws -> String {
        var out = ""
        try writePretty(to: &out, indent: 0)
        out.append("\n")
        return out
    }

    static func parse(_ value: Any) throws -> CanonicalJSON {
        if value is NSNull { return .null }
        if let string = value as? String { return .string(string) }
        if let array = value as? [Any] {
            return .array(try array.map { try parse($0) })
        }
        if let object = value as? [String: Any] {
            return .object(Dictionary(uniqueKeysWithValues: try object.map { key, nested in
                (key, try parse(nested))
            }))
        }
        if let number = value as? NSNumber {
            #if canImport(CoreFoundation) && !os(Linux)
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            #endif
            let double = number.doubleValue
            let integer = number.intValue
            if Double(integer) == double,
               double >= Double(Int.min),
               double <= Double(Int.max),
               !double.isNaN
            {
                return .integer(integer)
            }
            return .number(double)
        }
        if let bool = value as? Bool { return .bool(bool) }
        if let integer = value as? Int { return .integer(integer) }
        if let double = value as? Double { return .number(double) }
        throw WireError.utf8
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

    private func writePretty(to out: inout String, indent: Int) throws {
        let pad = String(repeating: " ", count: indent)
        let inner = String(repeating: " ", count: indent + 2)
        switch self {
        case .null, .bool, .integer, .number, .string:
            try write(to: &out)
        case .array(let items):
            if items.isEmpty {
                out.append("[]")
                return
            }
            out.append("[\n")
            for (i, item) in items.enumerated() {
                if i > 0 { out.append(",\n") }
                out.append(inner)
                try item.writePretty(to: &out, indent: indent + 2)
            }
            out.append("\n")
            out.append(pad)
            out.append("]")
        case .object(let members):
            if members.isEmpty {
                out.append("{}")
                return
            }
            out.append("{\n")
            for (i, key) in members.keys.sorted().enumerated() {
                if i > 0 { out.append(",\n") }
                out.append(inner)
                out.append("\"")
                out.append(Self.escape(key))
                out.append("\": ")
                try members[key]!.writePretty(to: &out, indent: indent + 2)
            }
            out.append("\n")
            out.append(pad)
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
