//
//  AppStateManager.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import Foundation
import SwiftUI
import FirebaseAuth
import Combine
import UIKit

class AppStateManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var hasResolvedAuthState = false
    @Published var hasCompletedOnboarding = false
    @Published var hasCompletedInitialProfile = false
    @Published var isNewSignup = false
    @Published var signUpName: String = ""
    @Published var currentUser: SpectRoomUser?
    @Published var matches: [Match] = []
    @Published var conversations: [Conversation] = []
    @Published var cachedMatches: [MatchDisplay] = [] // Cache for matches list
    @Published var cachedMessageConversations: [MessageDisplay] = [] // Cache for message conversations list
    @Published var cachedDiscoverProfiles: [ProfileCard] = []
    @Published var cachedDiscoverCardIndex: Int = 0
    private var isDiscoverProfilesCacheValid = false
    @Published var blockedUsers: [BlockedUser] = []
    @Published var blockedByUsers: [BlockedUser] = []
    @Published private(set) var suppressedBlockedAlertUserIds: Set<String> = []
    @Published var authErrorMessage: String?
    private var lastMatchesUpdate: Date?
    private var lastMessageConversationsUpdate: Date?
    
    // Cache for individual conversation messages (keyed by otherUserId)
    private var cachedConversationStates: [String: CachedConversationState] = [:]
    @Published var isLoading = false
    
    // Match notification properties
    @Published var showingMatchNotification = false
    @Published var newMatchProfile: ProfileCard?
    @Published var shouldOpenMessageModal = false
    @Published var viewedMatchProfileId: String? = nil // Track when a match profile is viewed
    private var lastMatchId: String?
    private var isShowingSwipeMatchPopup = false
    
    // New message notification properties
    @Published var showingNewMessageNotification = false
    @Published var newMessageSenderName: String = ""
    @Published var newMessageSenderPhotoURL: String?
    @Published var newMessageSenderId: String = ""
    @Published var shouldOpenConversation = false
    @Published var conversationToOpenSenderId: String? = nil
    @Published var conversationToOpenProfile: ProfileCard? = nil
    @Published var currentlyOpenConversationSenderId: String? = nil // Track which conversation is currently open
    @Published private(set) var isMessagesTabActive = false
    @Published var unreadMessageCount: Int = 0
    @Published var conversationUnreadCounts: [String: Int] = [:]
    private var lastMessageId: String?
    private var lastPlayedMessageSoundId: String?
    
    private let firebaseAuth = FirebaseAuthService.shared
    private var cancellables = Set<AnyCancellable>()
    private let newMessageReceivedSubject = PassthroughSubject<MessageDisplay, Never>()
    var newMessageReceivedPublisher: AnyPublisher<MessageDisplay, Never> {
        newMessageReceivedSubject.eraseToAnyPublisher()
    }
    private let newMatchReceivedSubject = PassthroughSubject<MatchDisplay, Never>()
    var newMatchReceivedPublisher: AnyPublisher<MatchDisplay, Never> {
        newMatchReceivedSubject.eraseToAnyPublisher()
    }
    
    static let shared = AppStateManager()
    
    private init() {
        // Listen to Firebase authentication state changes
        // Ensure all updates happen on the main thread to avoid publishing from background threads
        // Mirror Firebase auth immediately so launch routing does not wait on the Combine subscription.
        isAuthenticated = firebaseAuth.isAuthenticated
        hasResolvedAuthState = firebaseAuth.hasResolvedAuthState
        
        firebaseAuth.$hasResolvedAuthState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] resolved in
                self?.hasResolvedAuthState = resolved
            }
            .store(in: &cancellables)
        
        firebaseAuth.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuth in
                self?.isAuthenticated = isAuth
                if isAuth {
                    // Returning session: never show the welcome wizard again.
                    if self?.hasCompletedOnboarding != true {
                        self?.hasCompletedOnboarding = true
                        self?.saveAppState()
                    }
                    // User is authenticated - set online status and preload photos
                    Task {
                        await self?.updateOnlineStatus(isOnline: true)
                        await self?.preloadUserPhotos()
                    }
                    // Start listening for new matches when authenticated
                    // This will notify users when they receive a match (even if they didn't swipe)
                    self?.startListeningForMatches()
                    // Start listening for new messages when authenticated
                    // This will notify users when they receive a new message
                    self?.startListeningForNewMessages()
                    self?.refreshUnreadMessageCount()
                } else {
                    // Set offline status before clearing data
                    Task {
                        await self?.updateOnlineStatus(isOnline: false)
                    }
                    // Clear user data when not authenticated to prevent stale data
                    self?.currentUser = nil
                    self?.unreadMessageCount = 0
                    self?.clearMessageConversationsCache() // Clear message conversations cache
                    self?.clearDiscoverProfilesCache()
                    Task { @MainActor in
                        NotificationService.shared.setAppIconBadgeCount(0)
                    }
                    print("🔐 User logged out - cleared all user data")
                }
            }
            .store(in: &cancellables)
        
        // Listen to Firebase user changes
        // Ensure all updates happen on the main thread to avoid publishing from background threads
        firebaseAuth.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newUser in
                self?.currentUser = newUser
                if let user = newUser {
                    print("🔄 AppStateManager: Updated currentUser with \(user.photos.count) photos")
                    self?.blockedUsers = user.blockedUsers
                    self?.blockedByUsers = user.blockedByUsers
                    self?.loadSuppressedBlockedAlerts()
                } else {
                    self?.blockedUsers = []
                    self?.blockedByUsers = []
                    self?.suppressedBlockedAlertUserIds = []
                }
            }
            .store(in: &cancellables)
        
        // Note: Sound is now played when push notification is received (handled by iOS)
        
        // Load saved state if available (but not authentication state)
        loadAppState()
        
        // Clear any stale authentication data on app start
        clearStaleAuthData()
    }
    
    // MARK: - Authentication
    func signIn(email: String, password: String) {
        isLoading = true
        
        // Check for empty fields - treat as invalid credentials
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedEmail.isEmpty || trimmedPassword.isEmpty {
            // Treat empty fields as invalid credentials
            Task { @MainActor in
                self.isLoading = false
                let currentAttempts = UserDefaults.standard.integer(forKey: "failedSignInAttempts")
                let newAttempts = currentAttempts + 1
                UserDefaults.standard.set(newAttempts, forKey: "failedSignInAttempts")
                
                // Show extended message every 5th time (5th, 10th, 15th, etc.)
                if newAttempts % 5 == 0 {
                    self.authErrorMessage = "auth.error.credentials.with.forgot".localized
                } else {
                    self.authErrorMessage = "auth.error.credentials".localized
                }
            }
            return
        }
        
        Task {
            do {
                try await firebaseAuth.signIn(email: trimmedEmail, password: trimmedPassword)
                await MainActor.run {
                    self.isLoading = false
                    // Reset failed sign-in attempts counter on successful sign-in
                    UserDefaults.standard.set(0, forKey: "failedSignInAttempts")
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    print("Sign in error: \(error.localizedDescription)")
                    
                    // Increment failed sign-in attempts counter
                    let currentAttempts = UserDefaults.standard.integer(forKey: "failedSignInAttempts")
                    let newAttempts = currentAttempts + 1
                    UserDefaults.standard.set(newAttempts, forKey: "failedSignInAttempts")
                    
                    // Show extended message every 5th time (5th, 10th, 15th, etc.)
                    if newAttempts % 5 == 0 {
                        self.authErrorMessage = "auth.error.credentials.with.forgot".localized
                    } else {
                        self.authErrorMessage = "auth.error.credentials".localized
                    }
                }
            }
        }
    }
    
    func signUp(name: String, age: Int, email: String, password: String) {
        isLoading = true
        
        Task {
            do {
                try await firebaseAuth.signUp(email: email, password: password, name: name, age: age)
                await MainActor.run {
                    self.isLoading = false
                    // Mark as new signup to trigger mandatory profile completion
                    self.isNewSignup = true
                    self.signUpName = name
                    self.hasCompletedInitialProfile = false
                    self.saveAppState()
                    print("🆕 New user signed up - will show mandatory profile completion")
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    // Handle error - you might want to show an alert
                    print("Sign up error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func signOut() {
        Task {
            do {
                try await firebaseAuth.signOut()
                await MainActor.run {
                    currentUser = nil
                    isNewSignup = false
                    hasCompletedInitialProfile = false
                    matches = []
                    cachedMatches = []
                    lastMatchesUpdate = nil
                    conversations = []
                    blockedUsers = []
                    blockedByUsers = []
                    clearMessageConversationsCache()
                    clearDiscoverProfilesCache()
                    
                    // Show welcome again after logout unless the user opted out
                    if !UserDefaults.standard.bool(forKey: "dontShowWelcomeAgain") {
                        hasCompletedOnboarding = false
                    }
                    
                    saveAppState()
                    print("🔐 User signed out successfully - hasCompletedOnboarding: \(hasCompletedOnboarding)")
                }
            } catch {
                await MainActor.run {
                    print("Sign out error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    
    func resetPassword(email: String) {
        Task {
            do {
                try await firebaseAuth.resetPassword(email: email)
            } catch {
                print("Reset password error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - User Data
    // User data is now automatically synced with FirebaseAuthService via @Published properties
    
    func cleanupUserPhotos() {
        if var user = currentUser {
            let originalCount = user.photos.count
            user.photos = user.photos.filter { photoURL in
                let trimmedURL = photoURL.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmedURL.isEmpty && URL(string: trimmedURL) != nil
            }
            currentUser = user
            print("🧹 AppStateManager: Cleaned up photos from \(originalCount) to \(user.photos.count)")
            saveAppState()
        }
    }
    
    func isProfileComplete() -> Bool {
        guard let user = currentUser else { return false }
        
        // Check full name (first and last at least)
        let nameComponents = user.name.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        let hasFullName = nameComponents.count >= 2 && nameComponents.allSatisfy { !$0.isEmpty }
        
        // Check age
        let hasValidAge = user.age >= 18 && user.age <= 100
        
        // Check about me (at least 20 characters)
        let hasAboutMe = user.bio.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20
        
        // Check interests (at least 3)
        let hasInterests = user.interests.count >= 3
        
        // Check photos (at least 3)
        let validPhotos = user.photos.filter { photoURL in
            let trimmedURL = photoURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmedURL.isEmpty && URL(string: trimmedURL) != nil
        }
        let hasPhotos = validPhotos.count >= 3
        
        // Check profile photo (must exist - first photo)
        let hasProfilePhoto = !validPhotos.isEmpty
        
        let isComplete = hasFullName && hasValidAge && hasAboutMe && hasInterests && hasPhotos && hasProfilePhoto
        
        print("📋 Profile completion check:")
        print("  - Full name: \(hasFullName) (\(nameComponents.count) components)")
        print("  - Valid age: \(hasValidAge) (\(user.age))")
        print("  - About me: \(hasAboutMe) (\(user.bio.count) chars)")
        print("  - Interests: \(hasInterests) (\(user.interests.count) items)")
        print("  - Photos: \(hasPhotos) (\(validPhotos.count) photos)")
        print("  - Profile photo: \(hasProfilePhoto)")
        print("  - Overall: \(isComplete)")
        
        return isComplete
    }
    
    
    // MARK: - Onboarding
    func completeOnboarding(dontShowAgain: Bool = false) {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(dontShowAgain, forKey: "dontShowWelcomeAgain")
        saveAppState()
    }
    
    func resetOnboarding() {
        hasCompletedOnboarding = false
        UserDefaults.standard.set(false, forKey: "dontShowWelcomeAgain")
        saveAppState()
        print("🔄 Onboarding state reset - wizard will show on next app launch")
    }
    
    func completeInitialProfile() {
        hasCompletedInitialProfile = true
        isNewSignup = false
        signUpName = "" // Clear the sign up name
        saveAppState()
        print("✅ Initial profile completed - user can now access main app")
    }
    
    // MARK: - Matches
    func addMatch(_ match: Match) {
        matches.append(match)
        saveAppState()
    }
    
    func removeMatch(_ match: Match) {
        matches.removeAll { $0.id == match.id }
        saveAppState()
    }

    // MARK: - Matches Cache
    func getCachedOrFreshMatches() async throws -> [MatchDisplay] {
        if let lastUpdate = lastMatchesUpdate,
           Date().timeIntervalSince(lastUpdate) < 60,
           !cachedMatches.isEmpty {
            print("💕 Returning cached matches (\(cachedMatches.count) items, updated \(Date().timeIntervalSince(lastUpdate)) seconds ago)")
            return cachedMatches
        }
        return try await refreshMatchesCache()
    }
    
    @discardableResult
    func refreshMatchesCache() async throws -> [MatchDisplay] {
        print("💕 Refreshing matches cache...")
        let fetched = try await firebaseAuth.fetchMatches()
        await MainActor.run {
            cachedMatches = fetched
            lastMatchesUpdate = Date()
        }
        return fetched
    }
    
    func updateMatchesCache(with match: MatchDisplay) {
        Task {
            await MainActor.run {
                if let index = cachedMatches.firstIndex(where: { $0.otherUser.userId == match.otherUser.userId }) {
                    cachedMatches[index] = match
                } else {
                    cachedMatches.insert(match, at: 0)
                }
                cachedMatches.sort { $0.matchedAt > $1.matchedAt }
                lastMatchesUpdate = Date()
                newMatchReceivedSubject.send(match)
            }
        }
    }

    // MARK: - Discover Profiles Cache
    var hasValidDiscoverProfilesCache: Bool {
        isDiscoverProfilesCacheValid
    }

    func updateDiscoverProfilesCache(profiles: [ProfileCard], cardIndex: Int) {
        guard !profiles.isEmpty else {
            clearDiscoverProfilesCache()
            return
        }
        cachedDiscoverProfiles = profiles
        cachedDiscoverCardIndex = cardIndex
        isDiscoverProfilesCacheValid = true
    }

    func clearDiscoverProfilesCache() {
        cachedDiscoverProfiles = []
        cachedDiscoverCardIndex = 0
        isDiscoverProfilesCacheValid = false
    }
    
    // MARK: - Conversations
    func addConversation(_ conversation: Conversation) {
        conversations.append(conversation)
        saveAppState()
    }
    
    func updateConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
            saveAppState()
        }
    }
    
    // MARK: - Persistence
    func saveAppState() {
        let encoder = JSONEncoder()
        
        if let userData = try? encoder.encode(currentUser) {
            UserDefaults.standard.set(userData, forKey: "currentUser")
        }
        
        // Don't save authentication state - Firebase handles this
        UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(hasCompletedInitialProfile, forKey: "hasCompletedInitialProfile")
        UserDefaults.standard.set(isNewSignup, forKey: "isNewSignup")
        
        if let matchesData = try? encoder.encode(matches) {
            UserDefaults.standard.set(matchesData, forKey: "matches")
        }
        
        if let conversationsData = try? encoder.encode(conversations) {
            UserDefaults.standard.set(conversationsData, forKey: "conversations")
        }
    }
    
    private func loadAppState() {
        let decoder = JSONDecoder()
        
        if let userData = UserDefaults.standard.data(forKey: "currentUser"),
           let user = try? decoder.decode(SpectRoomUser.self, from: userData) {
            currentUser = user
            blockedUsers = user.blockedUsers
            blockedByUsers = user.blockedByUsers
            print("📱 Loaded user from UserDefaults with \(user.photos.count) photos")
        }
        
        // Don't load authentication state from UserDefaults - rely on Firebase
        // isAuthenticated will be set by FirebaseAuthService
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        hasCompletedInitialProfile = UserDefaults.standard.bool(forKey: "hasCompletedInitialProfile")
        isNewSignup = UserDefaults.standard.bool(forKey: "isNewSignup")
        
        if let matchesData = UserDefaults.standard.data(forKey: "matches"),
           let matches = try? decoder.decode([Match].self, from: matchesData) {
            self.matches = matches
        }
        
        if let conversationsData = UserDefaults.standard.data(forKey: "conversations"),
           let conversations = try? decoder.decode([Conversation].self, from: conversationsData) {
            self.conversations = conversations
        }
    }
    
    private func clearStaleAuthData() {
        // Clear any cached authentication data to prevent stale state
        UserDefaults.standard.removeObject(forKey: "isAuthenticated")
        print("🧹 Cleared stale authentication data from UserDefaults")
    }
    
    func resetAllAppState() {
        // Reset all app state for testing/development
        Task {
            do {
                // Delete all swipes, matches, and messages from Firebase
                try await FirebaseAuthService.shared.deleteAllUserInteractions()
                
                await MainActor.run {
                    // Reset local state
                    hasCompletedOnboarding = false
                    hasCompletedInitialProfile = false
                    isNewSignup = false
                    currentUser = nil
                    matches = []
                    conversations = []
                    blockedUsers = []
                    blockedByUsers = []
                    clearMessageConversationsCache() // Clear message conversations cache
                    clearDiscoverProfilesCache()
                    UserDefaults.standard.set(false, forKey: "dontShowWelcomeAgain")
                    saveAppState()
                    print("🔄 All app state reset - app will start fresh")
                }
            } catch {
                await MainActor.run {
                    print("❌ Error deleting user interactions: \(error.localizedDescription)")
                    // Still reset local state even if Firebase deletion fails
                    hasCompletedOnboarding = false
                    hasCompletedInitialProfile = false
                    isNewSignup = false
                    currentUser = nil
                    matches = []
                    conversations = []
                    clearMessageConversationsCache()
                    clearDiscoverProfilesCache()
                    UserDefaults.standard.set(false, forKey: "dontShowWelcomeAgain")
                    saveAppState()
                }
            }
        }
    }
    
    func isUserBlocked(_ userId: String) -> Bool {
        blockedUsers.contains(where: { $0.id == userId })
    }
    
    func isBlockedByUser(_ userId: String) -> Bool {
        blockedByUsers.contains(where: { $0.id == userId })
    }
    
    func isMessagingBlocked(with userId: String) -> Bool {
        isUserBlocked(userId) || isBlockedByUser(userId)
    }
    
    func shouldShowBlockedAlert(for userId: String) -> Bool {
        !suppressedBlockedAlertUserIds.contains(userId)
    }
    
    func suppressBlockedAlert(for userId: String) {
        suppressedBlockedAlertUserIds.insert(userId)
        persistSuppressedBlockedAlerts()
    }
    
    func unsuppressBlockedAlert(for userId: String) {
        suppressedBlockedAlertUserIds.remove(userId)
        persistSuppressedBlockedAlerts()
    }
    
    private var suppressedBlockedAlertsStorageKey: String? {
        guard let uid = firebaseAuth.auth.currentUser?.uid else { return nil }
        return "suppressedBlockedAlertUserIds_\(uid)"
    }
    
    func loadSuppressedBlockedAlerts() {
        guard let key = suppressedBlockedAlertsStorageKey else {
            suppressedBlockedAlertUserIds = []
            return
        }
        let ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        suppressedBlockedAlertUserIds = Set(ids)
    }
    
    private func persistSuppressedBlockedAlerts() {
        guard let key = suppressedBlockedAlertsStorageKey else { return }
        UserDefaults.standard.set(Array(suppressedBlockedAlertUserIds), forKey: key)
    }
    
    func refreshBlockedByUsers() {
        Task {
            do {
                let users = try await firebaseAuth.fetchBlockedByUsers()
                await MainActor.run {
                    self.blockedByUsers = users
                    if var current = self.currentUser {
                        current.blockedByUsers = users
                        self.currentUser = current
                    }
                }
            } catch {
                print("⚠️ Unable to refresh blockedBy users: \(error.localizedDescription)")
            }
        }
    }

    func blockUser(userId: String, name: String) {
        guard !isUserBlocked(userId) else { return }
        let blockedUser = BlockedUser(id: userId, name: name, blockedAt: Date())

        Task {
            await MainActor.run {
                self.blockedUsers.append(blockedUser)
                self.cachedDiscoverProfiles.removeAll { $0.userId == userId }
                if self.cachedDiscoverCardIndex >= self.cachedDiscoverProfiles.count {
                    self.cachedDiscoverCardIndex = max(0, self.cachedDiscoverProfiles.count - 1)
                }
                if var current = self.currentUser {
                    current.blockedUsers = self.blockedUsers
                    self.currentUser = current
                }
                self.saveAppState()
            }

            do {
                try await firebaseAuth.blockUser(userId: userId, name: name)
            } catch {
                print("⚠️ Unable to persist block to Firestore: \(error.localizedDescription)")
            }
        }
    }

    func unblockUser(userId: String) {
        guard isUserBlocked(userId) else { return }
        unsuppressBlockedAlert(for: userId)

        Task {
            await MainActor.run {
                self.blockedUsers.removeAll { $0.id == userId }
                if var current = self.currentUser {
                    current.blockedUsers = self.blockedUsers
                    self.currentUser = current
                }
                self.saveAppState()
            }

            do {
                try await firebaseAuth.unblockUser(userId: userId)
            } catch {
                print("⚠️ Unable to persist unblock to Firestore: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Photo Preloading
    private func preloadUserPhotos() async {
        // Preload photos from Firebase Storage to improve user experience
        print("🔄 Preloading user photos for better UX...")
        
        // Only sync photos once when user first logs in, not continuously
        guard currentUser?.photos.isEmpty == true else {
            print("📸 Photos already loaded, skipping preload")
            return
        }
        
        await firebaseAuth.syncPhotosFromStorage()
        print("✅ User photos preloaded successfully")
    }
    
    func startListeningForMatches() {
        guard isAuthenticated else {
            print("❌ Cannot start listening for matches - user not authenticated")
            return
        }
        
        print("💕 Starting to listen for new matches...")
        
        firebaseAuth.listenForNewMatches { [weak self] matchDisplay in
            self?.handleIncomingMatchNotification(matchDisplay)
        }
    }
    
    func presentMatchNotification(otherUser: ProfileCard, matchId: String) {
        let matchDisplay = MatchDisplay(
            id: matchId,
            otherUser: otherUser,
            matchedAt: Date()
        )
        handleIncomingMatchNotification(matchDisplay)
    }
    
    private func handleIncomingMatchNotification(_ matchDisplay: MatchDisplay) {
        DispatchQueue.main.async { [weak self] in
            print("💕 New match received: \(matchDisplay.otherUser.name)")
            print("💕 Match ID: \(matchDisplay.id)")
            
            guard self?.lastMatchId != matchDisplay.id else {
                print("💕 Duplicate match notification, ignoring")
                return
            }
            
            guard self?.showingMatchNotification != true else {
                print("💕 Match notification already showing, ignoring new match")
                return
            }
            
            self?.lastMatchId = matchDisplay.id
            self?.newMatchProfile = matchDisplay.otherUser
            self?.showingMatchNotification = true
            self?.updateMatchesCache(with: matchDisplay)
            self?.playMatchSoundIfEnabled()
            print("💕 Match notification set to show for: \(matchDisplay.otherUser.name)")
        }
    }
    
    private func playMatchSoundIfEnabled() {
        if let settings = currentUser?.preferences.notificationSettings {
            guard settings.newMatches, settings.soundEnabled else { return }
        }
        SoundService.shared.playMatchSound()
    }
    
    func dismissMatchNotification() {
        print("💕 Dismissing match notification")
        print("💕 Current showingMatchNotification: \(showingMatchNotification)")
        print("💕 Current newMatchProfile: \(newMatchProfile?.name ?? "nil")")
        
        showingMatchNotification = false
        newMatchProfile = nil
        shouldOpenMessageModal = false
        isShowingSwipeMatchPopup = false
        
        print("💕 Match notification dismissed")
    }
    
    func setShowingSwipeMatchPopup(_ showing: Bool) {
        print("💕 Setting isShowingSwipeMatchPopup to: \(showing)")
        isShowingSwipeMatchPopup = showing
    }
    
    // MARK: - New Message Notification
    
    func refreshUnreadMessageCount() {
        guard isAuthenticated else {
            unreadMessageCount = 0
            conversationUnreadCounts = [:]
            syncAppIconBadge()
            return
        }
        
        Task {
            do {
                async let totalUnreadTask = firebaseAuth.countUnreadIncomingMessages()
                async let perConversationTask = firebaseAuth.fetchUnreadCountsBySender()
                let (totalUnread, perConversation) = try await (totalUnreadTask, perConversationTask)
                await MainActor.run {
                    self.unreadMessageCount = totalUnread
                    self.conversationUnreadCounts = perConversation
                    self.syncAppIconBadge()
                }
            } catch {
                print("❌ Error loading unread message count: \(error)")
                await MainActor.run {
                    self.unreadMessageCount = 0
                    self.syncAppIconBadge()
                }
            }
        }
    }
    
    private func syncAppIconBadge() {
        let count = unreadMessageCount
        Task { @MainActor in
            NotificationService.shared.setAppIconBadgeCount(count)
        }
    }
    
    /// Sync badge immediately when leaving the app so it persists on the home screen icon.
    func syncAppIconBadgeBeforeBackground() {
        guard isAuthenticated else { return }
        
        let cachedTotal = conversationUnreadCounts.values.reduce(0, +)
        if cachedTotal > unreadMessageCount {
            unreadMessageCount = cachedTotal
        }
        syncAppIconBadge()
        
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SyncAppIconBadge") {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }
        
        guard backgroundTaskID != .invalid else { return }
        
        Task {
            do {
                let totalUnread = try await firebaseAuth.countUnreadIncomingMessages()
                await MainActor.run {
                    self.unreadMessageCount = totalUnread
                    NotificationService.shared.setAppIconBadgeCount(totalUnread)
                }
            } catch {
                print("❌ Failed to sync app icon badge before background: \(error)")
            }
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }
    }
    
    func refreshConversationUnreadCounts() {
        guard isAuthenticated else {
            conversationUnreadCounts = [:]
            return
        }
        
        Task {
            do {
                let counts = try await firebaseAuth.fetchUnreadCountsBySender()
                await MainActor.run {
                    self.conversationUnreadCounts = counts
                }
            } catch {
                print("❌ Error loading conversation unread counts: \(error)")
            }
        }
    }
    
    func markMessagesAsRead(from otherUserId: String) async {
        do {
            try await firebaseAuth.markMessagesAsRead(from: otherUserId)
            await MainActor.run {
                let clearedCount = self.conversationUnreadCounts[otherUserId] ?? 0
                var counts = self.conversationUnreadCounts
                counts[otherUserId] = 0
                self.conversationUnreadCounts = counts
                self.unreadMessageCount = max(0, self.unreadMessageCount - clearedCount)
                self.syncAppIconBadge()
                self.refreshUnreadMessageCount()
            }
        } catch {
            print("❌ Failed to mark messages as read: \(error)")
        }
    }
    
    func shouldSuppressMessageNotification(for senderId: String) -> Bool {
        if isMessagesTabActive {
            return true
        }
        if let openSenderId = currentlyOpenConversationSenderId, openSenderId == senderId {
            return true
        }
        return false
    }
    
    func setMessagesTabActive(_ isActive: Bool) {
        guard isMessagesTabActive != isActive else { return }
        isMessagesTabActive = isActive
        Task {
            await syncMessagesTabStateToFirestore(isActive: isActive)
        }
    }
    
    private func syncMessagesTabStateToFirestore(isActive: Bool) async {
        guard firebaseAuth.auth.currentUser != nil else { return }
        
        do {
            try await firebaseAuth.updateUserData([
                "messagesTabActive": isActive,
                "appStateUpdatedAt": Date().timeIntervalSince1970
            ])
            print("📱 Updated messages tab state in Firestore: \(isActive ? "active" : "inactive")")
        } catch {
            print("❌ Failed to update messages tab state: \(error)")
        }
    }
    
    func startListeningForNewMessages() {
        guard isAuthenticated else {
            print("❌ Cannot start listening for messages - user not authenticated")
            return
        }
        
        print("💬 Starting to listen for new messages...")
        
        firebaseAuth.listenForNewMessages { [weak self] senderId, senderName, senderPhotoURL, messageDocId, content, type, voiceDuration, createdAt, hasProfile in
            DispatchQueue.main.async {
                if !hasProfile {
                    print("💬 New message preview from: \(senderId), content: \(content.prefix(20))...")
                    self?.applyIncomingMessagePreview(
                        senderId: senderId,
                        senderName: senderName.isEmpty ? nil : senderName,
                        senderPhotoURL: senderPhotoURL,
                        content: content,
                        type: type,
                        voiceDuration: voiceDuration,
                        createdAt: createdAt
                    )
                    self?.incrementUnreadCount(for: senderId)
                    
                    // When this chat is open, the conversation UI appends the message and
                    // plays the sound together. Otherwise play here for list/other screens.
                    let chatIsOpen = self?.currentlyOpenConversationSenderId == senderId
                    if UIApplication.shared.applicationState == .active, chatIsOpen != true {
                        self?.playIncomingMessageSoundIfNeeded(for: messageDocId)
                    }
                    
                    if let openSenderId = self?.currentlyOpenConversationSenderId, openSenderId == senderId {
                        print("💬 Conversation with \(senderId) is already open, marking messages as read")
                        self?.lastMessageId = messageDocId
                        Task {
                            await self?.markMessagesAsRead(from: senderId)
                        }
                    }
                    return
                }
                
                print("💬 New message received from: \(senderName)")
                print("💬 Sender ID: \(senderId), Message Doc ID: \(messageDocId)")
                print("💬 Current showingNewMessageNotification state: \(self?.showingNewMessageNotification ?? false)")
                print("💬 Last message ID: \(self?.lastMessageId ?? "nil")")
                
                // Prevent duplicate notifications for the same message (using document ID)
                guard self?.lastMessageId != messageDocId else {
                    print("💬 Duplicate message notification (same document ID), ignoring")
                    return
                }
                
                // Only show notification if not already showing one
                guard self?.showingNewMessageNotification != true else {
                    print("💬 Message notification already showing, ignoring new message")
                    return
                }
                
                // If user is on Messages tab or already viewing this chat, skip notifications
                if self?.shouldSuppressMessageNotification(for: senderId) == true {
                    print("💬 Suppressing message notification for \(senderName) (messages tab or open conversation)")
                    self?.lastMessageId = messageDocId
                    return
                }
                
                self?.refreshUnreadMessageCount()
                
                // Check if app is in background/closed
                let isAppInBackground = UIApplication.shared.applicationState != .active
                
                // Only send push notification if app is closed/backgrounded
                if isAppInBackground {
                    // Fetch message content for notification
                    Task {
                        // Get message content for notification
                        let messageContent = try? await FirebaseAuthService.shared.fetchLatestMessageContent(from: senderId)
                        
                        let hasPermission = await NotificationService.shared.checkNotificationPermission()
                        if hasPermission && NotificationService.shared.areNotificationsEnabled() {
                            let badgeCount = await MainActor.run {
                                self?.unreadMessageCount ?? 0
                            }
                            NotificationService.shared.sendNewMessageNotification(
                                senderName: senderName,
                                messageContent: messageContent ?? content,
                                senderId: senderId,
                                badgeCount: badgeCount
                            )
                            print("📱 Push notification sent for message from: \(senderName)")
                        }
                    }
                }
                
                // Just update the message ID to prevent duplicates
                self?.lastMessageId = messageDocId
            }
        }
    }
    
    func playIncomingMessageSoundIfNeeded(for messageDocId: String) {
        guard lastPlayedMessageSoundId != messageDocId else { return }
        lastPlayedMessageSoundId = messageDocId
        
        if let settings = currentUser?.preferences.notificationSettings {
            guard settings.newMessages, settings.soundEnabled else { return }
        }
        
        SoundService.shared.playNewMessageSound()
    }
    
    func dismissNewMessageNotification() {
        print("💬 Dismissing new message notification")
        print("💬 Current showingNewMessageNotification: \(showingNewMessageNotification)")
        
        showingNewMessageNotification = false
        newMessageSenderName = ""
        newMessageSenderPhotoURL = nil
        newMessageSenderId = ""
        shouldOpenConversation = false
        conversationToOpenSenderId = nil
        conversationToOpenProfile = nil
        
        print("💬 New message notification dismissed")
    }
    
    
    // MARK: - Message Conversations Cache
    
    /// Get cached conversations if available and recent (within 30 seconds), otherwise fetch fresh
    func getCachedOrFreshConversations() async throws -> [MessageDisplay] {
        // If cache is empty or older than 30 seconds, fetch fresh
        if let lastUpdate = lastMessageConversationsUpdate,
           Date().timeIntervalSince(lastUpdate) < 30.0,
           !cachedMessageConversations.isEmpty {
            print("💬 Returning cached conversations (\(cachedMessageConversations.count) items, updated \(Date().timeIntervalSince(lastUpdate)) seconds ago)")
            refreshConversationUnreadCounts()
            return cachedMessageConversations
        }
        
        // Cache is stale or empty, fetch fresh
        print("💬 Cache is stale or empty, fetching fresh conversations...")
        return try await refreshMessageConversationsCache()
    }
    
    /// Refresh the message conversations cache from Firebase
    func refreshMessageConversationsCache() async throws -> [MessageDisplay] {
        print("💬 Refreshing message conversations cache...")
        async let latestMessagesTask = firebaseAuth.fetchLatestMessagesFromEachUser()
        async let unreadCountsTask = firebaseAuth.fetchUnreadCountsBySender()
        
        let latestMessages = try await latestMessagesTask
        let unreadCounts = try await unreadCountsTask
        let sortedMessages = latestMessages.sorted { $0.createdAt > $1.createdAt }
        
        await MainActor.run {
            cachedMessageConversations = sortedMessages
            conversationUnreadCounts = unreadCounts
            print("💬 Cache updated with \(sortedMessages.count) conversations")
            lastMessageConversationsUpdate = Date()
        }
        
        return sortedMessages
    }
    
    /// Update a single conversation in the cache (when a new message arrives or is sent)
    @MainActor
    func updateConversationInCache(_ conversation: MessageDisplay) {
        let newOtherUserId = otherUserId(for: conversation)
        var updated = cachedMessageConversations
        
        if let index = updated.firstIndex(where: { otherUserId(for: $0) == newOtherUserId }) {
            let existing = updated[index]
            guard conversation.createdAt >= existing.createdAt else {
                return
            }
            updated[index] = conversation
            print("💬 Updated conversation in cache: \(conversation.recipientName)")
        } else {
            updated.append(conversation)
            print("💬 Added new conversation to cache: \(conversation.recipientName)")
        }
        
        cachedMessageConversations = updated.sorted { $0.createdAt > $1.createdAt }
        lastMessageConversationsUpdate = Date()
        newMessageReceivedSubject.send(conversation)
    }
    
    @MainActor
    func applyIncomingMessagePreview(
        senderId: String,
        senderName: String?,
        senderPhotoURL: String?,
        content: String,
        type: MessageType,
        voiceDuration: TimeInterval?,
        createdAt: Date
    ) {
        guard let currentUserId = firebaseAuth.auth.currentUser?.uid else { return }
        
        let resolvedName = senderName
            ?? cachedMessageConversations.first(where: { otherUserId(for: $0) == senderId }).map { conversation in
                conversation.senderName == "You" ? conversation.recipientName : conversation.senderName
            }
            ?? "Unknown User"
        let cachedPhotoURL = cachedMessageConversations.first(where: { otherUserId(for: $0) == senderId }).flatMap { conversation in
            conversation.senderName == "You" ? conversation.recipientProfilePhotoURL : conversation.senderProfilePhotoURL
        }
        let resolvedPhotoURL = senderPhotoURL ?? cachedPhotoURL
        
        let message = Message(
            conversationId: UUID(),
            senderId: UUID(),
            senderFirebaseId: senderId,
            content: content,
            createdAt: createdAt,
            type: type,
            voiceDuration: voiceDuration
        )
        let messageDisplay = MessageDisplay(
            message: message,
            senderName: resolvedName,
            recipientName: "You",
            senderId: senderId,
            recipientId: currentUserId,
            senderProfilePhotoURL: resolvedPhotoURL,
            recipientProfilePhotoURL: currentUser?.profilePhotoURL
        )
        updateConversationInCache(messageDisplay)
        // Keep the open-chat message pool in sync so the conversation UI can show
        // the bubble at the same time as the in-app sound.
        updateConversationMessagesCache([messageDisplay], for: senderId)
    }
    
    @MainActor
    private func incrementUnreadCount(for senderId: String) {
        guard currentlyOpenConversationSenderId != senderId else { return }
        var counts = conversationUnreadCounts
        counts[senderId, default: 0] += 1
        conversationUnreadCounts = counts
        unreadMessageCount += 1
        syncAppIconBadge()
        refreshUnreadMessageCount()
    }
    
    private func otherUserId(for conversation: MessageDisplay) -> String {
        conversation.senderName == "You" ? conversation.recipientId : conversation.senderId
    }
    
    /// Optimistically update the messages list after sending a message, then refresh from the server.
    @MainActor
    func recordOutgoingMessage(
        to recipientId: String,
        recipientName: String,
        recipientPhotoURL: String?,
        content: String,
        type: MessageType = .text
    ) {
        guard let currentUserId = firebaseAuth.auth.currentUser?.uid else { return }
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }
        
        let message = Message(
            conversationId: UUID(),
            senderId: UUID(),
            senderFirebaseId: currentUserId,
            content: trimmedContent,
            type: type
        )
        let messageDisplay = MessageDisplay(
            message: message,
            senderName: "You",
            recipientName: recipientName,
            senderId: currentUserId,
            recipientId: recipientId,
            senderProfilePhotoURL: currentUser?.profilePhotoURL,
            recipientProfilePhotoURL: recipientPhotoURL
        )
        updateConversationInCache(messageDisplay)
        
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            _ = try? await refreshMessageConversationsCache()
        }
    }
    
    /// Clear the message conversations cache (e.g., on logout)
    func clearMessageConversationsCache() {
        cachedMessageConversations = []
        conversationUnreadCounts = [:]
        lastMessageConversationsUpdate = nil
        cachedConversationStates = [:]
        print("💬 Message conversations cache cleared")
    }
    
    // MARK: - Individual Conversation Messages Cache
    
    struct ConversationCacheSnapshot {
        let messagePool: [MessageDisplay]
        let visibleMessages: [MessageDisplay]
        let hasMoreOlderMessages: Bool
    }
    
    private struct CachedConversationState {
        var messagePool: [MessageDisplay]
        var visibleMessages: [MessageDisplay]
        var hasMoreOlderMessages: Bool
        var updatedAt: Date
    }
    
    /// Returns the in-memory conversation cache for the current app session.
    func getCachedConversationState(for otherUserId: String) -> ConversationCacheSnapshot? {
        guard let state = cachedConversationStates[otherUserId] else {
            print("💬 No cached conversation state for \(otherUserId)")
            return nil
        }
        
        print("💬 Returning cached conversation state for \(otherUserId) (\(state.visibleMessages.count) visible / \(state.messagePool.count) total messages)")
        return ConversationCacheSnapshot(
            messagePool: state.messagePool.deduplicatedConversationMessages(),
            visibleMessages: state.visibleMessages.deduplicatedConversationMessages(),
            hasMoreOlderMessages: state.hasMoreOlderMessages
        )
    }
    
    /// Backward-compatible accessor for callers that only need the message pool.
    func getCachedConversationMessages(for otherUserId: String) -> [MessageDisplay]? {
        getCachedConversationState(for: otherUserId)?.messagePool
    }
    
    /// Persist the full scroll state so reopening/scrolling does not reload already fetched messages.
    func cacheConversationState(
        for otherUserId: String,
        messagePool: [MessageDisplay],
        visibleMessages: [MessageDisplay],
        hasMoreOlderMessages: Bool
    ) {
        let pool = messagePool.deduplicatedConversationMessages()
        let visible = visibleMessages.deduplicatedConversationMessages()
        cachedConversationStates[otherUserId] = CachedConversationState(
            messagePool: pool,
            visibleMessages: visible,
            hasMoreOlderMessages: hasMoreOlderMessages,
            updatedAt: Date()
        )
        print("💬 Cached conversation state for \(otherUserId) (\(visible.count) visible / \(pool.count) total messages)")
    }
    
    /// Cache only the message pool, preserving any existing visible scroll state.
    func cacheConversationMessages(_ messages: [MessageDisplay], for otherUserId: String) {
        let pool = messages.deduplicatedConversationMessages()
        if var existingState = cachedConversationStates[otherUserId] {
            existingState.messagePool = pool
            existingState.updatedAt = Date()
            cachedConversationStates[otherUserId] = existingState
            print("💬 Updated message pool cache for \(otherUserId) (\(pool.count) messages)")
            return
        }
        
        cacheConversationState(
            for: otherUserId,
            messagePool: pool,
            visibleMessages: pool,
            hasMoreOlderMessages: false
        )
    }
    
    /// Update conversation messages cache when new messages arrive
    func updateConversationMessagesCache(_ newMessages: [MessageDisplay], for otherUserId: String) {
        if var existingState = cachedConversationStates[otherUserId] {
            let existingKeys = Set(existingState.messagePool.map(\.deduplicationKey))
            var appendedToVisible = false
            
            for newMessage in newMessages where !existingKeys.contains(newMessage.deduplicationKey) {
                existingState.messagePool.append(newMessage)
                existingState.visibleMessages.append(newMessage)
                appendedToVisible = true
            }
            
            existingState.messagePool = existingState.messagePool.deduplicatedConversationMessages()
            if appendedToVisible {
                existingState.visibleMessages = existingState.visibleMessages.deduplicatedConversationMessages()
            }
            existingState.updatedAt = Date()
            cachedConversationStates[otherUserId] = existingState
            print("💬 Updated conversation cache for \(otherUserId) (total: \(existingState.messagePool.count))")
        } else {
            cacheConversationMessages(newMessages, for: otherUserId)
        }
    }
    
    /// Clear cache for a specific conversation
    func clearConversationMessagesCache(for otherUserId: String) {
        cachedConversationStates.removeValue(forKey: otherUserId)
        print("💬 Cleared conversation cache for \(otherUserId)")
    }
    
    // MARK: - App State Management for Push Notifications
    
    /// Update app state in Firestore so Cloud Functions can check if app is active
    func updateAppStateInFirestore(isActive: Bool) async {
        guard firebaseAuth.auth.currentUser != nil else {
            return
        }
        
        do {
            let now = Date()
            var state: [String: Any] = [
                "appIsActive": isActive,
                "appStateUpdatedAt": now.timeIntervalSince1970,
                "isOnline": isActive,
                "lastSeen": now.timeIntervalSince1970
            ]
            
            // Clear stale in-app state when app is backgrounded or closed
            if !isActive {
                state["openConversationUserId"] = NSNull()
                state["messagesTabActive"] = false
                await MainActor.run {
                    self.isMessagesTabActive = false
                }
            }
            
            try await firebaseAuth.updateUserData(state)
            
            // Also update local user object
            if var user = currentUser {
                user.isOnline = isActive
                user.lastSeen = now
                await MainActor.run {
                    self.currentUser = user
                }
            }
            
            print("📱 Updated app state in Firestore: \(isActive ? "active" : "inactive"), isOnline: \(isActive)")
        } catch {
            print("❌ Failed to update app state in Firestore: \(error)")
        }
    }
    
    // MARK: - Update Online Status
    func updateOnlineStatus(isOnline: Bool) async {
        guard firebaseAuth.auth.currentUser != nil else {
            return
        }
        
        do {
            let now = Date()
            let statusData: [String: Any] = [
                "isOnline": isOnline,
                "lastSeen": now.timeIntervalSince1970
            ]
            try await firebaseAuth.updateUserData(statusData)
            
            // Also update local user object
            if var user = currentUser {
                user.isOnline = isOnline
                user.lastSeen = now
                await MainActor.run {
                    self.currentUser = user
                }
            }
            
            print("🟢 Updated online status: \(isOnline ? "online" : "offline")")
        } catch {
            print("❌ Failed to update online status: \(error)")
        }
    }
}
