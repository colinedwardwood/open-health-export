// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import CorrectnessEngine
import EnginePorts
import MetricCatalog
import Observation
import SwiftUI

/// #58: a complete export of made-up data, for anyone without Health data to try it
/// with. Nothing here reads Apple Health, and nothing is written to the person's
/// archive: the files go to a private folder that Delete everything clears.
@MainActor
@Observable
final class SampleDataModel {
    struct Row: Identifiable {
        let id: MetricID
        let name: String
        let value: String
        let unit: String?
        let when: Date
    }

    enum Phase: Equatable {
        case running
        case done
        case failed
    }

    private(set) var phase = Phase.running
    private(set) var rows: [Row] = []

    func run() async {
        phase = .running
        let date = Date()
        do {
            _ = try await AppExport.service.runDemoDataset(at: date)
            let source = DemoSampleSource(now: date)
            var rows: [Row] = []
            for declaration in MetricCatalog.selectable where declaration.kind == "sample.quantity" {
                let page = try await source.page(metric: declaration.id, afterAnchor: nil)
                guard let latest = page.samples.max(by: { $0.start < $1.start }),
                      let when = try? Date(latest.start, strategy: .iso8601)
                else { continue }
                rows.append(Row(
                    id: declaration.id,
                    name: declaration.displayName,
                    value: latest.value.formatted(.number.precision(.fractionLength(0...1))),
                    unit: DataSelection.unitLabel(declaration.wireUnit),
                    when: when
                ))
            }
            self.rows = rows
            phase = .done
        } catch {
            phase = .failed
        }
    }
}

struct SampleDataScreen: View {
    @State private var model = SampleDataModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "flask").accessibilityHidden(true)
                        Text(DemoCopy.banner)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("sample-banner")
                    }
                } footer: {
                    SectionFooter("Made up for this demo. It is kept apart from your archive and removed by Delete everything.")
                }
                switch model.phase {
                case .running:
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Exporting sample data…")
                        }
                        .accessibilityElement(children: .combine)
                    }
                case .failed:
                    Section {
                        Text("The sample export didn't finish. Try again.")
                        Button("Try again") { Task { await model.run() } }
                            .accessibilityIdentifier("sample-retry")
                    }
                case .done:
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle").accessibilityHidden(true)
                            Text("Sample export finished")
                                .accessibilityIdentifier("sample-done")
                        }
                    }
                    Section {
                        ForEach(model.rows) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(row.name)
                                    Spacer()
                                    Text([row.value, row.unit].compactMap { $0 }.joined(separator: " "))
                                        .monospacedDigit()
                                }
                                Text(row.when, format: .dateTime.day().month().hour().minute())
                                    .metadata()
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("sample-value-\(row.id.rawValue)")
                        }
                    } header: {
                        SectionTitle("Latest sample values")
                    }
                }
            }
            .navigationTitle("Sample data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("sample-close")
                }
            }
            .task { await model.run() }
        }
    }
}
