//
//  PhotoShareWarningOverlay.swift
//  SpectRoom
//

import SwiftUI

struct PhotoShareWarningOverlay: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    private let bulletKeys = [
        "messages.photo.share.warning.bullet.intimate",
        "messages.photo.share.warning.bullet.address",
        "messages.photo.share.warning.bullet.workplace"
    ]

    private var panelBackground: Color { Color.white }
    private var primaryText: Color { .black }
    private var secondaryText: Color { Color.black.opacity(0.7) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 14) {
                Text("messages.photo.share.warning.subtitle".localized)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(primaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("messages.photo.share.warning.bullets.intro".localized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(secondaryText)
                        .multilineTextAlignment(.leading)

                    ForEach(bulletKeys, id: \.self) { key in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(secondaryText)
                            Text(key.localized)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(secondaryText)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onContinue) {
                    Text("messages.photo.share.warning.understand".localized)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Show schedule (taps 1, 20, 40 — then never again)

    private static let tapCountKeyPrefix = "photoShareWarningMediaTapCount_"
    private static let legacyDontShowKey = "dontShowPhotoShareWarning"
    private static let reminderTapCounts: Set<Int> = [1, 20, 40]

    private static var accountKey: String? {
        if let uid = FirebaseAuthService.shared.auth.currentUser?.uid, !uid.isEmpty {
            return uid
        }
        if let email = FirebaseAuthService.shared.auth.currentUser?.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !email.isEmpty {
            return email
        }
        return nil
    }

    private static func tapCountStorageKey(for accountKey: String) -> String {
        tapCountKeyPrefix + accountKey
    }

    /// Increments the shared media-button tap count and returns whether the safety popup should show.
    @discardableResult
    static func registerMediaTapAndShouldShow() -> Bool {
        // Drop the old forever-dismiss flag; schedule is now tap-based.
        UserDefaults.standard.removeObject(forKey: legacyDontShowKey)

        guard let accountKey else { return false }
        let defaults = UserDefaults.standard
        let key = tapCountStorageKey(for: accountKey)
        let nextCount = defaults.integer(forKey: key) + 1
        defaults.set(nextCount, forKey: key)
        return reminderTapCounts.contains(nextCount)
    }

    static func reset() {
        guard let accountKey else { return }
        UserDefaults.standard.removeObject(forKey: tapCountStorageKey(for: accountKey))
        UserDefaults.standard.removeObject(forKey: legacyDontShowKey)
    }
}
