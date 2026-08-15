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
    @AppStorage("selectedLanguage") private var selectedLanguageCode: String = "en"
    @State private var showingLanguageModal = false
    @State private var showingBlockedUsers = false
    @State private var showingPrivacySafety = false
    @State private var showingHelpSupport = false
    @State private var showingAbout = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var deleteConfirmationStep: DeleteAccountConfirmationStep = .sure
    @State private var deleteConfirmationText = ""
    @State private var isDeletingAccount = false
    @State private var deleteAccountErrorMessage: String?
    @State private var isExportingMessages = false
    @State private var showingExportShareSheet = false
    @State private var exportFileURL: URL?
    @State private var showingExportEmptyAlert = false
    @State private var showingExportErrorAlert = false
    
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
                }
                
                // Account & Data
                Section("settings.section.account.data".localized) {
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
                                    .lineLimit(2)
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
                        appState.signOut()
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
                                Text("settings.authentication.signout.subtitle".localized)
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
                        deleteConfirmationStep = .sure
                        deleteConfirmationText = ""
                        isDeletingAccount = false
                        deleteAccountErrorMessage = nil
                        showingDeleteAccountConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("settings.delete.account.button".localized)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .foregroundColor(.red)
                                Text("settings.delete.account.subtitle".localized)
                                    .font(.caption)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isDeletingAccount)
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
                
                // Development only — alone at the bottom
                #if DEBUG
                Section {
                    HStack {
                        Image(systemName: "trash.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text("settings.reset.user.data".localized)
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text("settings.reset.user.data.description".localized)
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
                        appState.resetAllAppState()
                    }
                }
                #endif
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
                if showingDeleteAccountConfirmation {
                    DeleteAccountConfirmationDialog(
                        step: $deleteConfirmationStep,
                        confirmationText: $deleteConfirmationText,
                        isDeleting: $isDeletingAccount,
                        errorMessage: $deleteAccountErrorMessage,
                        onCancel: {
                            showingDeleteAccountConfirmation = false
                            deleteConfirmationText = ""
                            deleteConfirmationStep = .sure
                            deleteAccountErrorMessage = nil
                        },
                        onConfirmDeletion: { password in
                            Task {
                                await MainActor.run { isDeletingAccount = true }
                                do {
                                    try await appState.deleteAccount(password: password)
                                    await MainActor.run {
                                        isDeletingAccount = false
                                        deleteConfirmationText = ""
                                        deleteAccountErrorMessage = nil
                                        deleteConfirmationStep = .success
                                    }
                                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                                    await MainActor.run {
                                        showingDeleteAccountConfirmation = false
                                        deleteConfirmationStep = .sure
                                        appState.signOut()
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
                        }
                    )
                }
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
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .font(.system(size: 48))
                            .foregroundColor(SpectRoomTheme.secondaryText)
                        Text("settings.blocked.users.empty".localized)
                            .font(.headline)
                            .foregroundColor(SpectRoomTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SpectRoomTheme.card)
                } else {
                    List(appState.blockedUsers) { blocked in
                        BlockedUserRow(
                            blocked: blocked,
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
}

private struct UnblockConfirmationOverlay: View {
    let firstName: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
            
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("settings.blocked.users.unblock.confirm.title".localized(with: firstName))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(SpectRoomTheme.text)
                    
                    Text("settings.blocked.users.unblock.confirm.message".localized(with: firstName))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(SpectRoomTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 18)
                
                Divider()
                
                HStack(spacing: 0) {
                    Button(action: onCancel) {
                        Text("common.cancel".localized)
                            .font(.body.weight(.medium))
                            .foregroundColor(SpectRoomTheme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                        .frame(height: 48)
                    
                    Button(action: onConfirm) {
                        Text("settings.blocked.users.unblock.action".localized)
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
            .padding(.horizontal, 48)
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

private enum DeleteAccountConfirmationStep {
    case sure
    case enterPassword
    case success
}

private struct DeleteAccountConfirmationDialog: View {
    @Binding var step: DeleteAccountConfirmationStep
    @Binding var confirmationText: String
    @Binding var isDeleting: Bool
    @Binding var errorMessage: String?
    let onCancel: () -> Void
    let onConfirmDeletion: (String) -> Void
    
    private var canConfirmPasswordStep: Bool {
        !confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isDeleting
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
                if step == .success {
                    Text("settings.delete.account.success.message".localized)
                        .font(.system(size: 22, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 28)
                        .padding(.horizontal, 22)
                } else {
                    Text("settings.delete.account.confirm.title".localized)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                        .padding(.horizontal, 20)
                    
                    Group {
                        if step == .sure {
                            Text("settings.delete.account.confirm.message".localized)
                                .font(.subheadline)
                                .foregroundColor(SpectRoomTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.top, 10)
                                .padding(.horizontal, 20)
                        } else {
                            VStack(spacing: 12) {
                                Text("settings.delete.account.type.message".localized)
                                    .font(.subheadline)
                                    .foregroundColor(SpectRoomTheme.secondaryText)
                                    .multilineTextAlignment(.center)
                                
                                SecureField("settings.delete.account.type.placeholder".localized, text: $confirmationText)
                                    .textContentType(.password)
                                    .padding(10)
                                    .background(SpectRoomTheme.card)
                                    .cornerRadius(8)
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
                                errorMessage = nil
                            }
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                    } else {
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
                                onConfirmDeletion(confirmationText)
                            }
                            .fontWeight(.semibold)
                            .foregroundColor(canConfirmPasswordStep ? .red : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .disabled(!canConfirmPasswordStep)
                        }
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
}

private extension View {
    func compactToggleStyle() -> some View {
        scaleEffect(0.8, anchor: .trailing)
            .frame(width: 46, height: 28, alignment: .trailing)
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = UIView()
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
        .environmentObject(AppStateManager.shared)
}
