//
//  PlanTierCloudSync.swift
//  SpectRoom
//

import Foundation
import FirebaseFirestore

/// Publishes / applies billing plan (`planTier` + `billingInterval`) with Firestore as source of truth.
/// Local mock billing + UserDefaults are only a cache (Android parity).
enum PlanTierCloudSync {
    /// Ignore remote snapshots for a short window after this device writes a plan change.
    private static let localWriteGraceSeconds: TimeInterval = 15
    private static var localWriteAt: Date?

    @MainActor
    static func markLocalPlanWrite() {
        localWriteAt = Date()
    }

    @MainActor
    static var isWithinLocalPlanWriteGrace: Bool {
        guard let localWriteAt else { return false }
        return Date().timeIntervalSince(localWriteAt) < localWriteGraceSeconds
    }

    /// Apply Firestore values to local cache + mock billing (no cloud write).
    @MainActor
    static func applyRemoteBillingPlan(tier: PlanTier, interval: BillingInterval?) {
        let resolvedInterval: BillingInterval = {
            if tier == .free { return .monthly }
            return interval ?? MockBillingService.shared.currentSubscription.interval
        }()
        DiscoverDailyLimit.applyLocalPlanTier(tier)
        MockBillingService.shared.applyRemotePlanTier(tier, interval: resolvedInterval)
        if var user = AppStateManager.shared.currentUser {
            user.planTier = tier
            user.billingInterval = tier == .free ? nil : resolvedInterval
            AppStateManager.shared.currentUser = user
        }
        if var authUser = FirebaseAuthService.shared.currentUser {
            authUser.planTier = tier
            authUser.billingInterval = tier == .free ? nil : resolvedInterval
            FirebaseAuthService.shared.currentUser = authUser
        }
    }

    @MainActor
    static func pushToFirestoreIfNeeded(_ tier: PlanTier, interval: BillingInterval? = nil) async {
        guard FirebaseAuthService.shared.auth.currentUser != nil else { return }
        markLocalPlanWrite()
        do {
            var data: [String: Any] = ["planTier": tier.rawValue]
            if tier == .free {
                data["billingInterval"] = ""
            } else if let interval {
                data["billingInterval"] = interval.rawValue
            }
            try await FirebaseAuthService.shared.updateUserData(data)
            applyRemoteBillingPlan(tier: tier, interval: tier == .free ? nil : interval)
        } catch {
            print("⚠️ Failed to sync plan tier to Firestore: \(error)")
        }
    }

    /// Parse `planTier` / `billingInterval` from a user document payload.
    static func parseBillingPlan(from userData: [String: Any]) -> (tier: PlanTier, interval: BillingInterval?) {
        let tier = PlanTier(rawValue: (userData["planTier"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            ?? .free
        let interval: BillingInterval? = {
            guard tier != .free else { return nil }
            guard let raw = userData["billingInterval"] as? String else { return .monthly }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return .monthly }
            return BillingInterval(rawValue: trimmed) ?? .monthly
        }()
        return (tier, interval)
    }
}
