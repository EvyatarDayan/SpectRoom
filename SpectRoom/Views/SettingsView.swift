//
//  SettingsView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import UserNotifications
import UIKit
import Foundation

struct SettingsView: View {
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @State private var showingPermissionAlert = false
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("selectedLanguage") private var selectedLanguageCode: String = "sv"
    @State private var showingLanguageModal = false
    @State private var showingBlockedUsers = false
    @State private var showingReportedProfiles = false
    @State private var showingPrivacySafety = false
    @State private var reportedProfilesCount = 0
    @State private var showingHelpSupport = false
    @State private var showingAbout = false
    @State private var showingAccountBilling = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var deleteConfirmationStep: DeleteAccountConfirmationStep = .sure
    @State private var deleteConfirmationText = ""
    @State private var deleteMfaCode = ""
    @State private var deleteMfaMaskedPhone = ""
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?
    @State private var isExportingMessages = false
    @State private var showingExportShareSheet = false
    @State private var exportFileURL: URL?
    @State private var showingExportEmptyAlert = false
    @State private var showingExportErrorAlert = false
    @State private var showingSignOutConfirmation = false
    
    var body: some View {
        NavigationView {
            List {
//                // Account Section
//                Section("Account") {
//                    // Account section is now empty - could be removed or used for other account-related settings
//                }
//                
                // Preferences
                Section("settings.section.preferences".localized) {
                    HStack {
                        Image(systemName: "bell.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.notifications".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.notifications.description".localized)
                                .font(.caption)
                                .foregroundColor(SpectRoomTheme.secondaryText)
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
                                        if granted {
                                            await FirebaseAuthService.shared.refreshFCMToken()
                                        } else {
                                            await MainActor.run {
                                                notificationsEnabled = false
                                                showingPermissionAlert = true
                                            }
                                        }
                                    }
                                } else {
                                    UserDefaults.standard.set(false, forKey: "notificationsEnabled")
                                }
                            }
                    }
                    
                    HStack {
                        Image(systemName: "moon.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.dark.mode".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.dark.mode.description".localized)
                                .font(.caption)
                                .foregroundColor(SpectRoomTheme.secondaryText)
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
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Text(currentLanguageFlag)
                                .font(.title3)
                            Text(currentLanguageName)
                                .font(.subheadline)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                            Image(systemName: "chevron.right")
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .font(.caption)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingLanguageModal = true
                    }
                }
                
                // Privacy & Safety
                Section("settings.section.privacy.safety".localized) {
                    HStack {
                        Image(systemName: "lock.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.privacy.settings".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.privacy.safety.description".localized)
                                .font(.caption)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(SpectRoomTheme.secondaryText)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingPrivacySafety = true
                    }

                    Button(action: exportMessages) {
                        HStack {
                            Image(systemName: "square.and.arrow.up.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings.export.messages".localized)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundColor(SpectRoomTheme.text)
                                Text("settings.export.messages.description".localized)
                                    .font(.caption)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                            if isExportingMessages {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .font(.caption)
                            }
                        }
                    }
                    .disabled(isExportingMessages)
                    
                    Button(action: {
                        showingBlockedUsers = true
                    }) {
                        HStack {
                            Image(systemName: "hand.raised.slash.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    String(
                                        format: "settings.blocked.users.button.title.count".localized,
                                        appState.blockedUsers.count
                                    )
                                )
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundColor(SpectRoomTheme.text)
                                Text("settings.blocked.users.button.subtitle".localized)
                                    .font(.caption)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .font(.caption)
                        }
                    }

                    Button(action: {
                        showingReportedProfiles = true
                    }) {
                        HStack {
                            Image(systemName: "exclamationmark.bubble.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    String(
                                        format: "settings.reported.profiles.button.title.count".localized,
                                        reportedProfilesCount
                                    )
                                )
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundColor(SpectRoomTheme.text)
                                Text("settings.reported.profiles.button.subtitle".localized)
                                    .font(.caption)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .font(.caption)
                        }
                    }
                }
                
                // Account
                Section("settings.section.account".localized) {
                    Button(action: {
                        showingAccountBilling = true
                    }) {
                        HStack {
                            Image(systemName: "creditcard.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings.account.billing".localized)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundColor(SpectRoomTheme.text)
                                Text("settings.account.billing.description".localized)
                                    .font(.caption)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                            Text((appState.currentUser?.planTier ?? DiscoverDailyLimit.currentPlanTier).titleStars)
                                .font(.body)
                            Image(systemName: "chevron.right")
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .font(.caption)
                        }
                    }

                    Button(action: {
                        showingSignOutConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings.sign.out".localized)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundColor(SpectRoomTheme.text)
                                Text(FirebaseAuthService.shared.auth.currentUser?.email ?? "")
                                    .font(.caption)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                        }
                    }
                }

                // Support & About
                Section("settings.section.support.about".localized) {
                    HStack {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.help.support".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.help.support.description".localized)
                                .font(.caption)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(SpectRoomTheme.secondaryText)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingHelpSupport = true
                    }
                    
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.about.spectroom".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.about.description".localized)
                                .font(.caption)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(SpectRoomTheme.secondaryText)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingAbout = true
                    }
                }

                // Danger zone
                Section("settings.section.danger.zone".localized) {
                    #if DEBUG
                    HStack {
                        Image(systemName: "trash.circle.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("settings.reset.user.data".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                            Text("settings.reset.user.data.description".localized)
                                .font(.caption)
                                .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.resetAllAppState()
                    }
                    #endif

                    Button(action: {
                        deleteConfirmationStep = .sure
                        deleteConfirmationText = ""
                        deleteMfaCode = ""
                        deleteMfaMaskedPhone = ""
                        isDeletingAccount = false
                        deleteAccountErrorMessage = nil
                        showingDeleteAccountConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash.circle.fill")
                                .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings.delete.account.button".localized)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                                Text("settings.delete.account.subtitle".localized)
                                    .font(.caption)
                                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isDeletingAccount)
                }
            }
            .padding(.bottom, 60)
            .scrollContentBackground(.hidden)
            .background(
                SpectRoomBackground()
            )
            .sheet(isPresented: $showingBlockedUsers) {
                BlockedUsersModal()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingReportedProfiles, onDismiss: {
                Task { await refreshReportedProfilesCount() }
            }) {
                ReportedProfilesModal()
            }
            .sheet(isPresented: $showingHelpSupport) {
                HelpSupportView()
            }
            .navigationTitle("settings.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .spectRoomNavigationChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("settings.title".localized)
                        .font(.system(size: 28, weight: .bold))
                }
            }
            .onAppear {
                checkNotificationPermission()
                Task { await refreshReportedProfilesCount() }
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
            .sheet(isPresented: $showingAccountBilling) {
                AccountBillingView()
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .sheet(isPresented: $showingExportShareSheet, onDismiss: {
                exportFileURL = nil
            }) {
                if let exportFileURL {
                    ActivityShareSheet(items: [exportFileURL])
                }
            }
            .alert("settings.export.messages".localized, isPresented: $showingExportEmptyAlert) {
                Button("common.ok".localized, role: .cancel) { }
            } message: {
                Text("settings.export.messages.empty".localized)
            }
            .alert("settings.export.messages".localized, isPresented: $showingExportErrorAlert) {
                Button("common.ok".localized, role: .cancel) { }
            } message: {
                Text("settings.export.messages.error".localized)
            }
            .overlay {
                if showingSignOutConfirmation {
                    SignOutConfirmationOverlay(
                        onCancel: { showingSignOutConfirmation = false },
                        onConfirm: {
                            showingSignOutConfirmation = false
                            appState.signOut()
                        }
                    )
                } else if showingDeleteAccountConfirmation {
                    DeleteAccountConfirmationDialog(
                        step: $deleteConfirmationStep,
                        confirmationText: $deleteConfirmationText,
                        mfaCode: $deleteMfaCode,
                        mfaMaskedPhone: deleteMfaMaskedPhone,
                        isDeleting: $isDeletingAccount,
                        errorMessage: $deleteAccountErrorMessage,
                        onCancel: {
                            appState.cancelDeleteAccountMfa()
                            showingDeleteAccountConfirmation = false
                            deleteConfirmationText = ""
                            deleteMfaCode = ""
                            deleteMfaMaskedPhone = ""
                            deleteConfirmationStep = .sure
                            deleteAccountErrorMessage = nil
                        },
                        onConfirmDeletion: { password in
                            Task {
                                await MainActor.run { isDeletingAccount = true }
                                do {
                                    let outcome = try await appState.deleteAccount(password: password)
                                    await MainActor.run {
                                        isDeletingAccount = false
                                        deleteAccountErrorMessage = nil
                                        switch outcome {
                                        case .completed:
                                            deleteConfirmationText = ""
                                            deleteConfirmationStep = .success
                                        case .mfaRequired(let maskedPhone):
                                            deleteMfaMaskedPhone = maskedPhone
                                            deleteMfaCode = ""
                                            deleteConfirmationStep = .enterMfaCode
                                        }
                                    }
                                } catch let error as SpectRoomAuthError {
                                    await MainActor.run {
                                        isDeletingAccount = false
                                        deleteAccountErrorMessage = error.errorDescription
                                            ?? "settings.delete.account.error".localized
                                    }
                                } catch {
                                    await MainActor.run {
                                        isDeletingAccount = false
                                        deleteAccountErrorMessage = "settings.delete.account.error".localized
                                    }
                                }
                            }
                        },
                        onConfirmMfa: { code in
                            Task {
                                await MainActor.run { isDeletingAccount = true }
                                do {
                                    try await appState.completeDeleteAccountAfterMfa(code: code)
                                    await MainActor.run {
                                        isDeletingAccount = false
                                        deleteConfirmationText = ""
                                        deleteMfaCode = ""
                                        deleteAccountErrorMessage = nil
                                        deleteConfirmationStep = .success
                                    }
                                } catch let error as SpectRoomAuthError {
                                    await MainActor.run {
                                        isDeletingAccount = false
                                        deleteAccountErrorMessage = error.errorDescription
                                            ?? "settings.delete.account.error".localized
                                    }
                                } catch {
                                    await MainActor.run {
                                        isDeletingAccount = false
                                        deleteAccountErrorMessage = "settings.delete.account.error".localized
                                    }
                                }
                            }
                        },
                        onResendMfa: {
                            Task {
                                do {
                                    try await appState.resendDeleteAccountMfaCode()
                                    await MainActor.run {
                                        deleteAccountErrorMessage = nil
                                    }
                                } catch let error as SpectRoomAuthError {
                                    await MainActor.run {
                                        deleteAccountErrorMessage = error.errorDescription
                                            ?? "auth.mfa.error.send".localized
                                    }
                                } catch {
                                    await MainActor.run {
                                        deleteAccountErrorMessage = "auth.mfa.error.send".localized
                                    }
                                }
                            }
                        },
                        onSuccessAcknowledged: {
                            appState.cancelDeleteAccountMfa()
                            showingDeleteAccountConfirmation = false
                            deleteConfirmationStep = .sure
                            deleteConfirmationText = ""
                            deleteMfaCode = ""
                            deleteMfaMaskedPhone = ""
                            deleteAccountErrorMessage = nil
                            appState.signOut()
                        }
                    )
                }
            }
        }
    }
    
    private var currentLanguageFlag: String {
        Language.allLanguages.first(where: { $0.code == selectedLanguageCode })?.flag ?? "🇸🇪"
    }
    
    private var currentLanguageName: String {
        Language.allLanguages.first(where: { $0.code == selectedLanguageCode })?.name ?? "Swedish"
    }
    
    private func refreshReportedProfilesCount() async {
        do {
            let reports = try await FirebaseAuthService.shared.fetchMyReports()
            await MainActor.run {
                reportedProfilesCount = reports.count
            }
        } catch {
            print("⚠️ Failed to load reported profiles count: \(error.localizedDescription)")
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
    
    private func exportMessages() {
        guard !isExportingMessages else { return }
        isExportingMessages = true
        Task {
            do {
                let fileURL = try await appState.exportAllMessagesToFile()
                await MainActor.run {
                    isExportingMessages = false
                    if let fileURL {
                        exportFileURL = fileURL
                        showingExportShareSheet = true
                    } else {
                        showingExportEmptyAlert = true
                    }
                }
            } catch {
                print("❌ Error exporting messages: \(error)")
                await MainActor.run {
                    isExportingMessages = false
                    showingExportErrorAlert = true
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
                    emptyBlockedUsersView
                } else {
                    List(appState.blockedUsers) { blocked in
                        BlockedUserRow(
                            blocked: blocked,
                            onRequestUnblock: {
                                pendingUnblockUser = blocked
                                showingUnblockConfirmation = true
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                    .background(SpectRoomBackground())
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
            .overlay {
                if showingUnblockConfirmation, let user = pendingUnblockUser {
                    UnblockConfirmationOverlay(
                        firstName: firstName(from: user.name),
                        onCancel: {
                            showingUnblockConfirmation = false
                            pendingUnblockUser = nil
                        },
                        onConfirm: {
                            showingUnblockConfirmation = false
                            appState.unblockUser(userId: user.id)
                            pendingUnblockUser = nil
                        }
                    )
                }
            }
        }
    }
    
    private func firstName(from fullName: String) -> String {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return components.first.map(String.init) ?? fullName
    }

    private var emptyBlockedUsersView: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Text("🚫")
                    .font(.system(size: 48))
                    .frame(width: 96, height: 96)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(0.12))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.red.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.red.opacity(0.14), radius: 12, y: 4)

                Text("settings.blocked.users.empty".localized)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.center)

                Text("settings.blocked.users.empty.description".localized)
                    .font(.subheadline)
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SpectRoomBackground())
    }
}

private struct ReportedProfilesModal: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reports: [UserReport] = []
    @State private var isLoading = true
    @State private var selectedReport: UserReport?

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(SpectRoomBackground())
                } else if reports.isEmpty {
                    emptyReportedProfilesView
                } else {
                    List(reports) { report in
                        Button {
                            selectedReport = report
                        } label: {
                            ReportedProfileRow(report: report)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                    .background(SpectRoomBackground())
                }
            }
            .navigationTitle("settings.reported.profiles.modal.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) {
                        dismiss()
                    }
                }
            }
            .overlay {
                if let selectedReport {
                    ReportDetailsOverlay(
                        report: selectedReport,
                        onDismiss: { self.selectedReport = nil }
                    )
                }
            }
            .task {
                await loadReports()
            }
        }
    }

    private func loadReports() async {
        isLoading = true
        do {
            reports = try await FirebaseAuthService.shared.fetchMyReports()
        } catch {
            print("⚠️ Failed to load reported profiles: \(error.localizedDescription)")
            reports = []
        }
        isLoading = false
    }

    private var emptyReportedProfilesView: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Text("🚩")
                    .font(.system(size: 48))
                    .frame(width: 96, height: 96)
                    .background(
                        Circle()
                            .fill(Color.orange.opacity(0.12))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: Color.orange.opacity(0.14), radius: 12, y: 4)

                Text("settings.reported.profiles.empty".localized)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.center)

                Text("settings.reported.profiles.empty.description".localized)
                    .font(.subheadline)
                    .foregroundColor(SpectRoomTheme.text)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SpectRoomBackground())
    }
}

