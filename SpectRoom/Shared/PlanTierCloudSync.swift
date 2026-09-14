//
//  PlanTierCloudSync.swift
//  SpectRoom
//

import Foundation

/// Publishes the current plan tier to the user document so others can show it on profiles.
enum PlanTierCloudSync {
    @MainActor
    static func pushToFirestoreIfNeeded(_ tier: PlanTier) async {
        guard FirebaseAuthService.shared.auth.currentUser != nil else { return }
        do {
            try await FirebaseAuthService.shared.updateUserData(["planTier": tier.rawValue])
            if var user = AppStateManager.shared.currentUser {
                user.planTier = tier
                AppStateManager.shared.currentUser = user
            }
            if var authUser = FirebaseAuthService.shared.currentUser {
                authUser.planTier = tier
                FirebaseAuthService.shared.currentUser = authUser
            }
        } catch {
            print("⚠️ Failed to sync planTier to Firestore: \(error)")
        }
    }
}
