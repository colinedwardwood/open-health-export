import RequestTemplate

public struct MemorySecrets: TemplateSecrets {
    public var values: [String: String]
    public init(_ values: [String: String]) {
        self.values = values
    }

    public func resolve(handle: String) throws -> String {
        guard let value = values[handle] else {
            throw TemplateError.missingSecret(handle)
        }
        return value
    }
}
