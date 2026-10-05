// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import CoreDomain
import Foundation

/// #52: what About must show. The licence and where the source is (ADR-0005), the
/// privacy policy App Review looks for (5.1.1(i)), terms and support.
public enum About {
    public static let repository = "https://github.com/colinedwardwood/open-health-export"

    public static let copyright = "© 2026 Colin Edward Wood and contributors"
    public static let licence =
        "Source-available under the Functional Source License 1.1 (FSL-1.1-ALv2). Each version becomes Apache-2.0 two years after release."
    public static let warranty =
        "It comes with no warranty, to the extent permitted by law. See the licence for details."
    public static let medical = "This is not a medical device. It does not diagnose or treat anything."

    public struct Link: Sendable, Equatable, Identifiable {
        public var title: String
        public var url: URL
        public var id: String { title }
    }

    /// Linked at their source in the repository until the project's own site exists;
    /// a paid app uses Apple's standard licence agreement as its terms.
    public static let links: [Link] = [
        Link(title: "Privacy policy", url: URL(string: "\(repository)/blob/main/PRIVACY.md")!),
        Link(title: "Terms of use", url: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!),
        Link(title: "Support", url: URL(string: "\(repository)/blob/main/SUPPORT.md")!),
        Link(title: "Report a security problem", url: URL(string: "\(repository)/blob/main/SECURITY.md")!),
        Link(title: "Licence", url: URL(string: "\(repository)/blob/main/LICENSE")!),
    ]

    /// The source this build was made from: the commit when known, otherwise the
    /// repository.
    public static func sourceLink(commit: String) -> URL {
        BuildIdentity.sourceLink(commit: commit).flatMap(URL.init(string:)) ?? URL(string: repository)!
    }

    public static func versionLine(version: String, build: String, commit: String) -> String {
        let short = commit.count >= 7 && commit != "unspecified" ? String(commit.prefix(7)) : "unknown commit"
        return "Version \(version) (\(build)) · \(short)"
    }
}
