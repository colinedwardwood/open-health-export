// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Watchdog

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

@MainActor
enum ArchiveLiveActivitySession {
    private static var activity: Activity<ArchiveLiveActivityAttributes>?

    static func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = ArchiveLiveActivityAttributes.ContentState(
            completedMonths: 0,
            totalMonths: 1,
            type: 0,
            types: 1
        )
        activity = try? Activity.request(
            attributes: ArchiveLiveActivityAttributes(),
            content: .init(state: state, staleDate: nil)
        )
    }

    static func update(progressLine: String) async {
        guard let parsed = ArchiveLiveActivity.parseProgress(progressLine) else { return }
        let state = ArchiveLiveActivityAttributes.ContentState(
            completedMonths: parsed.completedMonths,
            totalMonths: parsed.totalMonths,
            type: parsed.type,
            types: parsed.types
        )
        guard let current = activity else { return }
        nonisolated(unsafe) let unsafeCurrent = current
        await unsafeCurrent.update(.init(state: state, staleDate: nil))
    }

    static func finish() async {
        guard let current = activity else { return }
        activity = nil
        nonisolated(unsafe) let unsafeCurrent = current
        let state = ArchiveLiveActivityAttributes.ContentState(
            completedMonths: 1,
            totalMonths: 1,
            type: 1,
            types: 1
        )
        let dismissal = Date().addingTimeInterval(ArchiveLiveActivity.dismissalSeconds)
        await unsafeCurrent.end(
            .init(state: state, staleDate: nil),
            dismissalPolicy: .after(dismissal)
        )
    }
}
#else
@MainActor
enum ArchiveLiveActivitySession {
    static func start() {}
    static func update(progressLine: String) async { _ = progressLine }
    static func finish() async {}
}
#endif
