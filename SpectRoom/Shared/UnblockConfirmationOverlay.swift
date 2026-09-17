//
//  UnblockConfirmationOverlay.swift
//  SpectRoom
//

import SwiftUI

struct UnblockConfirmationOverlay: View {
    let firstName: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("settings.blocked.users.unblock.confirm.title".localized(with: firstName))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(SpectRoomTheme.text)
                        .padding(.bottom, 4)

                    Text("settings.blocked.users.unblock.confirm.message".localized(with: firstName))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 18)

                Divider()

                HStack(spacing: 0) {
                    Button(action: onCancel) {
                        Text("common.cancel".localized)
                            .font(.body)
                            .foregroundColor(SpectRoomTheme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(height: 44)

                    Button(action: onConfirm) {
                        Text("settings.blocked.users.unblock.action".localized)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 36)
        }
    }
}
