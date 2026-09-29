// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import CoreDomain
import Foundation
import Testing
import Watchdog

@Test func failureNotificationOpensTheErrorOnStatus() {
    let url = UserFacingErrorRoute(destinationID: "mqtt", archetype: .timeout).url
    #expect(
        DeepLinkRouter.target(for: url, disclosureAcknowledged: true)
        == NavigationTarget(tab: .status, path: [.destinationError(id: "mqtt", archetype: .timeout)])
    )
}

@Test func errorLinkWithoutArchetypeStillOpensTheDestinationError() {
    let url = UserFacingErrorRoute(destinationID: "https").url
    #expect(
        DeepLinkRouter.target(for: url, disclosureAcknowledged: true)?.path
        == [.destinationError(id: "https", archetype: nil)]
    )
}

@Test func widgetLinkOpensTheDestinationOrStatus() {
    #expect(
        DeepLinkRouter.target(for: WidgetStatusRoute(destinationID: "files").url, disclosureAcknowledged: true)
        == NavigationTarget(tab: .status, path: [.destination(id: "files")])
    )
    #expect(
        DeepLinkRouter.target(for: WidgetStatusRoute().url, disclosureAcknowledged: true)
        == NavigationTarget(tab: .status)
    )
}

@Test func exportNowAsksForAnExport() {
    #expect(
        DeepLinkRouter.target(for: ExportNowRoute().url, disclosureAcknowledged: true)
        == NavigationTarget(tab: .status, exportNow: true)
    )
}

@Test func nothingOpensOrExportsBeforeTheDisclosure() {
    for url in [
        UserFacingErrorRoute(destinationID: "mqtt", archetype: .timeout).url,
        WidgetStatusRoute(destinationID: "files").url,
        ExportNowRoute().url,
    ] {
        #expect(
            DeepLinkRouter.target(for: url, disclosureAcknowledged: false)
            == NavigationTarget(tab: .status),
            Comment(rawValue: url.absoluteString)
        )
    }
}

@Test func foreignLinksAreIgnored() {
    #expect(DeepLinkRouter.target(
        for: URL(string: "https://example.com/status")!,
        disclosureAcknowledged: true
    ) == nil)
    #expect(DeepLinkRouter.target(
        for: URL(string: "\(WidgetStatusRoute.scheme)://unknown")!,
        disclosureAcknowledged: true
    ) == nil)
}
