// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import CorrectnessEngine
import Foundation
import Observation

/// Runs the one backfill pipeline (`ExportService.runBackfill`) for the Backfill
/// screen and keeps what it shows: progress, the result, or the five-part error.
@MainActor
@Observable
final class BackfillModel {
    enum Phase: Equatable {
        case idle
        case running(progress: String)
        case finished(BackfillReport)
        case cancelled
    }

    private(set) var phase: Phase = .idle
    private(set) var error: UserFacingErrorObject?
    private var work: Task<Void, Never>?

    var isRunning: Bool {
        if case .running = phase { true } else { false }
    }

    func start(range: BackfillRange, mode: BackfillMode, onFinished: @escaping @MainActor () -> Void) {
        guard !isRunning else { return }
        error = nil
        phase = .running(progress: "")
        work = Task {
            do {
                let lines = try await AppExport.service.runBackfill(mode: mode, range: range) { text in
                    await MainActor.run { self.progress(text) }
                }
                phase = .finished(BackfillReport.parse(lines))
            } catch is CancellationError {
                phase = .cancelled
            } catch {
                self.error = UserFacingFailure.object(for: error, destinationLabel: "your destination")
                phase = .idle
            }
            work = nil
            onFinished()
        }
    }

    /// The job is saved as it goes, so cancelling parks it and the same range resumes.
    func cancel() {
        work?.cancel()
    }

    private func progress(_ text: String) {
        if isRunning { phase = .running(progress: text) }
    }
}
