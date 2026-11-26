// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import SwiftUI
import UIKit

/// Settings > Diagnostics: build, last exports, launch failures and network activity,
/// and a redacted text report the person can share with support. The screen lists the
/// same lines the share sheet carries, so what is shown is what is sent.
struct DiagnosticsScreen: View {
    @State private var report: DiagnosticsReport?
    @State private var failed = false
    @State private var confirmingShare = false
    @State private var sharing = false

    var body: some View {
        List {
            if let report {
                DiagnosticsSection(title: "Build", lines: report.buildLines, id: "diagnostics-build")
                DiagnosticsSection(title: "Last exports", lines: report.exportLines, id: "diagnostics-exports")
                DiagnosticsSection(title: "Launch failures", lines: report.launchLines, id: "diagnostics-launch")
                DiagnosticsSection(title: "Network activity", lines: report.networkLines, id: "diagnostics-network")
                Section {
                    Button {
                        confirmingShare = true
                    } label: {
                        Label("Share diagnostics", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("diagnostics-share")
                } footer: {
                    SectionFooter("Share this with support along with what you expected to happen. It holds no health values, hostnames, credentials or tokens, and network activity shows counts only. It is not a crash log: if the app crashed, see the crash-log guide in the support docs.")
                }
            } else if failed {
                Section {
                    Text("Diagnostics couldn't be read.")
                        .accessibilityIdentifier("diagnostics-error")
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { load() }
        .confirmationDialog("Share diagnostics?", isPresented: $confirmingShare, titleVisibility: .visible) {
            Button("Share") { sharing = true }
                .accessibilityIdentifier("diagnostics-share-confirm")
        } message: {
            Text(localized(DiagnosticsReport.shareDisclosure))
        }
        .sheet(isPresented: $sharing) {
            if let report {
                ActivityView(text: report.text).ignoresSafeArea()
            }
        }
    }

    private func load() {
        do {
            report = try AppStatus.transparency.diagnosticsReport(
                environment: AppStatus.diagnosticEnvironment(),
                launchIssues: AppStatus.launchFailures.issues()
            )
        } catch {
            failed = true
        }
    }
}

/// One list section of report lines. Lines are technical text, so they stay in the
/// report's own English and wrap at any Dynamic Type size.
private struct DiagnosticsSection: View {
    let title: LocalizedStringKey
    let lines: [String]
    let id: String

    var body: some View {
        Section {
            // A row rather than a list header: the header's own chrome fails the contrast audit.
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: DiagnosticsReport.wrappable(line))
                    .font(.footnote)
            }
            .accessibilityIdentifier(id)
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context: Context) {}
}
