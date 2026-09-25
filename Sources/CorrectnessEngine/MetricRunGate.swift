// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain

/// #31: at most one `ExportRun` per metric in a process at a time.
///
/// Foreground catch-up, observer wakes, background tasks, Shortcuts and the Control
/// Centre control all start exports independently. A run loads its cursor at the
/// start and commits it much later, so two overlapping runs of one metric read the
/// same page, enqueue it twice, and the slower one can move the cursor back. A second
/// run now waits for the first and then starts from the cursor it left.
actor MetricRunGate {
    static let shared = MetricRunGate()

    private var busy: Set<MetricID> = []
    private var waiters: [MetricID: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(_ metric: MetricID) async {
        guard busy.contains(metric) else {
            busy.insert(metric)
            return
        }
        await withCheckedContinuation { waiters[metric, default: []].append($0) }
    }

    /// Hands the metric straight to the next waiter, in arrival order, so a run that
    /// was queued cannot be overtaken by one that arrives later.
    func release(_ metric: MetricID) {
        guard var queue = waiters[metric], !queue.isEmpty else {
            busy.remove(metric)
            return
        }
        let next = queue.removeFirst()
        waiters[metric] = queue.isEmpty ? nil : queue
        next.resume()
    }
}
