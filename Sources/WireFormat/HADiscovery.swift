import CoreDomain
import Foundation
import MetricCatalog

public enum HADiscoveryError: Error, Equatable {
    case badExporterId
    case unknownMetric
}

/// Home Assistant MQTT device discovery. Retained config and availability only — never samples.
public enum HADiscovery {
    public static let supportURL = "https://github.com/colinedwardwood/open-health-export"

    private static let sampleKeys: Set<String> = ["qty", "uuid", "samples", "observedAt"]

    public static func sanitizeExporterId(_ raw: String) throws -> String {
        let allowed = raw.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }
        let cleaned = String(String.UnicodeScalarView(allowed))
        guard !cleaned.isEmpty, cleaned.count <= 64 else { throw HADiscoveryError.badExporterId }
        return cleaned
    }

    public static func deviceConfigTopic(exporterId: String) throws -> String {
        try MQTTStyleTopic.homeAssistantDeviceConfig(exporterId: sanitizeExporterId(exporterId))
    }

    public static func statusTopic(exporterId: String) throws -> String {
        let id = try sanitizeExporterId(exporterId)
        return "ohe/\(id)/v1/status"
    }

    public static func statusPayload() -> Data { Data("online".utf8) }

    public static func encodeDeviceConfig(
        exporterId: String,
        metrics: [MetricID],
        softwareVersion: String = "0.1.0"
    ) throws -> Data {
        let id = try sanitizeExporterId(exporterId)
        let short = String(id.replacingOccurrences(of: "-", with: "").prefix(8))
        var components: [String: CanonicalJSON] = [:]
        for metric in metrics {
            guard let declaration = MetricCatalog.declaration(for: metric) else {
                throw HADiscoveryError.unknownMetric
            }
            let (key, object) = component(declaration: declaration, exporterId: id, shortId: short)
            components[key] = object
        }
        let root: CanonicalJSON = .object([
            "dev": .object([
                "identifiers": .array([.string("ohe_\(short)")]),
                "name": .string("iPhone Health Export"),
                "manufacturer": .string("open-health-exporter"),
                "model": .string("iPhone"),
                "sw_version": .string(softwareVersion),
            ]),
            "o": .object([
                "name": .string("open-health-exporter"),
                "sw_version": .string(softwareVersion),
                "support_url": .string(supportURL),
            ]),
            "cmps": .object(components),
        ])
        return Data(try root.serialized().utf8)
    }

    /// T-35: retain is only for discovery/config and the availability status byte string.
    public static func retainAllowed(topic: String, payload: Data) -> Bool {
        if MQTTStyleTopic.isHomeAssistantDeviceConfig(topic) {
            if payload.isEmpty { return true }
            return !containsSampleKeys(payload)
        }
        if MQTTStyleTopic.isAvailabilityStatus(topic) {
            return payload == statusPayload()
        }
        return false
    }

    private static func component(
        declaration: MetricDeclaration,
        exporterId: String,
        shortId: String
    ) -> (String, CanonicalJSON) {
        let statistic = declaration.cumulative ? "sum" : "mean"
        let granularity = declaration.cumulative ? "P1D" : "PT1H"
        let key = "\(declaration.wireId)_\(statistic)_\(granularity.lowercased())"
        let stateTopic = "ohe/\(exporterId)/v1/state/\(declaration.wireId)/\(statistic)/\(granularity)"
        var fields: [String: CanonicalJSON] = [
            "p": .string("sensor"),
            "name": .string(declaration.wireId.replacingOccurrences(of: "_", with: " ")),
            "unique_id": .string("ohe_\(shortId)_\(declaration.wireId)_\(statistic)_\(granularity)"),
            "state_topic": .string(stateTopic),
            "value_template": .string("{{ value_json.value }}"),
            "availability_topic": .string("ohe/\(exporterId)/v1/status"),
        ]
        if let unit = declaration.haUnit {
            fields["unit_of_measurement"] = .string(unit)
        }
        if let deviceClass = declaration.haDeviceClass {
            fields["device_class"] = .string(deviceClass)
        }
        if let stateClass = declaration.haStateClass {
            fields["state_class"] = .string(stateClass)
        }
        return (key, .object(fields))
    }

    private static func containsSampleKeys(_ payload: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: payload),
            let root = object as? [String: Any]
        else {
            return true
        }
        return walk(root)
    }

    private static func walk(_ value: Any) -> Bool {
        if let object = value as? [String: Any] {
            if !sampleKeys.isDisjoint(with: Set(object.keys)) { return true }
            return object.values.contains { walk($0) }
        }
        if let array = value as? [Any] {
            return array.contains { walk($0) }
        }
        return false
    }
}

enum MQTTStyleTopic {
    static func homeAssistantDeviceConfig(exporterId: String) -> String {
        "homeassistant/device/\(exporterId)/config"
    }

    static func isHomeAssistantDeviceConfig(_ topic: String) -> Bool {
        let parts = topic.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return parts.count == 4 && parts[0] == "homeassistant" && parts[1] == "device" && parts[3] == "config"
            && !parts[2].isEmpty && !parts[2].contains("+") && !parts[2].contains("#")
    }

    static func isAvailabilityStatus(_ topic: String) -> Bool {
        let parts = topic.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return parts.count == 4 && parts[0] == "ohe" && parts[2] == "v1" && parts[3] == "status"
            && !parts[1].isEmpty
    }
}
