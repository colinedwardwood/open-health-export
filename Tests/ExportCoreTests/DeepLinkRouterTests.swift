// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import CoreDomain
import Foundation
import Watchdog
import XCTest

final class DeepLinkRouterTests: XCTestCase {
    func testFailureNotificationOpensTheErrorOnStatus() {
        let url = UserFacingErrorRoute(destinationID: "mqtt", archetype: .timeout).url
        XCTAssertEqual(
            DeepLinkRouter.target(for: url, disclosureAcknowledged: true),
            NavigationTarget(tab: .status, path: [.destinationError(id: "mqtt", archetype: .timeout)])
        )
    }

    func testErrorLinkWithoutArchetypeStillOpensTheDestinationError() {
        let url = UserFacingErrorRoute(destinationID: "https").url
        XCTAssertEqual(
            DeepLinkRouter.target(for: url, disclosureAcknowledged: true)?.path,
            [.destinationError(id: "https", archetype: nil)]
        )
    }

    func testWidgetLinkOpensTheDestinationOrStatus() {
        XCTAssertEqual(
            DeepLinkRouter.target(for: WidgetStatusRoute(destinationID: "files").url, disclosureAcknowledged: true),
            NavigationTarget(tab: .status, path: [.destination(id: "files")])
        )
        XCTAssertEqual(
            DeepLinkRouter.target(for: WidgetStatusRoute().url, disclosureAcknowledged: true),
            NavigationTarget(tab: .status)
        )
    }

    func testExportNowAsksForAnExport() {
        XCTAssertEqual(
            DeepLinkRouter.target(for: ExportNowRoute().url, disclosureAcknowledged: true),
            NavigationTarget(tab: .status, exportNow: true)
        )
    }

    func testNothingOpensOrExportsBeforeTheDisclosure() {
        for url in [
            UserFacingErrorRoute(destinationID: "mqtt", archetype: .timeout).url,
            WidgetStatusRoute(destinationID: "files").url,
            ExportNowRoute().url,
        ] {
            XCTAssertEqual(
                DeepLinkRouter.target(for: url, disclosureAcknowledged: false),
                NavigationTarget(tab: .status),
                url.absoluteString
            )
        }
    }

    func testForeignLinksAreIgnored() {
        XCTAssertNil(DeepLinkRouter.target(
            for: URL(string: "https://example.com/status")!,
            disclosureAcknowledged: true
        ))
        XCTAssertNil(DeepLinkRouter.target(
            for: URL(string: "\(WidgetStatusRoute.scheme)://unknown")!,
            disclosureAcknowledged: true
        ))
    }
}
