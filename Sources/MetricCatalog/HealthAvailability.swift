// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// UX-07 / HK-01: a device with no Health store gets one terminal explanation,
/// not onboarding, a spinner, a retry loop, or an empty dashboard.
public enum HealthAvailability {
    public static let unavailableTitle = "Apple Health is not on this device"
    public static let unavailableBody =
        "This hardware has no Health store. Destinations and pairing still work. Export of Health samples stays off."
    public static let unavailableEnvironmentKey = "OHE_HEALTHKIT_UNAVAILABLE"
}
