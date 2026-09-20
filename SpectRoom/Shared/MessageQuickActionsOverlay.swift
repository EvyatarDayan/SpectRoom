//
//  MessageQuickActionsOverlay.swift
//  SpectRoom
//

import SwiftUI

/// Long-press menu: one tight row of quick reactions + Copy + Report + Delete.
struct MessageQuickActionsOverlay: View {
    let canCopy: Bool
    let onReact: (String) -> Void
    let onCopy: () -> Void
    let onReport: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.28 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissThen(onCancel)
                }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    ForEach(MessageDisplay.quickReactionEmojis, id: \.self) { emoji in
                        Button {
                            dismissThen { onReact(emoji) }
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

                menuRow(
                    title: "messages.copy.menu".localized,
                    systemImage: "doc.on.doc",
                    isEnabled: canCopy,
                    isDestructive: false
                ) {
                    dismissThen(onCopy)
                }

                Divider()

                menuRow(
                    title: "messages.report.menu".localized,
                    systemImage: "exclamationmark.bubble",
                    isEnabled: true,
                    isDestructive: false
                ) {
                    dismissThen(onReport)
                }

                Divider()

                menuRow(
                    title: "messages.delete.menu".localized,
                    systemImage: "trash",
                    isEnabled: true,
                    isDestructive: true
                ) {
                    dismissThen(onDelete)
                }
            }
            .frame(width: 260)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
            .scaleEffect(appeared ? 1 : 0.82)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                appeared = true
            }
        }
    }

    @ViewBuilder
    private func menuRow(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        isDestructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body)
                Spacer(minLength: 0)
                Image(systemName: systemImage)
                    .font(.body)
            }
            .foregroundColor(
                !isEnabled
                    ? SpectRoomTheme.secondaryText.opacity(0.75)
                    : (isDestructive ? .red : SpectRoomTheme.text)
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        withAnimation(.easeOut(duration: 0.16)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            action()
        }
    }
}
