//
//  SpectRoomNoticePopup.swift
//  SpectRoom
//

import SwiftUI

struct SpectRoomNoticePopup: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(SpectRoomTheme.text)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onDismiss) {
                    Text("auth.ok".localized)
                        .font(.body.weight(.semibold))
                        .foregroundColor(SpectRoomTheme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            .padding(.horizontal, 40)
        }
    }
}
