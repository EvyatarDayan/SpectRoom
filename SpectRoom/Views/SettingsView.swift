//
//  SettingsView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import UserNotifications
import Foundation

struct SettingsView: View {
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @State private var showingPermissionAlert = false
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("selectedLanguage") private var selectedLanguageCode: String = "en"
    @State private var showingLanguageModal = false
    @State private var showingBlockedUsers = false
    @State private var showingPrivacySafety = false
    @State private var showingHelpSupport = false
    @State private var showingAbout = false
    
    var body: some View {
        NavigationView {
            List {
//                // Account Section
//                Section("Account") {
//                    // Account section is now empty - could be removed or used for other account-related settings
//                }
//                
                // App Settings Section
                Section("settings.app.settings".localized) {
                    HStack {
                        Image(systemName: "bell.circle.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.notifications".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.notifications.description".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Toggle("", isOn: $notificationsEnabled)
                            .compactToggleStyle()
                            .onChange(of: notificationsEnabled) { enabled in
                                if enabled {
                                    Task {
                                        let granted = await NotificationService.shared.requestNotificationPermission()
                                        if !granted {
                                            await MainActor.run {
                                                notificationsEnabled = false
                                                showingPermissionAlert = true
                                            }
                                        }
                                    }
                                } else {
                                    // User disabled notifications
                                    UserDefaults.standard.set(false, forKey: "notificationsEnabled")
                                }
                            }
                    }
                    
                    HStack {
                        Image(systemName: "moon.circle.fill")
                            .foregroundColor(.purple)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.dark.mode".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.dark.mode.description".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Toggle("", isOn: $isDarkMode)
                            .compactToggleStyle()
                    }
                    
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.language".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.language.description".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Text(currentLanguageFlag)
                                .font(.title3)
                            Text(currentLanguageName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingLanguageModal = true
                    }
                }
                
                // Support Section
                Section("settings.support".localized) {
                    HStack {
                        Image(systemName: "lock.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.privacy.safety".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.privacy.safety.description".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingPrivacySafety = true
                    }
                    
                    HStack {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundColor(.cyan)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.help.support".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.help.support.description".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Open Help & Support modal
                        showingHelpSupport = true
                    }
                    
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.about".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.about.description".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingAbout = true
                    }
                }
                
                // Development Section (Debug builds only)
                #if DEBUG
                Section("settings.development".localized) {
//                    HStack {
//                        Image(systemName: "arrow.clockwise.circle.fill")
//                            .foregroundColor(.red)
//                            .font(.title2)
//                        VStack(alignment: .leading) {
//                            Text("Reset Onboarding")
//                                .font(.headline)
//                            Text("Reset onboarding flow for testing")
//                                .font(.caption)
//                                .foregroundColor(.secondary)
//                                .lineLimit(1)
//                                .minimumScaleFactor(0.8)
//                        }
//                        Spacer()
//                        Image(systemName: "chevron.right")
//                            .foregroundColor(.secondary)
//                            .font(.caption)
//                    }
//                    .contentShape(Rectangle())
//                    .onTapGesture {
//                        appState.resetOnboarding()
//                    }
                    
                    HStack {
                        Image(systemName: "trash.circle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.reset.user.data".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.reset.user.data.description".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.resetAllAppState()
                    }
                }
                #endif
                
                Section("settings.blocked.users.section.title".localized.uppercased()) {
                    Button(action: {
                        showingBlockedUsers = true
                    }) {
                        HStack {
                            Image(systemName: "hand.raised.slash.fill")
                                .foregroundColor(.red)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings.blocked.users.button.title".localized)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Text("settings.blocked.users.button.subtitle".localized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                            Text("\(appState.blockedUsers.count)")
                                .font(.footnote.bold())
                                .foregroundColor(.white)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color.orange)
                                .clipShape(Capsule())
                        }
                    }
                }
                
                // Sign Out Section
                Section("settings.authentication.section.title".localized.uppercased()) {
                    Button(action: {
                        // Use AppStateManager.signOut() to ensure proper state management
                        // This preserves hasCompletedOnboarding so users go to sign-in view, not onboarding
                        appState.signOut()
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right.fill")
                                .foregroundColor(.red)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings.sign.out".localized)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundColor(.red)
                                Text("settings.authentication.signout.subtitle".localized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
            .padding(.bottom, 60)
            .scrollContentBackground(.hidden)
            .background(
                Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            )
            .sheet(isPresented: $showingBlockedUsers) {
                BlockedUsersModal(blockedUsers: appState.blockedUsers)
            }
            .sheet(isPresented: $showingHelpSupport) {
                HelpSupportView()
            }
            .navigationTitle("settings.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("settings.title".localized)
                        .font(.system(size: 28, weight: .bold))
                }
            }
            .onAppear {
                checkNotificationPermission()
            }
            .alert("settings.notification.permission".localized, isPresented: $showingPermissionAlert) {
                Button("settings.settings.button".localized) {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                Button("settings.cancel".localized, role: .cancel) {
                    notificationsEnabled = false
                }
            } message: {
                Text("settings.notification.permission.message".localized)
            }
            .sheet(isPresented: $showingLanguageModal) {
                LanguageSelectionModal()
            }
            .sheet(isPresented: $showingPrivacySafety) {
                PrivacySafetyView()
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
        }
    }
    
    private var currentLanguageFlag: String {
        Language.allLanguages.first(where: { $0.code == selectedLanguageCode })?.flag ?? "🇺🇸"
    }
    
    private var currentLanguageName: String {
        Language.allLanguages.first(where: { $0.code == selectedLanguageCode })?.name ?? "English"
    }
    
    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    notificationsEnabled = true
                case .denied, .notDetermined:
                    notificationsEnabled = false
                case .ephemeral:
                    notificationsEnabled = false
                @unknown default:
                    notificationsEnabled = false
                }
            }
        }
    }
    
}



private struct BlockedUsersModal: View {
    let blockedUsers: [BlockedUser]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if blockedUsers.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "hand.raised.slash.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("settings.blocked.users.empty".localized)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else {
                    List(blockedUsers) { blocked in
                        HStack {
                            Image(systemName: "hand.raised.slash.fill")
                                .foregroundColor(.orange)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(blocked.name)
                                    .font(.headline)
                                Text(dateText(for: blocked))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("settings.blocked.users.modal.title".localized)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func dateText(for blocked: BlockedUser) -> String {
        if let blockedAt = blocked.blockedAt {
            return String(format: "settings.blocked.users.since".localized, blockedAt.formatted(date: .abbreviated, time: .shortened))
        } else {
            return "settings.blocked.users.no.date".localized
        }
    }
}

private extension View {
    func compactToggleStyle() -> some View {
        scaleEffect(0.8, anchor: .trailing)
            .frame(width: 46, height: 28, alignment: .trailing)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppStateManager.shared)
}
