//
//  MessageDeleteOptionsOverlay.swift
//  SpectRoom
//

import SwiftUI

enum MessageDeleteOption: String, CaseIterable, Identifiable {
    case forMe
    case forEveryone

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .forMe: return "messages.delete.option.for.me"
        case .forEveryone: return "messages.delete.option.for.everyone"
        }
    }
}

/// Centered alert: choose Delete for me / Delete for everyone, then Cancel or Delete.
struct MessageDeleteOptionsOverlay: View {
    /// When false, "Delete for everyone" stays visible but disabled (time window expired).
    let allowsDeleteForEveryone: Bool
    let onDelete: (MessageDeleteOption) -> Void
    let onCancel: () -> Void

    @State private var selected: MessageDeleteOption = .forMe

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Text("messages.delete.title".localized)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(SpectRoomTheme.text)
                        .padding(.bottom, 2)

                    VStack(spacing: 8) {
                        ForEach(MessageDeleteOption.allCases) { option in
                            let isEnabled = option != .forEveryone || allowsDeleteForEveryone
                            Button {
                                guard isEnabled else { return }
                                selected = option
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selected == option ? "largecircle.fill.circle" : "circle")
                                        .font(.title3)
                                        .foregroundColor(
                                            !isEnabled
                                                ? SpectRoomTheme.secondaryText.opacity(0.45)
                                                : (selected == option ? .blue : SpectRoomTheme.secondaryText)
                                        )
                                    Text(option.titleKey.localized)
                                        .font(.body)
                                        .foregroundColor(
                                            isEnabled
                                                ? SpectRoomTheme.text
                                                : SpectRoomTheme.secondaryText.opacity(0.45)
                                        )
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!isEnabled)
                            .accessibilityLabel(option.titleKey.localized)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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

                    Button {
                        let choice: MessageDeleteOption = {
                            if selected == .forEveryone, !allowsDeleteForEveryone {
                                return .forMe
                            }
                            return selected
                        }()
                        onDelete(choice)
                    } label: {
                        Text("messages.delete.confirm".localized)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.red)
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
        .onAppear {
            selected = .forMe
        }
        .onChange(of: allowsDeleteForEveryone) { _, allowed in
            if !allowed, selected == .forEveryone {
                selected = .forMe
            }
        }
    }
}
