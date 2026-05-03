//
//  SpectRoomApp.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import FirebaseCore
import FirebaseMessaging
import Combine
import UserNotifications

@main
struct SpectRoomApp: App {
    @StateObject private var appState = AppStateManager.shared
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("selectedLanguage") private var selectedLanguage: String = "en"
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var languageChanged = false
    
    init() {
        // Configure Firebase - try to load from bundle first, then fallback to file path
        var options: FirebaseOptions?
        var configurationSource: String?
        
        // First, try to load from app bundle (if file is added to Xcode project)
        if let bundlePath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let bundleOptions = FirebaseOptions(contentsOfFile: bundlePath) {
            options = bundleOptions
            configurationSource = "main bundle"
        }
        // Fallback: try to load from project directory
        else if let projectPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist", inDirectory: nil),
                 let projectOptions = FirebaseOptions(contentsOfFile: projectPath) {
            options = projectOptions
            configurationSource = "project directory"
        }
        // Last resort: try absolute path
        else {
            let absolutePath = "/Users/evyatardayan/Desktop/My projects/swift/SpectRoom/SpectRoom/GoogleService-Info.plist"
            if FileManager.default.fileExists(atPath: absolutePath),
               let absoluteOptions = FirebaseOptions(contentsOfFile: absolutePath) {
                options = absoluteOptions
                configurationSource = "absolute path"
            }
        }
        
        if let options = options {
            FirebaseApp.configure(options: options)
            print("✅ Firebase configured with project: \(options.projectID) (source: \(configurationSource ?? "unknown"))")
        } else {
            // If all else fails, try default configuration (might work if file is in bundle)
            FirebaseApp.configure()
            if let app = FirebaseApp.app() {
                print("✅ Firebase configured with default options: \(app.options.projectID)")
            } else {
                assertionFailure("❌ Firebase configuration failed. Ensure GoogleService-Info.plist is included in the target.")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isAuthenticated {
                    if appState.hasCompletedInitialProfile {
                        ContentView()
                            .environmentObject(appState)
                    } else if appState.isNewSignup {
                        // New user after signup - must complete profile
                        ProfileEditView(isMandatoryCompletion: true)
                            .environmentObject(appState)
                    } else {
                        // Existing user with incomplete profile - allow access but encourage completion
                        ContentView()
                            .environmentObject(appState)
                    }
                } else if appState.hasCompletedOnboarding {
                    // User has completed onboarding before - show sign-in view
                    // hasCompletedOnboarding persists across sign-outs, so users won't see onboarding again
                    AuthenticationView()
                        .environmentObject(appState)
                } else {
                    // New user (first app install) - show welcome wizard
                    // This should only display once for new users after first app installation
                    OnboardingView()
                        .environmentObject(appState)
                }
            }
            .preferredColorScheme(isDarkMode ? .dark : .light)
            .onAppear {
                // Set online status when app first appears and user is authenticated
                if appState.isAuthenticated {
                    Task {
                        await appState.updateAppStateInFirestore(isActive: true)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Update online status and preload photos when app becomes active
                if appState.isAuthenticated {
                    Task {
                        await appState.updateAppStateInFirestore(isActive: true)
                        await FirebaseAuthService.shared.syncPhotosFromStorage()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                // Update offline status when app goes to background
                if appState.isAuthenticated {
                    Task {
                        await appState.updateAppStateInFirestore(isActive: false)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                // Update offline status when app enters background
                if appState.isAuthenticated {
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
}

// MARK: - AppDelegate for handling push notifications
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Set UNUserNotificationCenter delegate
        UNUserNotificationCenter.current().delegate = self
        
        // Set Firebase Messaging delegate
        Messaging.messaging().delegate = self
        
        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
                print("✅ Notification permission granted on app launch")
            } else {
                print("❌ Notification permission denied on app launch")
            }
        }
        
        return true
    }
    
    // Handle APNs token registration
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("📱 APNs token received")
        // Pass token to Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
    }
    
    // Handle APNs token registration failure
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
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
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        print("📱 Notification tapped, userInfo: \(userInfo)")
        
        if let type = userInfo["type"] as? String {
            switch type {
            case "match":
                if let matchId = userInfo["matchId"] as? String {
                    print("📱 User tapped match notification: \(matchId)")
                    // Set flag to open matches view
                    DispatchQueue.main.async {
                        // TODO: Navigate to matches view when match notification is tapped
                        // For now, we can set a flag that the MessagesView can check
                        print("📱 Match notification tapped, matchId: \(matchId)")
                    }
                }
            case "message":
                if let senderId = userInfo["senderId"] as? String {
                    print("📱 User tapped message notification from: \(senderId)")
                    // Set flag to open conversation when app opens
                    DispatchQueue.main.async {
                        AppStateManager.shared.conversationToOpenSenderId = senderId
                        AppStateManager.shared.shouldOpenConversation = true
                        print("📱 Set conversationToOpenSenderId to: \(senderId)")
                        print("📱 Set shouldOpenConversation to: true")
                    }
                }
            default:
                break
            }
        }
        
        completionHandler()
    }
}
