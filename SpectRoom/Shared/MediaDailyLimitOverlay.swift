import SwiftUI

struct MediaDailyLimitOverlay: View {
    var title: String = "messages.media.limit.title".localized
    let message: String
    var showsPlansButton: Bool = true
    var dismissButtonTitle: String = "messages.media.limit.not.now".localized
    var plansButtonTitle: String = "messages.media.limit.view.plans".localized
    let onGotIt: () -> Void
    let onPlans: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var panelBackground: Color {
        colorScheme == .light ? Color.white.opacity(0.94) : Color(.systemGray6).opacity(0.95)
    }

    private var primaryText: Color {
        colorScheme == .light ? .black : .white
    }

    private var secondaryText: Color {
        colorScheme == .light ? Color.black.opacity(0.55) : Color.white.opacity(0.7)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .light ? 0.28 : 0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onGotIt)

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(message)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(secondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Button(action: onGotIt) {
                        Text(dismissButtonTitle)
                            .font(.body.weight(.semibold))
                            .foregroundColor(primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if showsPlansButton {
                        Button(action: onPlans) {
                            Text(plansButtonTitle)
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 28)
        }
    }
}