private struct ReportedProfileRow: View {
    let report: UserReport

    var body: some View {
        HStack(spacing: 12) {
            profilePhoto

            VStack(alignment: .leading, spacing: 4) {
                Text(report.reportedName)
                    .font(.headline)
                    .foregroundColor(SpectRoomTheme.text)
                Text(dateText)
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(SpectRoomTheme.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
        .contentShape(Rectangle())
    }

    private var dateText: String {
        if let createdAt = report.createdAt {
            return String(
                format: "settings.reported.profiles.since".localized,
                createdAt.formatted(date: .abbreviated, time: .shortened)
            )
        }
        return "settings.reported.profiles.no.date".localized
    }

    private var profilePhoto: some View {
        Group {
            if let photoURL = report.primaryPhotoURL, let url = URL(string: photoURL) {
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
                Text(String(report.reportedName.prefix(1)).uppercased())
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            )
    }
}

private struct ReportDetailsOverlay: View {
    let report: UserReport
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text(
                        String(
                            format: "settings.reported.profiles.detail.headline".localized,
                            report.reportedName
                        )
                    )
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(SpectRoomTheme.text)
                    .padding(.bottom, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        if let dateLine = formattedDateLine {
                            Text(dateLine)
                        }

                        Text(
                            String(
                                format: "settings.reported.profiles.detail.category.line".localized,
                                displayCategory
                            )
                        )

                        if let details = report.details?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !details.isEmpty {
                            Text(
                                String(
                                    format: "settings.reported.profiles.detail.details.line".localized,
                                    details
                                )
                            )
                        }
                    }
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(SpectRoomTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 18)

                Divider()

                Button(action: onDismiss) {
                    Text("common.close".localized)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
            .background(SpectRoomTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 36)
        }
    }

    private var displayCategory: String {
        let category = report.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let somethingElseStorage = ProfileReportReason.somethingElse.storageCategory
        let somethingElseLabel = ProfileReportReason.somethingElse.label
        if category.caseInsensitiveCompare(somethingElseStorage) == .orderedSame
            || category.caseInsensitiveCompare(somethingElseLabel) == .orderedSame {
            return "settings.reported.profiles.detail.see.details".localized
        }
        return category
    }

    private var formattedDateLine: String? {
        guard let createdAt = report.createdAt else { return nil }
        let formattedDate = createdAt.formatted(
            Date.FormatStyle()
                .day()
                .month(.abbreviated)
                .year()
                .hour()
                .minute()
        )
        return String(
            format: "settings.reported.profiles.detail.date.line".localized,
            formattedDate
        )
    }
}

private struct SignOutConfirmationOverlay: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("settings.sign.out.confirm.title".localized)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(SpectRoomTheme.text)
                        .padding(.bottom, 4)

                    Text("settings.sign.out.confirm.message".localized)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
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

                    Button(action: onConfirm) {
                        Text("settings.sign.out".localized)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.green)
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
    }
}

private struct BlockedUserRow: View {
    let blocked: BlockedUser
    let onRequestUnblock: () -> Void
    
