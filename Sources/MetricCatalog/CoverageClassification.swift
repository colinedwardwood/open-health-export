// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation

/// UX-05 / FIX-A02: after authorisation, each selected type is exactly one of
/// three states. Limited history is the only positively detectable restriction;
/// full access and denial both look like nothing returned (R-60).
public enum CoverageState: Sendable, Equatable {
    case dataAvailable(sampleCount: Int, latestStart: String)
    case limitedWindow(earliestAuthorizedDay: String, sampleCount: Int, latestStart: String?)
    case nothingReturned
}

public struct CoverageObservation: Sendable, Equatable {
    public var sampleCount: Int
    public var latestStart: String?
    public var earliestAuthorizedDay: String?

    public init(
        sampleCount: Int = 0,
        latestStart: String? = nil,
        earliestAuthorizedDay: String? = nil
    ) {
        self.sampleCount = sampleCount
        self.latestStart = latestStart
        self.earliestAuthorizedDay = earliestAuthorizedDay
    }
}

public enum CoverageClassification {
    public static func classify(_ observation: CoverageObservation) -> CoverageState {
        classify(
            sampleCount: observation.sampleCount,
            latestStart: observation.latestStart,
            earliestAuthorizedDay: observation.earliestAuthorizedDay
        )
    }

    public static func classify(
        sampleCount: Int,
        latestStart: String?,
        earliestAuthorizedDay: String?
    ) -> CoverageState {
        if let day = earliestAuthorizedDay, !day.isEmpty {
            return .limitedWindow(
                earliestAuthorizedDay: day,
                sampleCount: max(0, sampleCount),
                latestStart: latestStart
            )
        }
        if sampleCount > 0 {
            return .dataAvailable(
                sampleCount: sampleCount,
                latestStart: latestStart ?? ""
            )
        }
        return .nothingReturned
    }

    public static func subtitle(_ state: CoverageState) -> String {
        switch state {
        case .dataAvailable(let count, let latest):
            if latest.isEmpty {
                return "\(count) samples"
            }
            return "\(count) samples, latest \(latest)"
        case .limitedWindow(let day, _, _):
            return limitedWindowCopy(day: day)
        case .nothingReturned:
            return DataBrowser.nothingReturnedCopy
        }
    }

    public static func limitedWindowCopy(day: String) -> String {
        "Access limited to data from \(day) onward. Earlier samples stay in Health."
    }
}
