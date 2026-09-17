//
//  AuthFlowPreferenceBar.swift
//  SpectRoom
//

import SwiftUI

/// Dark mode and language controls shown during onboarding and authentication.
struct AuthFlowPreferenceBar: View {
    @AppStorage("selectedLanguage") private var selectedLanguageCode = "sv"
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var showingLanguageModal = false

    var body: some View {
        HStack {
            Button {
                isDarkMode.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                        .font(.headline)
                        .foregroundColor(isDarkMode ? .yellow : .orange)
                    Text(isDarkMode ? "settings.light.mode".localized : "settings.dark.mode".localized)
                        .font(.subheadline)
                        .foregroundColor(SpectRoomTheme.text)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
            }

            Spacer()

            Button {
                showingLanguageModal = true
            } label: {
                HStack(spacing: 6) {
                    Text(currentLanguageFlag)
                        .font(.headline)
                    Text(currentLanguageName)
                        .font(.subheadline)
                        .foregroundColor(SpectRoomTheme.text)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .sheet(isPresented: $showingLanguageModal) {
            LanguageSelectionModal()
        }
    }

    private var currentLanguageFlag: String {
        Language.allLanguages.first(where: { $0.code == selectedLanguageCode })?.flag ?? "🇸🇪"
    }

    private var currentLanguageName: String {
        Language.allLanguages.first(where: { $0.code == selectedLanguageCode })?.name ?? "Swedish"
    }
}

extension View {
    /// Pins dark mode and language controls at the top of auth-related screens.
    func authFlowPreferenceControls() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            AuthFlowPreferenceBar()
        }
    }
}
