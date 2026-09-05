import Foundation

/// Closed substitution grammar (AR-21). No conditionals, loops, or expression evaluation.
public struct RequestTemplate: Sendable {
    public var source: String

    public init(_ source: String) {
        self.source = source
    }

    public func render(context: TemplateContext) throws -> String {
        let pieces = try Self.parse(source)
        var out = ""
        for piece in pieces {
            switch piece {
            case .literal(let text):
                out.append(text)
            case .slot(let slot):
                out.append(try slot.render(context: context))
            }
        }
        return out
    }

    public func renderHeaderValue(context: TemplateContext) throws -> String {
        let rendered = try render(context: context)
        try TemplateDirective.validateHeaderValue(rendered)
        return rendered
    }
}

public struct TemplateContext: Sendable {
    public var values: [String: String]
    public var payload: String
    public var secrets: (any TemplateSecrets)?

    public init(
        values: [String: String] = [:],
        payload: String = "",
        secrets: (any TemplateSecrets)? = nil
    ) {
        self.values = values
        self.payload = payload
        self.secrets = secrets
    }
}

public protocol TemplateSecrets: Sendable {
    func resolve(handle: String) throws -> String
}

public enum TemplateError: Error, Equatable {
    case unclosedPlaceholder
    case emptyPlaceholder
    case unknownName(String)
    case unknownDirective(String)
    case missingDirective
    case rawForbidden(String)
    case headerInjection
    case missingSecret(String)
    case invalidHeaderName(String)
}

public enum TemplateDirective: String, Sendable {
    case header
    case json
    case query
    case raw

    func apply(_ value: String) throws -> String {
        switch self {
        case .header:
            try TemplateDirective.validateHeaderValue(value)
            return value
        case .json:
            return jsonString(value)
        case .query:
            return queryEscape(value)
        case .raw:
            return value
        }
    }

    public static func validateHeaderValue(_ headerValue: String) throws {
        for scalar in headerValue.unicodeScalars {
            if scalar.value == 0x0A || scalar.value == 0x0D || scalar.value == 0 {
                throw TemplateError.headerInjection
            }
            if scalar.value < 0x20 && scalar.value != 0x09 {
                throw TemplateError.headerInjection
            }
        }
    }
}

enum TemplatePiece {
    case literal(String)
    case slot(TemplateSlot)
}

struct TemplateSlot {
    var name: String
    var isSecret: Bool
    var directive: TemplateDirective

    func render(context: TemplateContext) throws -> String {
        let value: String
        if isSecret {
            guard let secrets = context.secrets else {
                throw TemplateError.missingSecret(name)
            }
            value = try secrets.resolve(handle: name)
        } else if name == "payload" {
            value = context.payload
        } else {
            guard let found = context.values[name] else {
                throw TemplateError.unknownName(name)
            }
            value = found
        }
        if directive == .raw, isSecret {
            throw TemplateError.rawForbidden(name)
        }
        if directive == .raw, !Self.trustedRaw.contains(name) {
            throw TemplateError.rawForbidden(name)
        }
        return try directive.apply(value)
    }

    static let trustedRaw: Set<String> = [
        "batchId", "idempotencyKey", "contentType", "exporterId", "seq", "emittedAt", "recordCount", "payload",
    ]
}

extension RequestTemplate {
    static func parse(_ source: String) throws -> [TemplatePiece] {
        var pieces: [TemplatePiece] = []
        var i = source.startIndex
        while i < source.endIndex {
            if let start = source[i...].range(of: "{{") {
                if start.lowerBound > i {
                    pieces.append(.literal(String(source[i..<start.lowerBound])))
                }
                guard let end = source[start.upperBound...].range(of: "}}") else {
                    throw TemplateError.unclosedPlaceholder
                }
                let inner = source[start.upperBound..<end.lowerBound]
                    .trimmingCharacters(in: .whitespaces)
                pieces.append(.slot(try parseSlot(inner)))
                i = end.upperBound
            } else {
                pieces.append(.literal(String(source[i...])))
                break
            }
        }
        return pieces
    }

    static func parseSlot(_ inner: String) throws -> TemplateSlot {
        if inner.isEmpty { throw TemplateError.emptyPlaceholder }
        let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[1].isEmpty else {
            throw TemplateError.missingDirective
        }
        guard let directive = TemplateDirective(rawValue: parts[1]) else {
            throw TemplateError.unknownDirective(parts[1])
        }
        let left = parts[0]
        if left.hasPrefix("secret:") {
            let handle = String(left.dropFirst("secret:".count))
            guard isHandle(handle) else { throw TemplateError.unknownName(left) }
            return TemplateSlot(name: handle, isSecret: true, directive: directive)
        }
        guard isName(left) else { throw TemplateError.unknownName(left) }
        return TemplateSlot(name: left, isSecret: false, directive: directive)
    }

    static func isName(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first else { return false }
        guard ("A"..."Z").contains(first) || ("a"..."z").contains(first) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            ("A"..."Z").contains(scalar)
                || ("a"..."z").contains(scalar)
                || ("0"..."9").contains(scalar)
                || scalar == "_"
        }
    }

    static func isHandle(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first else { return false }
        guard ("A"..."Z").contains(first) || ("a"..."z").contains(first) else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            ("A"..."Z").contains(scalar)
                || ("a"..."z").contains(scalar)
                || ("0"..."9").contains(scalar)
                || scalar == "_" || scalar == "." || scalar == "-"
        }
    }
}

func jsonString(_ value: String) -> String {
    var out = "\""
    for scalar in value.unicodeScalars {
        switch scalar {
        case "\"": out.append("\\\"")
        case "\\": out.append("\\\\")
        case "\n": out.append("\\n")
        case "\r": out.append("\\r")
        case "\t": out.append("\\t")
        default:
            if scalar.value < 0x20 {
                out.append(String(format: "\\u%04x", scalar.value))
            } else {
                out.append(String(scalar))
            }
        }
    }
    out.append("\"")
    return out
}

func queryEscape(_ value: String) -> String {
    var out = ""
    for byte in value.utf8 {
        let isUnreserved =
            (byte >= 0x41 && byte <= 0x5A)
            || (byte >= 0x61 && byte <= 0x7A)
            || (byte >= 0x30 && byte <= 0x39)
            || byte == 0x2D || byte == 0x2E || byte == 0x5F || byte == 0x7E
        if isUnreserved {
            out.append(Character(UnicodeScalar(byte)))
        } else {
            out.append(String(format: "%%%02X", byte))
        }
    }
    return out
}

public enum HeaderName {
    public static func validate(_ name: String) throws {
        guard !name.isEmpty else { throw TemplateError.invalidHeaderName(name) }
        for scalar in name.unicodeScalars {
            let ok =
                (scalar >= "A" && scalar <= "Z")
                || (scalar >= "a" && scalar <= "z")
                || (scalar >= "0" && scalar <= "9")
                || scalar == "-" || scalar == "_"
            if !ok {
                throw TemplateError.invalidHeaderName(name)
            }
        }
    }
}
