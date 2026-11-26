// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

/// UX-07 / HK-01: a device with no Health store gets one terminal explanation,
/// not onboarding, a spinner, a retry loop, or an empty dashboard.
public enum HealthAvailability {
    public static let unavailableTitle = "Apple Health is not on this device"
    public static let unavailableBody =
        "This hardware has no Health store. Destinations and pairing still work. Export of Health samples stays off."
    #if DEBUG
    /// DEBUG only (#69): the override string must not ship in a Release binary.
    public static let unavailableEnvironmentKey = "OHE_HEALTHKIT_UNAVAILABLE"
    #endif
}

/// Status row when this iPad is the exporter. Non-dismissible and non-alarming.
public enum IPadExporterNotice {
    public static let title = "This iPad is your only exporter."
    public static let body =
        "An iPad's Health data is only what this iPad recorded plus what syncs to it, and iPads spend more time asleep and off-charge than iPhones do. If you have an iPhone, it will be more complete and more current."
    #if DEBUG
    /// DEBUG only (#69): the override string must not ship in a Release binary.
    public static let environmentKey = "OHE_IPAD_ONLY_EXPORTER"
    #endif

    public static func isVisible(idiomIsPad: Bool, environment: [String: String]) -> Bool {
        #if DEBUG
        switch environment[environmentKey] {
        case "1": return true
        case "0": return false
        default: break
        }
        #endif
        return idiomIsPad
    }
}
