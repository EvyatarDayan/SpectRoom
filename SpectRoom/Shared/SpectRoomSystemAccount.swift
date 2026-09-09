//
//  SpectRoomSystemAccount.swift
//  SpectRoom
//

import Foundation
import SwiftUI

/// Reserved sender for official SpectRoom messages (admin warnings, etc.).
enum SpectRoomSystemAccount {
    static let userId = "spectroom-official"
    static let displayName = "SpectRoom"

    static func isSystemAccount(_ userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        return userId == Self.userId
    }
}

struct SpectRoomSystemAvatar: View {
    var size: CGFloat = 44

    var body: some View {
        Image("Logo1")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .accessibilityLabel(SpectRoomSystemAccount.displayName)
    }
}
