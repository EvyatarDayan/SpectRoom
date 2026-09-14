//
//  PlanTierBadgeLabel.swift
//  SpectRoom
//

import SwiftUI

/// Plan label overlay for the lower-left of a profile photo (own and others).
struct ProfilePlanPhotoBadge: View {
    let tier: PlanTier
    @Environment(\.colorScheme) private var colorScheme

    private var label: String {
        let name = tier.profilePlanLabelKey.localized
        let symbol = tier.profilePlanSymbol
        return symbol.isEmpty ? name : "\(name) \(symbol)"
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.blue)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(SpectRoomTheme.card.opacity(0.94))
                    .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 1)
            )
            .overlay(
                Capsule()
                    .stroke(SpectRoomTheme.subtleBorder(for: colorScheme).opacity(0.5), lineWidth: 0.5)
            )
    }
}
