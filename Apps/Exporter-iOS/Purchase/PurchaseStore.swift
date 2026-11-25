// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import Foundation
import Observation
import StoreKit

/// #68: the one-time unlock (D-08a, D-08b), on StoreKit 2. This folder is the only
/// place StoreKit may appear (policycheck). Source builds never ask StoreKit
/// anything: without OHE_STORE_BUILD, everything is unlocked.
@MainActor
@Observable
final class PurchaseStore {
    static let shared = PurchaseStore()
    static let productID = IdentifierRoot.qualified("unlock")

    private(set) var state: UnlockState
    private(set) var product: Product?
    private(set) var purchasing = false
    private(set) var message: String?

    @ObservationIgnored private var updates: Task<Void, Never>?

    private init() {
        state = Self.cachedState()
    }

    static var isStoreBuild: Bool {
        #if DEBUG
        if let forced = UITestFixtures.unlockState { return forced != .sourceBuild }
        #endif
        #if OHE_STORE_BUILD
        return true
        #else
        return false
        #endif
    }

    /// The last answer, readable from a background wake without waiting on StoreKit.
    nonisolated static func cachedState() -> UnlockState {
        #if DEBUG
        if let forced = UITestFixtures.unlockState { return forced }
        #endif
        #if OHE_STORE_BUILD
        let raw = UserDefaults.standard.string(forKey: SettingKey.unlockLastKnown.rawValue) ?? ""
        return UnlockState(rawValue: raw) ?? .locked
        #else
        return .sourceBuild
        #endif
    }

    /// Starts listening for purchases made elsewhere, Family Sharing changes and
    /// refunds, and refreshes once.
    func start() {
        guard Self.isStoreBuild, updates == nil else { return }
        #if DEBUG
        if UITestFixtures.unlockState != nil { return }
        #endif
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case let .verified(transaction) = update {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        guard Self.isStoreBuild else {
            state = .sourceBuild
            return
        }
        #if DEBUG
        if let forced = UITestFixtures.unlockState { state = forced; return }
        #endif
        var entitled = false
        var revoked = false
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  transaction.productID == Self.productID else { continue }
            if transaction.revocationDate != nil {
                revoked = true
            } else {
                entitled = true
            }
        }
        if !entitled, !revoked,
           let latest = await Transaction.latest(for: Self.productID),
           case let .verified(transaction) = latest,
           transaction.revocationDate != nil {
            revoked = true
        }
        set(UnlockDecision.state(
            isStoreBuild: true,
            hasEntitlement: entitled,
            wasRevoked: revoked && !entitled,
            lastKnown: state
        ))
    }

    func loadProduct() async {
        guard Self.isStoreBuild, product == nil else { return }
        product = try? await Product.products(for: [Self.productID]).first
    }

    func purchase() async {
        guard let product else {
            message = "The App Store isn't reachable right now. Try again in a moment."
            return
        }
        purchasing = true
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case let .success(.verified(transaction)):
                await transaction.finish()
                await refresh()
                message = nil
            case .success(.unverified):
                message = "The App Store couldn't verify the purchase. You haven't been charged twice; try Restore purchase."
            case .pending:
                message = "The purchase is waiting for approval, such as Ask to Buy."
            case .userCancelled:
                message = nil
            @unknown default:
                message = nil
            }
        } catch {
            message = "The purchase didn't go through. Nothing was charged."
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refresh()
            message = state.isUnlocked ? nil : "No purchase was found for this Apple Account."
        } catch {
            message = "The App Store couldn't be reached to restore. Try again later."
        }
    }

    private func set(_ new: UnlockState) {
        state = new
        UserDefaults.standard.set(new.rawValue, forKey: SettingKey.unlockLastKnown.rawValue)
    }
}
