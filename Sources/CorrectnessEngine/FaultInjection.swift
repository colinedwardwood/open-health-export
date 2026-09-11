// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if DEBUG
/// R-83's six stable pipeline locations. The injected vocabulary lives in test support; release
/// builds contain neither this protocol nor calls to it.
public enum ExportFaultLocation: String, Sendable, CaseIterable, Hashable {
    case afterRead
    case afterTransform
    case afterEnqueueBeforeDestinationWrite
    case afterDestinationWriteBeforeAck
    case afterAckBeforeRelease
    case duringAnchorPersist
}

public protocol ExportFaultInjector: Sendable {
    func hit(_ location: ExportFaultLocation) throws
}

public struct NoExportFaults: ExportFaultInjector {
    public init() {}
    public func hit(_ location: ExportFaultLocation) throws {
        _ = location
    }
}
#endif
