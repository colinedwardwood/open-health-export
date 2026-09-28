// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import Foundation
import NetEgress

/// The advisory client's counters in the app's preferences (keys in SettingsStore).
struct PreferencesAdvisoryStorage: AdvisoryStateStorage {
    func load(enabled: Bool) -> AdvisoryState {
        let defaults = UserDefaults.standard
        return AdvisoryState(
            enabled: enabled,
            lastAttemptEpoch: defaults.object(forKey: SettingKey.advisoryLastAttemptEpoch.rawValue) as? TimeInterval,
            lastVerifiedEpoch: defaults.object(forKey: SettingKey.advisoryLastVerifiedEpoch.rawValue) as? TimeInterval,
            lastSeenSeq: defaults.integer(forKey: SettingKey.advisoryLastSeenSeq.rawValue)
        )
    }

    func save(_ state: AdvisoryState) {
        let defaults = UserDefaults.standard
        defaults.set(state.lastAttemptEpoch, forKey: SettingKey.advisoryLastAttemptEpoch.rawValue)
        defaults.set(state.lastVerifiedEpoch, forKey: SettingKey.advisoryLastVerifiedEpoch.rawValue)
        defaults.set(state.lastSeenSeq, forKey: SettingKey.advisoryLastSeenSeq.rawValue)
    }
}

enum AppAdvisory {
    static let service = AdvisoryService(
        storage: PreferencesAdvisoryStorage(),
        transport: { SystemHTTPTransport.make() },
        store: {
            let root = try HarnessExport.applicationSupportRoot()
            return try StateStoreHost.store(path: root.appendingPathComponent("state.sqlite").path)
        },
        emptyBody: {
            let body = try HarnessExport.applicationSupportRoot()
                .appendingPathComponent("advisory-request-body")
            if !FileManager.default.fileExists(atPath: body.path) {
                try Data().write(to: body, options: .atomic)
            }
            return body
        },
        marketingVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0.0.0"
    )
}
