// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import SwiftUI

/// #68: the unlock in Settings. What it adds, its price, Buy and Restore. Mockup:
/// design canvas board 8.
struct UnlockSection: View {
    @State private var store = PurchaseStore.shared

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.state.isUnlocked ? "Automatic exports are on" : "Unlock automatic exports")
                    .font(.headline)
                Text(UnlockDecision.summary(store.state))
                    .foregroundStyle(.secondaryText)
                    .accessibilityIdentifier("unlock-summary")
            }
            .accessibilityElement(children: .combine)
            if !store.state.isUnlocked {
                // In a stack, as Export now is: a prominent button as a bare list row
                // doesn't scale with Dynamic Type.
                VStack(spacing: 12) {
                    Button {
                        Task { await store.purchase() }
                    } label: {
                        Text(store.product.map { "Unlock for \($0.displayPrice)" } ?? "Unlock")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.purchasing)
                    .accessibilityIdentifier("unlock-buy")
                }
                .padding(.vertical, 4)
                Button("Restore purchase") { Task { await store.restore() } }
                    .accessibilityIdentifier("unlock-restore")
            }
            if let message = store.message {
                Text(message)
                    .foregroundStyle(.secondaryText)
                    .accessibilityIdentifier("unlock-message")
            }
        } footer: {
            if store.state != .sourceBuild {
                SectionFooter("One payment, no subscription. Family Sharing is included. Security notices and updates are never part of the unlock.")
            }
        }
        .task { await store.loadProduct() }
    }
}
