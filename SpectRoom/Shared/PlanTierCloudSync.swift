//
//  PlanTierCloudSync.swift
//  SpectRoom
//

import Foundation
import FirebaseFirestore

/// Publishes / applies billing plan (`planTier` + `billingInterval` + `subscriptionStatus`)
/// with Firestore as source of truth. Local mock billing + UserDefaults are only a cache.
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
    static func applyRemoteBillingPlan(
        tier: PlanTier,
        interval: BillingInterval?,
        status: SubscriptionStatus? = nil
    ) {
        let resolvedInterval: BillingInterval = {
            if tier == .free { return .monthly }
            return interval ?? MockBillingService.shared.currentSubscription.interval
        }()
        let resolvedStatus: SubscriptionStatus = {
            if tier == .free { return .none }
            return status ?? MockBillingService.shared.currentSubscription.status
        }()
        DiscoverDailyLimit.applyLocalPlanTier(tier)
        MockBillingService.shared.applyRemotePlanTier(
            tier,
            interval: resolvedInterval,
            status: resolvedStatus
        )
        if var user = AppStateManager.shared.currentUser {
            user.planTier = tier
            user.billingInterval = tier == .free ? nil : resolvedInterval
            user.subscriptionStatus = resolvedStatus
            AppStateManager.shared.currentUser = user
        }
        if var authUser = FirebaseAuthService.shared.currentUser {
            authUser.planTier = tier
            authUser.billingInterval = tier == .free ? nil : resolvedInterval
            authUser.subscriptionStatus = resolvedStatus
            FirebaseAuthService.shared.currentUser = authUser
        }
    }

    @MainActor
    static func pushToFirestoreIfNeeded(
        _ tier: PlanTier,
        interval: BillingInterval? = nil,
        status: SubscriptionStatus? = nil
    ) async {
        guard FirebaseAuthService.shared.auth.currentUser != nil else { return }
        markLocalPlanWrite()
        do {
            let resolvedStatus: SubscriptionStatus = {
                if let status { return status }
                if tier == .free { return .none }
                return .renewing
            }()
            var data: [String: Any] = [
                "planTier": tier.rawValue,
                "subscriptionStatus": resolvedStatus.rawValue,
            ]
            if tier == .free {
                data["billingInterval"] = ""
            } else if let interval {
                data["billingInterval"] = interval.rawValue
            }
            if resolvedStatus != .cancelled {
                data["cancelledAt"] = ""
            }
            try await FirebaseAuthService.shared.updateUserData(data)
            applyRemoteBillingPlan(
                tier: tier,
                interval: tier == .free ? nil : interval,
                status: resolvedStatus
            )
        } catch {
            print("⚠️ Failed to sync plan tier to Firestore: \(error)")
        }
    }

    @MainActor
    static func pushCancellationToFirestore(
        tier: PlanTier,
        interval: BillingInterval,
        cancelledAt: Date = Date()
    ) async {
        guard FirebaseAuthService.shared.auth.currentUser != nil else { return }
        markLocalPlanWrite()
        do {
            let data: [String: Any] = [
                "planTier": tier.rawValue,
                "billingInterval": interval.rawValue,
                "subscriptionStatus": SubscriptionStatus.cancelled.rawValue,
                "cancelledAt": cancelledAt.timeIntervalSince1970,
            ]
            try await FirebaseAuthService.shared.updateUserData(data)
            applyRemoteBillingPlan(tier: tier, interval: interval, status: .cancelled)
        } catch {
            print("⚠️ Failed to sync cancellation to Firestore: \(error)")
        }
    }

    /// Parse billing fields from a user document payload.
    static func parseBillingPlan(
        from userData: [String: Any]
    ) -> (tier: PlanTier, interval: BillingInterval?, status: SubscriptionStatus?) {
        let tier = PlanTier(rawValue: (userData["planTier"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            ?? .free
        let interval: BillingInterval? = {
            guard tier != .free else { return nil }
            guard let raw = userData["billingInterval"] as? String else { return .monthly }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return .monthly }
            return BillingInterval(rawValue: trimmed) ?? .monthly
        }()
        let status: SubscriptionStatus? = {
            guard let raw = userData["subscriptionStatus"] as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            return SubscriptionStatus(rawValue: trimmed)
        }()
        return (tier, interval, status)
    }
}
