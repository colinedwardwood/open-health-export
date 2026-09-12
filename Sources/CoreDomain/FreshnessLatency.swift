// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum FreshnessClass: String, Sendable, Codable, CaseIterable {
    case a
    case b
    case c
    case d
}

/// One confirmed run's decomposed R-24 latency evidence.
///
/// The record is deliberately failable: incomplete, negative, or non-finite timing data
/// is not evidence and must not silently enter a local percentile.
public struct RunFreshnessLatency: Sendable, Equatable {
    public var runID: RunID
    public var destinationID: String
    public var freshnessClass: FreshnessClass
    public var firstObservedAtEpoch: TimeInterval
    public var observationLatencySeconds: TimeInterval
    public var deliveryLatencySeconds: TimeInterval
    public var recordedAtEpoch: TimeInterval

    public init?(
        runID: RunID,
        destinationID: String,
        freshnessClass: FreshnessClass,
        firstObservedAtEpoch: TimeInterval,
        observationLatencySeconds: TimeInterval,
        deliveryLatencySeconds: TimeInterval,
        recordedAtEpoch: TimeInterval
    ) {
        guard !destinationID.isEmpty,
              firstObservedAtEpoch.isFinite,
              observationLatencySeconds.isFinite,
              deliveryLatencySeconds.isFinite,
              recordedAtEpoch.isFinite,
              observationLatencySeconds >= 0,
              deliveryLatencySeconds >= 0,
              recordedAtEpoch >= firstObservedAtEpoch
        else {
            return nil
        }
        self.runID = runID
        self.destinationID = destinationID
        self.freshnessClass = freshnessClass
        self.firstObservedAtEpoch = firstObservedAtEpoch
        self.observationLatencySeconds = observationLatencySeconds
        self.deliveryLatencySeconds = deliveryLatencySeconds
        self.recordedAtEpoch = recordedAtEpoch
    }

    public var totalLatencySeconds: TimeInterval {
        observationLatencySeconds + deliveryLatencySeconds
    }
}
