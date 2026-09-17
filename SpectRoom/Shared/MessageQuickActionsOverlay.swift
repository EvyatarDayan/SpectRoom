//
//  MessageQuickActionsOverlay.swift
//  SpectRoom
//

import SwiftUI

/// Long-press menu: one tight row of quick reactions + Report + Delete.
struct MessageQuickActionsOverlay: View {
    let onReact: (String) -> Void
    let onReport: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ForEach(MessageDisplay.quickReactionEmojis, id: \.self) { emoji in
                        Button {
                            onReact(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 28))
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(emoji)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider()

                Button(action: onReport) {
                    HStack {
                        Text("messages.report.menu".localized)
                            .font(.body)
                        Spacer(minLength: 0)
                        Image(systemName: "exclamationmark.bubble")
                            .font(.body)
                    }
                    .foregroundColor(SpectRoomTheme.text)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()

                Button(role: .destructive, action: onDelete) {
                    HStack {
                        Text("messages.delete.menu".localized)
                            .font(.body)
                        Spacer(minLength: 0)
                        Image(systemName: "trash")
                            .font(.body)
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: 260)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
        }
    }
}
