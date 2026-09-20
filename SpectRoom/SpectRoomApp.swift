//
//  SpectRoomApp.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseMessaging
import Combine
import UserNotifications


/// Presents Help & Support from a moderation popup with a stable, unique sheet identity.
private struct ModerationSupportPresentation: Identifiable {
    let id = UUID()
    let topic: HelpSupportView.Topic
}

@main
struct SpectRoomApp: App {
    /// Firebase must configure in `AppDelegate.didFinishLaunching` only — not here.
    /// Early `Auth.auth()` from `App.init` breaks phone/MFA (nil tokenManager).
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var appState = AppStateManager.shared
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("selectedLanguage") private var selectedLanguage: String = "sv"
    @State private var languageChanged = false
    @State private var moderationSupport: ModerationSupportPresentation? = nil
    
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-KeyboardComposerVisualTest") {
                KeyboardStickyComposerVisualTest()
            } else {
                mainRootView
            }
            #else
            mainRootView
            #endif
        }
    }
    
    @ViewBuilder
    private var mainRootView: some View {
        Group {
            if !appState.hasResolvedAuthState && !appState.isAuthenticated {
                // Wait for Firebase to restore session before showing welcome/sign-in
                LaunchAuthPlaceholderView()
            } else if appState.pendingMfaSignIn {
                MfaVerificationView(kind: .signIn)
                    .environmentObject(appState)
            } else if appState.isAuthenticated {
                if appState.needsMfaEnrollment {
                    MfaVerificationView(kind: .enroll)
                        .environmentObject(appState)
                } else if !appState.hasResolvedProfileRouting {
                    // Wait until profile is loaded and completion flags are synced.
                    LaunchAuthPlaceholderView()
                } else if appState.hasCompletedInitialProfile {
                    ContentView()
                        .environmentObject(appState)
                } else {
                    // Incomplete profile: stay here until Save succeeds. No skip into the app.
                    ProfileEditView(isMandatoryCompletion: true)
                        .environmentObject(appState)
                }
            } else if appState.hasCompletedOnboarding {
                // Skip welcome - either completed with "Don't show again", or mid-session after Get Started
                AuthenticationView()
                    .environmentObject(appState)
            } else {
                // Show welcome (first launch, or after logout when "Don't show again" was not checked)
                OnboardingView()
                    .environmentObject(appState)
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onOpenURL { url in
            if url.scheme == "spectroom" {
                // Deep link from email verification page or in-app links.
                return
            }
            _ = Auth.auth().canHandle(url)
        }
        .overlay {
            if let notice = appState.pendingModerationNotice {
                SystemWarningOverlay(
                    title: notice.title,
                    message: notice.message,
                    acceptLabel: notice.acceptLabel,
                    requiresCheckbox: notice.requiresCheckbox,
                    acceptButtonColor: notice.usesBlueAcceptButton ? .blue : .orange,
                    secondaryLinkTitle: notice.showsContactSupport ? notice.contactSupportLabel : nil,
                    onSecondaryLink: notice.showsContactSupport
                        ? {
                            let topic: HelpSupportView.Topic
                            switch notice.kind {
                            case .banAcknowledgement, .loginBanned:
                                topic = .accountBan
                            case .deletedAcknowledgement, .loginDeleted:
                                topic = .accountDeleted
                            default:
                                topic = .accountFreeze
                            }
                            moderationSupport = ModerationSupportPresentation(topic: topic)
                        }
                        : nil
                ) {
                    appState.dismissModerationNotice()
                }
                .zIndex(999)
            }
        }
        .sheet(item: $moderationSupport) { presentation in
            HelpSupportView(
                initialTopic: presentation.topic,
                lockedTopic: presentation.topic,
                maxMessageLength: 200,
                onMessageSent: {
                    moderationSupport = nil
                    appState.dismissModerationNotice()
                }
            )
            .id(presentation.id)
            .environmentObject(appState)
        }
        .onAppear {
            // Set online status when app first appears and user is authenticated
            if appState.isAuthenticated {
                appState.startListeningForModerationStatus()
                Task {
                    await appState.updateAppStateInFirestore(isActive: true)
                    await appState.refreshPendingModerationNotice()
                }
            }
        }
        .onChange(of: appState.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                appState.startListeningForModerationStatus()
                Task {
                    await appState.refreshPendingModerationNotice()
                }
            }
        }
        .onChange(of: appState.hasResolvedUserProfile) { _, resolved in
            if resolved, appState.isAuthenticated {
                appState.startListeningForModerationStatus()
                Task {
                    await appState.refreshPendingModerationNotice()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Update online status and preload photos when app becomes active
            if appState.isAuthenticated {
                appState.startListeningForModerationStatus()
                Task {
                    await appState.updateAppStateInFirestore(isActive: true)
                    await FirebaseAuthService.shared.syncPhotosFromStorage()
                    appState.refreshUnreadMessageCount()
                    await appState.refreshPendingModerationNotice()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if appState.isAuthenticated {
                appState.syncAppIconBadgeBeforeBackground()
                Task {
                    await appState.updateAppStateInFirestore(isActive: false)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            if appState.isAuthenticated {
                appState.syncAppIconBadgeBeforeBackground()
                Task {
                    await appState.updateAppStateInFirestore(isActive: false)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("LanguageChanged"))) { _ in
            // Trigger view refresh when language changes
            languageChanged.toggle()
        }
        .id(languageChanged) // Force view refresh on language change
    }
}

/// Neutral launch screen while Firebase restores the persisted session.
private struct LaunchAuthPlaceholderView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            SpectRoomBackground()
        }
    }
}

// MARK: - AppDelegate for handling push notifications
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    private static var pendingAPNsToken: Data?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Only safe place to configure Firebase for phone/MFA (firebase-ios-sdk#16273).
        guard FirebaseBootstrap.configureIfNeeded() else {
            assertionFailure("Firebase configure failed in didFinishLaunching")
            return true
        }
        FirebaseAuthService.shared.startAuthListening()
        Self.forwardPendingAPNsTokenToAuthIfPossible()
        // Ensure MFA test-mode probe is satisfied after Auth listeners are live.
        FirebaseBootstrap.applyDebugPhoneAuthSettings()

        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        // Phone / MFA silent verification needs APNs registration even if the user
        // declines alert permission. Visible notification prompts stay separate.
        if !ProcessInfo.processInfo.arguments.contains("-KeyboardComposerVisualTest") {
            application.registerForRemoteNotifications()
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if granted {
                    print("✅ Notification permission granted on app launch")
                } else {
                    print("❌ Notification permission denied on app launch")
                }
                if let error {
                    print("⚠️ Notification permission error: \(error.localizedDescription)")
                }
            }
        }
        
        return true
    }
    
    // Handle APNs token registration
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("📱 APNs token received (\(deviceToken.count) bytes)")
        Messaging.messaging().apnsToken = deviceToken
        Self.pendingAPNsToken = deviceToken
        Self.forwardPendingAPNsTokenToAuthIfPossible()
    }

    /// After Firebase is configured in didFinishLaunching, Auth's tokenManager exists and
    /// setAPNSToken is safe. Needed for silent push verification on real devices.
    private static func forwardPendingAPNsTokenToAuthIfPossible() {
        guard FirebaseBootstrap.isConfigured, let token = pendingAPNsToken else { return }
        #if DEBUG
        // Prefer sandbox in DEBUG builds; .unknown also works if the build is installed via Xcode.
        Auth.auth().setAPNSToken(token, type: .sandbox)
        #else
        Auth.auth().setAPNSToken(token, type: .prod)
        #endif
        print("✅ APNs token forwarded to Firebase Auth")
        pendingAPNsToken = nil
    }
    
    // Handle APNs token registration failure
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        Messaging.messaging().appDidReceiveMessage(userInfo)
        syncBadgeCount(from: userInfo)
        completionHandler(.newData)
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        Auth.auth().canHandle(url)
    }
    
    private func syncBadgeCount(from userInfo: [AnyHashable: Any]) {
        if let aps = userInfo["aps"] as? [String: Any] {
            if let badge = aps["badge"] as? Int {
                Task { @MainActor in
                    AppStateManager.shared.unreadMessageCount = badge
                    NotificationService.shared.setAppIconBadgeCount(badge)
                }
                return
            }
        }
        
        if let badgeString = userInfo["badge"] as? String, let badge = Int(badgeString) {
            Task { @MainActor in
                AppStateManager.shared.unreadMessageCount = badge
                NotificationService.shared.setAppIconBadgeCount(badge)
            }
            return
        }
        
        if let gcmOptions = userInfo["gcm.notification"] as? [String: Any],
           let badgeString = gcmOptions["badge"] as? String,
           let badge = Int(badgeString) {
            Task { @MainActor in
                AppStateManager.shared.unreadMessageCount = badge
                NotificationService.shared.setAppIconBadgeCount(badge)
            }
        }
    }
    
    // MARK: - MessagingDelegate
    
    // Handle FCM token refresh
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("📱 FCM token received: \(fcmToken ?? "nil")")
        
        guard let fcmToken = fcmToken else {
            print("⚠️ FCM token is nil")
            return
        }
        
        // Save FCM token to Firestore
        Task {
            await saveFCMTokenToFirestore(fcmToken)
        }
    }
    
    // Save FCM token to Firestore
    private func saveFCMTokenToFirestore(_ token: String) async {
        guard let userId = FirebaseAuthService.shared.auth.currentUser?.uid else {
            print("⚠️ No user logged in, cannot save FCM token")
            return
        }
        
        do {
            try await FirebaseAuthService.shared.updateUserData(["fcmToken": token])
            print("✅ FCM token saved to Firestore for user: \(userId)")
        } catch {
            print("❌ Failed to save FCM token to Firestore: \(error.localizedDescription)")
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        syncBadgeCount(from: userInfo)
        refreshModerationNoticeIfNeeded(from: userInfo)
        
        if NotificationService.shouldSuppressForegroundMatchNotification(userInfo: userInfo) {
            completionHandler([])
            return
        }
        
        if NotificationService.shouldSuppressForegroundMessageNotification(userInfo: userInfo) {
            completionHandler([])
            return
        }
        
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        syncBadgeCount(from: userInfo)
        refreshModerationNoticeIfNeeded(from: userInfo)
        print("📱 Notification tapped, userInfo: \(userInfo)")
        
        let type = NotificationService.notificationString(userInfo, key: "type")
        switch type {
        case "match":
            if let matchId = NotificationService.notificationString(userInfo, key: "matchId") {
                print("📱 User tapped match notification: \(matchId)")
            }
        case "message":
            if let senderId = NotificationService.notificationString(userInfo, key: "senderId") {
                print("📱 User tapped message notification from: \(senderId)")
                DispatchQueue.main.async {
                    AppStateManager.shared.openConversationFromNotification(senderId: senderId)
                }
            } else {
                print("⚠️ Message notification tap missing senderId")
            }
        case "moderation_warning", "moderation_freeze", "moderation_freeze_extended", "moderation_unfreeze", "moderation_ban", "moderation_unban", "moderation_account_restored":
            print("📱 User opened moderation notification: \(type ?? "")")
            Task { @MainActor in
                if type == "moderation_account_restored" {
                    AppStateManager.shared.presentAccountRestoredNotice()
                }
                AppStateManager.shared.startListeningForModerationStatus()
                await AppStateManager.shared.refreshPendingModerationNotice()
            }
        default:
            print("⚠️ Unknown or missing notification type on tap: \(type ?? "nil")")
        }
        
        completionHandler()
    }

    private func refreshModerationNoticeIfNeeded(from userInfo: [AnyHashable: Any]) {
        let type = NotificationService.notificationString(userInfo, key: "type")
        switch type {
        case "moderation_warning", "moderation_freeze", "moderation_freeze_extended", "moderation_ban", "moderation_unban":
            Task { @MainActor in
                AppStateManager.shared.startListeningForModerationStatus()
                await AppStateManager.shared.refreshPendingModerationNotice()
            }
        case "moderation_account_restored":
            Task { @MainActor in
                AppStateManager.shared.presentAccountRestoredNotice()
                AppStateManager.shared.startListeningForModerationStatus()
                await AppStateManager.shared.refreshPendingModerationNotice()
            }
        default:
            break
        }
    }
}
