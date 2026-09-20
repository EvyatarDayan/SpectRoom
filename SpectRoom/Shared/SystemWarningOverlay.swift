import SwiftUI

/// Full-screen moderation notice for the signed-in user (warning / freeze / ban / unban).
struct SystemWarningOverlay: View {
    let title: String
    let message: String
    var acceptLabel: String = "admin.warning.popup.accept".localized
    var requiresCheckbox: Bool = true
    var acceptButtonColor: Color = .orange
    var secondaryLinkTitle: String? = nil
    var onSecondaryLink: (() -> Void)? = nil
    let onDismiss: () -> Void

    @State private var didAccept = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .allowsHitTesting(true)

            VStack(spacing: 16) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.text)
                    .padding(.horizontal, 20)
                    .padding(.top, 22)

                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)

                if requiresCheckbox {
                    Button {
                        didAccept.toggle()
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: didAccept ? "checkmark.square.fill" : "square")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(didAccept ? acceptButtonColor : SpectRoomTheme.secondaryText)
                                .frame(width: 22, height: 22)

                            Text(acceptLabel)
                                .font(.subheadline)
                                .foregroundColor(SpectRoomTheme.text)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 20)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDismiss) {
                        Text("common.ok".localized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(didAccept ? .white : SpectRoomTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(didAccept ? acceptButtonColor : Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!didAccept)
                    .padding(.horizontal, 20)
                    .padding(.bottom, secondaryLinkTitle == nil ? 20 : 4)
                } else {
                    Button(action: onDismiss) {
                        Text(acceptLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(acceptButtonColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, secondaryLinkTitle == nil ? 20 : 4)
                }

                if let secondaryLinkTitle, let onSecondaryLink {
                    Button(action: onSecondaryLink) {
                        Text(secondaryLinkTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.blue)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 20)
                }
            }
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 36)
        }
        .allowsHitTesting(true)
    }
}
