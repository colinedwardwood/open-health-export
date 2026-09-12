// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import NetEgress
#if canImport(Network)
import Network
#endif

enum NetworkPathMonitorCache {
    #if canImport(Network)
    private static let monitor: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.start(queue: DispatchQueue(label: "app.openhealthexporter.path"))
        return monitor
    }()
    #endif

    static func conditions() -> NetworkPathConditions {
        if ProcessInfo.processInfo.environment["OHE_FORCE_METERED_PATH"] == "1" {
            return NetworkPathConditions(isExpensive: true, isConstrained: true)
        }
        #if canImport(Network)
        let path = monitor.currentPath
        return NetworkPathConditions(
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
        #else
        return .clear
        #endif
    }
}
