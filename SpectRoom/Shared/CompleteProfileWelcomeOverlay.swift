//
//  CompleteProfileWelcomeOverlay.swift
//  SpectRoom
//

import SwiftUI

struct CompleteProfileWelcomeOverlay: View {
    let onContinue: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(alignment: .center, spacing: 14) {
                Text("profile.complete.welcome.title".localized)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                
                Text("profile.complete.welcome.message".localized)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Button(action: onContinue) {
                    Text("profile.complete.welcome.continue".localized)
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(Color.black.opacity(0.85))
            .cornerRadius(16)
            .padding(.horizontal, 28)
        }
    }
    
    private static let legacyKey = "dontShowCompleteProfileWelcome"
    
    private static func storageKey(for userId: String?) -> String {
        guard let userId, !userId.isEmpty else { return legacyKey }
        return "dontShowCompleteProfileWelcome.\(userId)"
    }
    
    static func shouldShowWelcome(for userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else {
            return !UserDefaults.standard.bool(forKey: legacyKey)
        }
        return !UserDefaults.standard.bool(forKey: storageKey(for: userId))
    }
    
    static func markWelcomeSeen(for userId: String?) {
        UserDefaults.standard.set(true, forKey: storageKey(for: userId))
    }
    
    /// Each new account should see the welcome popup once when opening profile setup.
    static func prepareForNewSignup(userId: String) {
        UserDefaults.standard.removeObject(forKey: storageKey(for: userId))
    }
}
