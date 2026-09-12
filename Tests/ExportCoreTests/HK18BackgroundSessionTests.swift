// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation
import NetEgress
import Testing

@Test func hk18ExportPayloadsUploadFromFileAndNameBackgroundSessions() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let transport = try String(
        contentsOf: root.appendingPathComponent("Sources/NetEgress/URLSessionHTTPTransport.swift"),
        encoding: .utf8
    )
    let background = try String(
        contentsOf: root.appendingPathComponent("Sources/NetEgress/HTTPBackgroundSession.swift"),
        encoding: .utf8
    )
    let runner = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/CorrectnessEngine/PendingDeliveryRunner.swift"
        ),
        encoding: .utf8
    )
    let app = try String(
        contentsOf: root.appendingPathComponent(
            "Apps/Exporter-iOS/AppLifecycleCoordinator.swift"
        ),
        encoding: .utf8
    )
    #expect(transport.contains("session.upload(for: urlRequest, fromFile: request.bodyFile)"))
    #expect(!transport.contains("httpBody = try Data(contentsOf: request.bodyFile)"))
    #expect(background.contains("URLSessionConfiguration.background(withIdentifier: identifier)"))
    #expect(background.contains("configuration.isDiscretionary = schedule == .discretionaryRetry"))
    #expect(HTTPBackgroundSession.identifier(for: .immediate) == HTTPBackgroundSession.immediateIdentifier)
    #expect(
        HTTPBackgroundSession.identifier(for: .discretionaryRetry)
            == HTTPBackgroundSession.retryIdentifier
    )
    #expect(runner.contains("HTTPTransferSchedule.$current.withValue(.discretionaryRetry)"))
    #expect(app.contains("handleEventsForBackgroundURLSession"))
    #expect(app.contains("HTTPBackgroundSession.finishEvents"))
    #expect(HTTPTransferSchedule.current == .immediate)
}

@Test func hk18RetryWakeMarksTheTransferDiscretionary() {
    #expect(HTTPTransferSchedule.current == .immediate)
    let nested = HTTPTransferSchedule.$current.withValue(.discretionaryRetry) {
        HTTPTransferSchedule.current
    }
    #expect(nested == .discretionaryRetry)
    #expect(HTTPTransferSchedule.current == .immediate)
}
