// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import Foundation
import Testing

@Test func aboutLinksThePrivacyPolicyTermsSupportAndLicence() {
    let titles = About.links.map(\.title)
    for required in ["Privacy policy", "Terms of use", "Support", "Licence"] {
        #expect(titles.contains(required), "\(required)")
    }
    for link in About.links {
        #expect(link.url.scheme == "https", "\(link.title)")
    }
}

@Test func theSourceLinkNamesTheCommitWhenItIsKnown() {
    let commit = "872c94b0e5204e3956bafa8c47ed6c94f6a1d8a"
    #expect(About.sourceLink(commit: commit).absoluteString.hasSuffix("/commit/\(commit)"))
    #expect(About.sourceLink(commit: "unspecified").absoluteString == About.repository)
    #expect(About.versionLine(version: "1.0", build: "42", commit: commit) == "Version 1.0 (42) · 872c94b")
    #expect(About.versionLine(version: "1.0", build: "42", commit: "unspecified").hasSuffix("unknown commit"))
}

@Test func aboutCarriesTheLegalNotices() {
    #expect(About.licence.contains("Affero"))
    #expect(About.warranty.contains("no warranty"))
    #expect(About.medical.contains("not a medical device"))
}
