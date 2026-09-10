//
//  PlanTierBadgeLabel.swift
//  SpectRoom
//

import SwiftUI

/// Compact plan name + stars badge (tab bar Discover, settings Account & Billing).
struct PlanTierBadgeLabel: View {
    let tier: PlanTier
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 1) {
            Text(tier.displayNameKey.localized)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(tier.titleStars)
                .font(.system(size: 9))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundColor(.blue)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(SpectRoomTheme.card.opacity(0.94))
                .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 1)
        )
        .overlay(
            Capsule()
                .stroke(SpectRoomTheme.subtleBorder(for: colorScheme).opacity(0.5), lineWidth: 0.5)
        )
        .fixedSize()
    }
}
