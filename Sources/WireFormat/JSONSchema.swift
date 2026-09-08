import Foundation
import CoreFoundation

public enum JSONSchemaError: Error, Equatable {
    case notObject
    case missingRequired(String)
    case typeMismatch(String)
    case constMismatch(String)
    case enumMismatch(String)
    case noOneOfMatch
    case missingKind
}

public enum FreezeClass: String, Sendable, Equatable {
    case breaking
    case additive
}

public struct FreezeChange: Sendable, Equatable {
    public var classification: FreezeClass
    public var code: String
    public var detail: String

    public init(classification: FreezeClass, code: String, detail: String) {
        self.classification = classification
        self.code = code
        self.detail = detail
    }
}

/// Subset JSON Schema validator for ohe.wire/1 (R-12 G2/G4). No third-party library.
public enum WireJSONSchema {
    public static func load(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JSONSchemaError.notObject
        }
        return object
    }

    public static func specVersion(of schema: [String: Any]) -> String {
        schema["x-ohe-specVersion"] as? String ?? "0.0"
    }

    public static func validate(instance: Any, schema: [String: Any]) throws {
        if let oneOf = schema["oneOf"] as? [Any] {
            if let object = instance as? [String: Any],
               let kind = object["kind"] as? String,
               let match = oneOf.first(where: {
                   let candidate = resolve($0, root: schema)
                   let properties = candidate["properties"] as? [String: Any]
                   let kindSchema = properties?["kind"] as? [String: Any]
                   return kindSchema?["const"] as? String == kind
               }) {
                try validate(instance: instance, schema: resolve(match, root: schema), root: schema)
                return
            }
            for entry in oneOf {
                do {
                    try validate(instance: instance, schema: resolve(entry, root: schema), root: schema)
                    return
                } catch {}
            }
            throw JSONSchemaError.noOneOfMatch
        }
        try validate(instance: instance, schema: schema, root: schema)
    }

    public static func validateNDJSON(_ text: String, schema: [String: Any]) throws {
        for line in text.split(whereSeparator: \.isNewline) where !line.isEmpty {
            let data = Data(line.utf8)
            let instance = try JSONSerialization.jsonObject(with: data)
            try validate(instance: instance, schema: schema)
        }
    }

    /// Structural diff of `$defs` record kinds against the freeze baseline (R-12 G2).
    public static func freezeDiff(frozen: [String: Any], current: [String: Any]) -> [FreezeChange] {
        var changes: [FreezeChange] = []
        let frozenDefs = frozen["$defs"] as? [String: Any] ?? [:]
        let currentDefs = current["$defs"] as? [String: Any] ?? [:]
        for (name, frozenDef) in frozenDefs {
            guard let frozenObject = frozenDef as? [String: Any] else { continue }
            guard let currentObject = currentDefs[name] as? [String: Any] else {
                changes.append(FreezeChange(classification: .breaking, code: "B1", detail: "removed record kind \(name)"))
                continue
            }
            changes.append(contentsOf: diffObject(name: name, frozen: frozenObject, current: currentObject))
        }
        for name in currentDefs.keys where frozenDefs[name] == nil {
            changes.append(FreezeChange(classification: .additive, code: "A3", detail: "added record kind \(name)"))
        }
        return changes
    }

    public static func freezeGate(
        frozen: [String: Any],
        current: [String: Any],
        markedFrozen: Bool
    ) -> String? {
        let changes = freezeDiff(frozen: frozen, current: current)
        let breaking = changes.filter { $0.classification == .breaking }
        if !breaking.isEmpty {
            return breaking.map { "\($0.code) \($0.detail)" }.joined(separator: "\n")
        }
        let additive = changes.filter { $0.classification == .additive }
        guard markedFrozen, !additive.isEmpty else { return nil }
        if compareSpecVersion(specVersion(of: current), specVersion(of: frozen)) <= 0 {
            return "A-class change without a MINOR specVersion bump"
        }
        return nil
    }

    private static func diffObject(
        name: String,
        frozen: [String: Any],
        current: [String: Any]
    ) -> [FreezeChange] {
        var changes: [FreezeChange] = []
        let frozenProps = frozen["properties"] as? [String: Any] ?? [:]
        let currentProps = current["properties"] as? [String: Any] ?? [:]
        let frozenRequired = Set(frozen["required"] as? [String] ?? [])
        let currentRequired = Set(current["required"] as? [String] ?? [])
        for key in frozenProps.keys where currentProps[key] == nil {
            changes.append(FreezeChange(classification: .breaking, code: "B1", detail: "\(name).\(key) removed"))
        }
        for key in currentRequired.subtracting(frozenRequired) {
            changes.append(FreezeChange(classification: .breaking, code: "B6", detail: "\(name).\(key) became required"))
        }
        for key in frozenRequired.subtracting(currentRequired) {
            changes.append(FreezeChange(classification: .additive, code: "A6", detail: "\(name).\(key) validation loosened"))
        }
        for (key, frozenProp) in frozenProps {
            guard let frozenSchema = frozenProp as? [String: Any],
                  let currentSchema = currentProps[key] as? [String: Any]
            else { continue }
            if jsonType(frozenSchema) != jsonType(currentSchema) {
                changes.append(FreezeChange(classification: .breaking, code: "B3", detail: "\(name).\(key) type changed"))
            }
            if let frozenConst = frozenSchema["const"],
               stringify(frozenConst) != stringify(currentSchema["const"] as Any) {
                changes.append(FreezeChange(classification: .breaking, code: "B5", detail: "\(name).\(key) const changed"))
            }
            let frozenEnum = Set(frozenSchema["enum"] as? [String] ?? [])
            let currentEnum = Set(currentSchema["enum"] as? [String] ?? [])
            if !frozenEnum.isEmpty {
                if !frozenEnum.isSubset(of: currentEnum) {
                    changes.append(FreezeChange(classification: .breaking, code: "B7", detail: "\(name).\(key) lost enum member"))
                }
                let added = currentEnum.subtracting(frozenEnum)
                if !added.isEmpty {
                    let open = frozenSchema["x-ohe-open"] as? Bool ?? false
                    if open {
                        changes.append(FreezeChange(classification: .additive, code: "A2", detail: "\(name).\(key) gained open enum member"))
                    } else {
                        changes.append(FreezeChange(classification: .breaking, code: "B8", detail: "\(name).\(key) gained closed enum member"))
                    }
                }
            }
            if validationTightened(frozen: frozenSchema, current: currentSchema) {
                changes.append(FreezeChange(classification: .breaking, code: "B13", detail: "\(name).\(key) validation tightened"))
            }
        }
        if frozen["additionalProperties"] as? Bool != false,
           current["additionalProperties"] as? Bool == false {
            changes.append(FreezeChange(classification: .breaking, code: "B13", detail: "\(name) rejects additive fields"))
        }
        for key in currentProps.keys where frozenProps[key] == nil {
            if currentRequired.contains(key) {
                changes.append(FreezeChange(classification: .breaking, code: "B6", detail: "\(name).\(key) added as required"))
            } else {
                changes.append(FreezeChange(classification: .additive, code: "A1", detail: "\(name).\(key) added optional"))
            }
        }
        return changes
    }

    private static func validationTightened(
        frozen: [String: Any],
        current: [String: Any]
    ) -> Bool {
        for key in ["minimum", "exclusiveMinimum", "minLength", "minItems"] {
            let before = numeric(frozen[key])
            let after = numeric(current[key])
            if before == nil, after != nil { return true }
            if let before, let after, after > before { return true }
        }
        for key in ["maximum", "exclusiveMaximum", "maxLength", "maxItems"] {
            let before = numeric(frozen[key])
            let after = numeric(current[key])
            if before != nil, after != nil, after! < before! { return true }
            if before == nil, after != nil { return true }
        }
        if frozen["pattern"] == nil, current["pattern"] != nil { return true }
        if let before = frozen["pattern"] as? String,
           let after = current["pattern"] as? String,
           before != after {
            return true
        }
        return false
    }

    private static func numeric(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func jsonType(_ schema: [String: Any]) -> String {
        if let type = schema["type"] as? String { return type }
        if schema["const"] != nil { return "const" }
        if schema["enum"] != nil { return "enum" }
        return "unknown"
    }

    private static func compareSpecVersion(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        let majorL = left.first ?? 0
        let minorL = left.count > 1 ? left[1] : 0
        let majorR = right.first ?? 0
        let minorR = right.count > 1 ? right[1] : 0
        if majorL != majorR { return majorL < majorR ? -1 : 1 }
        if minorL != minorR { return minorL < minorR ? -1 : 1 }
        return 0
    }

    private static func resolve(_ entry: Any, root: [String: Any]) -> [String: Any] {
        guard let object = entry as? [String: Any] else { return [:] }
        if let ref = object["$ref"] as? String, ref.hasPrefix("#/$defs/") {
            let name = String(ref.dropFirst("#/$defs/".count))
            return (root["$defs"] as? [String: Any])?[name] as? [String: Any] ?? object
        }
        return object
    }

    private static func validate(instance: Any, schema: [String: Any], root: [String: Any]) throws {
        let schema = resolve(schema, root: root)
        if let expected = schema["type"] as? String {
            try checkType(instance, expected: expected, field: schema["const"] as? String ?? "value")
        }
        if let constant = schema["const"] {
            if stringify(instance) != stringify(constant) {
                throw JSONSchemaError.constMismatch(stringify(constant))
            }
        }
        if let values = schema["enum"] as? [Any] {
            let ok = values.contains { stringify($0) == stringify(instance) }
            if !ok { throw JSONSchemaError.enumMismatch("enum") }
        }
        guard schema["type"] as? String == "object" || schema["properties"] != nil else { return }
        guard let object = instance as? [String: Any] else {
            throw JSONSchemaError.notObject
        }
        for key in schema["required"] as? [String] ?? [] {
            if object[key] == nil { throw JSONSchemaError.missingRequired(key) }
        }
        let properties = schema["properties"] as? [String: Any] ?? [:]
        for (key, value) in object {
            if let child = properties[key] as? [String: Any] {
                try validate(instance: value, schema: child, root: root)
            }
        }
    }

    private static func checkType(_ instance: Any, expected: String, field: String) throws {
        switch expected {
        case "object":
            guard instance is [String: Any] else { throw JSONSchemaError.typeMismatch(field) }
        case "array":
            guard instance is [Any] else { throw JSONSchemaError.typeMismatch(field) }
        case "string":
            guard instance is String else { throw JSONSchemaError.typeMismatch(field) }
        case "boolean":
            guard instance is Bool else { throw JSONSchemaError.typeMismatch(field) }
        case "integer":
            guard isInteger(instance) else { throw JSONSchemaError.typeMismatch(field) }
        case "number":
            guard isNumber(instance) else { throw JSONSchemaError.typeMismatch(field) }
        default:
            break
        }
    }

    private static func isInteger(_ instance: Any) -> Bool {
        if isBoolean(instance) { return false }
        if instance is Int || instance is Int64 { return true }
        if let number = instance as? NSNumber {
            return number.doubleValue == floor(number.doubleValue)
        }
        return false
    }

    private static func isNumber(_ instance: Any) -> Bool {
        if isBoolean(instance) { return false }
        return instance is Int || instance is Int64 || instance is Double || instance is NSNumber
    }

    private static func isBoolean(_ instance: Any) -> Bool {
        guard let number = instance as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func stringify(_ value: Any) -> String {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        if let flag = value as? Bool { return flag ? "true" : "false" }
        return "\(value)"
    }
}
