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
    @State private var distanceLimitLevel = DiscoverDistanceLimit.currentOption.rawValue
    @State private var profilesInRadiusCount: Int?
    @State private var isCountingProfilesInRadius = false
    @State private var profilesInRadiusCountTask: Task<Void, Never>?
    
    private var selectedDistanceOption: DiscoverDistanceOption {
        DiscoverDistanceOption(rawValue: distanceLimitLevel) ?? .default
    }
    
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
                
                Section("settings.distance.limit".localized) {
                    distanceLimitSettingsRow
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
                        // Welcome shows again after logout unless "Don't show this again" was checked
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
                BlockedUsersModal()
                    .environmentObject(appState)
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
                distanceLimitLevel = DiscoverDistanceLimit.currentOption.rawValue
                scheduleProfilesInRadiusCount()
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
    
    private var distanceLimitSettingsRow: some View {
        let option = selectedDistanceOption
        let levelColor = option.accentColor
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(option.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(levelColor)
                
                if isCountingProfilesInRadius && profilesInRadiusCount == nil {
                    ProgressView()
                        .scaleEffect(0.75)
                } else if let profilesInRadiusCount {
                    Text("·")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(levelColor.opacity(0.7))
                    Text("\(profilesInRadiusCount)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(levelColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.28), lineWidth: 1.5)
            )
            .multilineTextAlignment(.center)
            
            EnergyLevelSlider(
                energyLevel: $distanceLimitLevel,
                levelColor: levelColor
            )
            .frame(height: 40)
            .onChange(of: distanceLimitLevel) { newLevel in
                let clamped = max(0, min(DiscoverDistanceOption.allCases.count - 1, newLevel))
                if clamped != newLevel {
                    distanceLimitLevel = clamped
                    return
                }
                let option = DiscoverDistanceOption(rawValue: clamped) ?? .default
                DiscoverDistanceLimit.currentOption = option
                // While the daily swipe limit is active, keep the frozen blurry deck.
                // Apply the new radius only after the limit lifts.
                if DiscoverDailyLimit.currentCount() >= DiscoverDailyLimit.maxSwipesPerDay {
                    DiscoverDistanceLimit.hasPendingDeckRefresh = true
                } else {
                    DiscoverDistanceLimit.hasPendingDeckRefresh = false
                    appState.clearDiscoverProfilesCache()
                }
                scheduleProfilesInRadiusCount()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
    
    private func scheduleProfilesInRadiusCount() {
        profilesInRadiusCountTask?.cancel()
        let option = selectedDistanceOption
        let blockedUserIds = Set(appState.blockedUsers.map(\.id))
        guard let currentUser = appState.currentUser else {
            profilesInRadiusCount = nil
            isCountingProfilesInRadius = false
            return
        }
        
        isCountingProfilesInRadius = true
        profilesInRadiusCount = nil
        
        profilesInRadiusCountTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            
            let count = await DiscoverRadiusCounter.countEligibleProfiles(
                currentUser: currentUser,
                option: option,
                blockedUserIds: blockedUserIds
            )
            
            await MainActor.run {
                guard !Task.isCancelled else { return }
                profilesInRadiusCount = count
                isCountingProfilesInRadius = false
            }
        }
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
    @EnvironmentObject private var appState: AppStateManager
    @Environment(\.dismiss) private var dismiss
    @State private var pendingUnblockUser: BlockedUser?
    @State private var showingUnblockConfirmation = false
    
    var body: some View {
        NavigationView {
            Group {
                if appState.blockedUsers.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("settings.blocked.users.empty".localized)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else {
                    List(appState.blockedUsers) { blocked in
                        BlockedUserRow(
                            blocked: blocked,
                            isBlocked: true,
                            onRequestUnblock: {
                                pendingUnblockUser = blocked
                                showingUnblockConfirmation = true
                            }
                        )
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("settings.blocked.users.modal.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) {
                        dismiss()
                    }
                }
            }
            .alert("profile.block.confirm.title".localized, isPresented: $showingUnblockConfirmation) {
                Button("common.cancel".localized, role: .cancel) {
                    pendingUnblockUser = nil
                }
                Button("settings.blocked.users.unblock.action".localized, role: .destructive) {
                    if let user = pendingUnblockUser {
                        appState.unblockUser(userId: user.id)
                    }
                    pendingUnblockUser = nil
                }
            } message: {
                if let user = pendingUnblockUser {
                    Text(String(format: "settings.blocked.users.unblock.confirm.message".localized, firstName(from: user.name)))
                }
            }
        }
    }
    
    private func firstName(from fullName: String) -> String {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return components.first.map(String.init) ?? fullName
    }
}

private struct BlockedUserRow: View {
    let blocked: BlockedUser
    let isBlocked: Bool
    let onRequestUnblock: () -> Void
    
    @State private var photoURL: String?
    
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { isBlocked },
            set: { newValue in
                if !newValue {
                    onRequestUnblock()
                }
            }
        )
    }
    
    var body: some View {
        HStack(spacing: 12) {
            profilePhoto
            
            VStack(alignment: .leading, spacing: 4) {
                Text(blocked.name)
                    .font(.headline)
                Text(dateText(for: blocked))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: toggleBinding)
                .labelsHidden()
                .compactToggleStyle()
        }
        .padding(.vertical, 4)
        .task(id: blocked.id) {
            await loadPhoto()
        }
    }
    
    private var profilePhoto: some View {
        Group {
            if let photoURL, let url = URL(string: photoURL) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsPlaceholder
                }
            } else {
                initialsPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }
    
    private var initialsPlaceholder: some View {
        Circle()
            .fill(Color.blue.opacity(0.2))
            .overlay(
                Text(String(blocked.name.prefix(1)).uppercased())
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            )
    }
    
    private func dateText(for blocked: BlockedUser) -> String {
        if let blockedAt = blocked.blockedAt {
            return String(
                format: "settings.blocked.users.since".localized,
                blockedAt.formatted(date: .abbreviated, time: .shortened)
            )
        }
        return "settings.blocked.users.no.date".localized
    }
    
    private func loadPhoto() async {
        do {
            photoURL = try await FirebaseAuthService.shared.fetchUserProfilePhotoURL(for: blocked.id)
        } catch {
            photoURL = nil
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