    @State private var photoURL: String?
    
    var body: some View {
        HStack(spacing: 12) {
            profilePhoto
            
            VStack(alignment: .leading, spacing: 4) {
                Text(blocked.name)
                    .font(.headline)
                    .foregroundColor(SpectRoomTheme.text)
                Text(dateText(for: blocked))
                    .font(.caption)
                    .foregroundColor(SpectRoomTheme.secondaryText)
            }
            
            Spacer()
            
            Button("settings.blocked.users.unblock.action".localized, action: onRequestUnblock)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.green)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(SpectRoomTheme.card)
        .cornerRadius(12)
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

private enum DeleteAccountConfirmationStep {
    case sure
    case enterPassword
    case enterMfaCode
    case success
}

private struct DeleteAccountConfirmationDialog: View {
    @Binding var step: DeleteAccountConfirmationStep
    @Binding var confirmationText: String
    @Binding var mfaCode: String
    let mfaMaskedPhone: String
    @Binding var isDeleting: Bool
    @Binding var errorMessage: String?
    let onCancel: () -> Void
    let onConfirmDeletion: (String) -> Void
    let onConfirmMfa: (String) -> Void
    let onResendMfa: () -> Void
    let onSuccessAcknowledged: () -> Void

    @State private var isPasswordVisible = false

    private var canConfirmPasswordStep: Bool {
        !confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isDeleting
    }

    private var canConfirmMfaStep: Bool {
        mfaCode.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6 && !isDeleting
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    if step != .success && !isDeleting {
                        onCancel()
                    }
                }

            VStack(spacing: 0) {
                Text(
                    step == .success
                        ? "settings.delete.account.success.message".localized
                        : "settings.delete.account.confirm.title".localized
                )
                .font(step == .success ? .system(size: 20, weight: .bold) : .headline)
                .multilineTextAlignment(.center)
                .padding(.top, 20)
                .padding(.bottom, step == .success ? 8 : 0)
                .padding(.horizontal, 20)

                if step != .success {
                    Group {
                        if step == .sure {
                            Text("settings.delete.account.confirm.message".localized)
                                .font(.subheadline)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.top, 10)
                                .padding(.horizontal, 20)
                        } else if step == .enterPassword {
                            passwordStepContent
                        } else {
                            mfaStepContent
                        }
                    }
                }

                Divider()
                    .padding(.top, 18)

                if step == .sure {
                    HStack(spacing: 0) {
                        Button("settings.cancel".localized, action: onCancel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)

                        Divider()
                            .frame(height: 44)

                        Button("settings.delete.account.confirm.yes".localized) {
                            step = .enterPassword
                            confirmationText = ""
                            isPasswordVisible = false
                            errorMessage = nil
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                } else if step == .enterPassword {
                    HStack(spacing: 0) {
                        Button("settings.cancel".localized) {
                            guard !isDeleting else { return }
                            onCancel()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .disabled(isDeleting)

                        Divider()
                            .frame(height: 44)

                        Button("settings.delete.account.confirm.ok".localized) {
                            onConfirmDeletion(confirmationText.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(canConfirmPasswordStep ? .red : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .disabled(!canConfirmPasswordStep)
                    }
                } else if step == .enterMfaCode {
                    HStack(spacing: 0) {
                        Button("settings.cancel".localized) {
                            guard !isDeleting else { return }
                            onCancel()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .disabled(isDeleting)

                        Divider()
                            .frame(height: 44)

                        Button("settings.delete.account.confirm.ok".localized) {
                            onConfirmMfa(mfaCode.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(canConfirmMfaStep ? .red : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .disabled(!canConfirmMfaStep)
                    }
                } else {
                    HStack(spacing: 0) {
                        Button("settings.cancel".localized) {}
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .disabled(true)
                            .foregroundColor(.secondary)

                        Divider()
                            .frame(height: 44)

                        Button("settings.delete.account.confirm.ok".localized, action: onSuccessAcknowledged)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
            }
            .frame(maxWidth: 300)
            .background(SpectRoomTheme.card)
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .padding(.horizontal, 40)
        }
    }

    private var passwordStepContent: some View {
        VStack(spacing: 12) {
            Text("settings.delete.account.type.message".localized)
                .font(.subheadline)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Group {
                    if isPasswordVisible {
                        TextField("settings.delete.account.type.placeholder".localized, text: $confirmationText)
                    } else {
                        SecureField("settings.delete.account.type.placeholder".localized, text: $confirmationText)
                    }
                }
                .textContentType(.password)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .disabled(isDeleting)

                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
            }
            .padding(10)
            .background(SpectRoomTheme.background)
            .cornerRadius(8)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            if isDeleting {
                ProgressView()
                    .padding(.top, 4)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 20)
    }

    private var mfaStepContent: some View {
        VStack(spacing: 12) {
            Text(String(format: "settings.delete.account.mfa.message".localized, mfaMaskedPhone))
                .font(.subheadline)
                .foregroundColor(SpectRoomTheme.secondaryText)
                .multilineTextAlignment(.center)

            TextField("settings.delete.account.mfa.placeholder".localized, text: $mfaCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .padding(10)
                .background(SpectRoomTheme.background)
                .cornerRadius(8)
                .disabled(isDeleting)

            Button("settings.delete.account.mfa.resend".localized, action: onResendMfa)
                .font(.caption.weight(.semibold))
                .foregroundColor(.blue)
                .disabled(isDeleting)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            if isDeleting {
                ProgressView()
                    .padding(.top, 4)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 20)
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
