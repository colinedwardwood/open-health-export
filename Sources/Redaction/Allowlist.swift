import CoreDomain

public enum Allowlist {
    public static let journalFields: Set<String> = [
        "metric",
        "count",
        "outcome",
        "errorClass",
        "runID",
    ]

    public static func permitted(_ field: String) -> Bool {
        journalFields.contains(field)
    }
}
