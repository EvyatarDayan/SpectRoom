//
//  FirebaseAuthService.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import FirebaseMessaging

class FirebaseAuthService: ObservableObject {
    static let shared = FirebaseAuthService()
    
    @Published var currentUser: SpectRoomUser?
    /// Restored synchronously from Firebase's persisted session so launch UI does not flash logged-out screens.
    @Published var isAuthenticated: Bool
    /// Becomes true after Firebase emits the first auth-state callback.
    @Published var hasResolvedAuthState = false
    
    let auth = Auth.auth()
    private let db = Firestore.firestore()
    private var matchesListener: ListenerRegistration?
    
    private init() {
        // Firebase restores the session from the keychain synchronously when available.
        isAuthenticated = auth.currentUser != nil
        
        // Listen for authentication state changes
        auth.addStateDidChangeListener { [weak self] _, firebaseUser in
            DispatchQueue.main.async {
                self?.isAuthenticated = firebaseUser != nil
                self?.hasResolvedAuthState = true
                if let firebaseUser = firebaseUser {
                    // Load user data from Firestore when Firebase user changes
                    Task {
                        await self?.loadUserData(for: firebaseUser.uid)
                        // Update FCM token when user logs in
                        await self?.updateFCMTokenIfNeeded()
                    }
                } else {
                    self?.currentUser = nil
                }
            }
        }
    }
    
    // Update FCM token when user logs in
    private func updateFCMTokenIfNeeded() async {
        guard let userId = auth.currentUser?.uid else { return }
        
        // Get FCM token from Messaging
        guard let fcmToken = try? await Messaging.messaging().token() else {
            print("⚠️ Could not get FCM token")
            return
        }
        
        print("📱 Updating FCM token for user: \(userId)")
        
        do {
            try await updateUserData(["fcmToken": fcmToken])
            print("✅ FCM token updated in Firestore")
        } catch {
            print("❌ Failed to update FCM token: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Authentication Methods
    
    func signUp(email: String, password: String, name: String, age: Int) async throws {
        let result = try await auth.createUser(withEmail: email, password: password)
        let user = result.user
        
        // Don't create user document automatically - let user complete profile first
        print("✅ User account created: \(user.uid)")
        print("📝 User can now complete their profile through the app")
    }
    
    func signIn(email: String, password: String) async throws {
        _ = try await auth.signIn(withEmail: email, password: password)
    }
    
    func signOut() throws {
        try auth.signOut()
    }
    
    func resetPassword(email: String) async throws {
        try await auth.sendPasswordReset(withEmail: email)
    }
    
    // MARK: - User Data Methods
    
    func fetchUserData() async throws -> [String: Any]? {
        guard let user = auth.currentUser else { return nil }
        
        let document = try await db.collection("users").document(user.uid).getDocument()
        return document.data()
    }
    
    private func loadUserData(for userID: String) async {
        do {
            if let userData = try await fetchUserData() {
                // Load photos and profile photo from Firestore
                let photos = userData["photos"] as? [String] ?? []
                let profilePhotoURL = userData["profilePhotoURL"] as? String
                print("📸 Loaded \(photos.count) photos from Firestore")
                print("🖼️ Loaded profile photo URL: \(profilePhotoURL ?? "nil")")
                
                // Parse location data from Firebase
                let locationData = userData["location"] as? [String: Any] ?? [:]
                let location = Location(
                    displayString: locationData["displayString"] as? String ?? "",
                    city: locationData["city"] as? String ?? "",
                    state: locationData["state"] as? String ?? "",
                    country: locationData["country"] as? String ?? "",
                    latitude: locationData["latitude"] as? Double,
                    longitude: locationData["longitude"] as? Double
                )
                
                let interests = userData["interests"] as? [String] ?? []
                print("🔍 Firebase - Loaded interests from database: \(interests)")
                print("🔍 Firebase - Interests count: \(interests.count)")
                
                // Load gender and preferences
                let gender = userData["gender"] as? String ?? ""
                let interestedIn = userData["interestedIn"] as? [String] ?? []
                let lookingFor = userData["lookingFor"] as? [String] ?? []
                let savedPreferredAgeMin = userData["preferredAgeMin"] as? Int
                let savedPreferredAgeMax = userData["preferredAgeMax"] as? Int
                let userAge = userData["age"] as? Int ?? 18
                
                // Set default preferred age range based on user's age if not saved
                let preferredAgeMin = savedPreferredAgeMin ?? userAge
                let preferredAgeMax = savedPreferredAgeMax ?? min(userAge + 5, 80)
                
                print("🔍 Firebase - Loaded gender: \(gender)")
                print("🔍 Firebase - Loaded interestedIn: \(interestedIn)")
                print("🔍 Firebase - Loaded lookingFor: \(lookingFor)")
                print("🔍 Firebase - Loaded preferredAgeMin: \(preferredAgeMin)")
                print("🔍 Firebase - Loaded preferredAgeMax: \(preferredAgeMax)")
                
                // Load date of birth from database
                let dateOfBirth: Date?
                if let dateOfBirthTimestamp = userData["dateOfBirth"] as? TimeInterval {
                    dateOfBirth = Date(timeIntervalSince1970: dateOfBirthTimestamp)
                    print("🔍 Firebase - Loaded date of birth from database: \(String(describing: dateOfBirth))")
                } else {
                    dateOfBirth = nil
                    print("🔍 Firebase - No date of birth found in database")
                }
                
                let lifestyle = userData["lifestyle"] as? String ?? ""
                let shareLifestyle = userData["shareLifestyle"] as? Bool ?? false
                let bodyType = userData["bodyType"] as? String ?? ""
                let shareBodyType = userData["shareBodyType"] as? Bool ?? false
                let idealFirstDate = userData["idealFirstDate"] as? [String] ?? []
                let shareIdealFirstDate = userData["shareIdealFirstDate"] as? Bool ?? false
                let sensoryPreferences = userData["sensoryPreferences"] as? [String] ?? []
                let shareSensoryPreferences = userData["shareSensoryPreferences"] as? Bool ?? false
                let energyLevel = userData["energyLevel"] as? Int ?? 4
                
                print("🔍 Firebase - Loaded lifestyle: \(lifestyle), shareLifestyle: \(shareLifestyle)")
                print("🔍 Firebase - Loaded bodyType: \(bodyType), shareBodyType: \(shareBodyType)")
                print("🔍 Firebase - Loaded idealFirstDate: \(idealFirstDate), shareIdealFirstDate: \(shareIdealFirstDate)")
                print("🔍 Firebase - Loaded sensoryPreferences: \(sensoryPreferences), shareSensoryPreferences: \(shareSensoryPreferences)")
                print("🔍 Firebase - Loaded energyLevel: \(energyLevel)")
                
                let spectRoomUser = SpectRoomUser(
                    name: userData["name"] as? String ?? "",
                    age: userData["age"] as? Int ?? 0,
                    email: userData["email"] as? String ?? "",
                    bio: userData["bio"] as? String ?? "",
                    interests: interests,
                    location: location,
                    preferences: UserPreferences(), // You might want to parse preferences
                    gender: gender,
                    interestedIn: interestedIn,
                    lookingFor: lookingFor,
                    preferredAgeMin: preferredAgeMin,
                    preferredAgeMax: preferredAgeMax,
                    lifestyle: lifestyle,
                    shareLifestyle: shareLifestyle,
                    bodyType: bodyType,
                    shareBodyType: shareBodyType,
                    idealFirstDate: idealFirstDate,
                    shareIdealFirstDate: shareIdealFirstDate,
                    sensoryPreferences: sensoryPreferences,
                    shareSensoryPreferences: shareSensoryPreferences,
                    energyLevel: energyLevel
                )
                
                // Load isOnline and lastSeen from Firebase
                let isOnline = userData["isOnline"] as? Bool ?? false
                let lastSeenInterval = userData["lastSeen"] as? TimeInterval
                let lastSeen = lastSeenInterval.map { Date(timeIntervalSince1970: $0) } ?? Date()
                
                // Create a mutable copy and set the photos, profile photo, date of birth, and online status
                var userWithPhotos = spectRoomUser
                userWithPhotos.photos = photos
                userWithPhotos.profilePhotoURL = profilePhotoURL
                userWithPhotos.dateOfBirth = dateOfBirth
                userWithPhotos.isOnline = isOnline
                userWithPhotos.lastSeen = lastSeen

                // Fetch blocked users subcollection (non-fatal)
                do {
                    let blockedSnapshot = try await db.collection("users")
                        .document(userID)
                        .collection("blockedUsers")
                        .getDocuments()
                    userWithPhotos.blockedUsers = blockedSnapshot.documents.compactMap { document in
                        let data = document.data()
                        let name = data["name"] as? String ?? "Unknown"
                        let blockedAtInterval = data["blockedAt"] as? TimeInterval
                        let blockedAt = blockedAtInterval.map { Date(timeIntervalSince1970: $0) }
                        return BlockedUser(id: document.documentID, name: name, blockedAt: blockedAt)
                    }
                    
                    await syncBlockedByMirrors(
                        for: userWithPhotos.blockedUsers,
                        blockerName: userWithPhotos.name
                    )
                } catch {
                    userWithPhotos.blockedUsers = []
                    print("⚠️ Failed to load blocked users for \(userID): \(error.localizedDescription)")
                }

                do {
                    let blockedBySnapshot = try await db.collection("users")
                        .document(userID)
                        .collection("blockedBy")
                        .getDocuments()
                    userWithPhotos.blockedByUsers = blockedBySnapshot.documents.compactMap { document in
                        let data = document.data()
                        let name = data["name"] as? String ?? "Unknown"
                        let blockedAtInterval = data["blockedAt"] as? TimeInterval
                        let blockedAt = blockedAtInterval.map { Date(timeIntervalSince1970: $0) }
                        return BlockedUser(id: document.documentID, name: name, blockedAt: blockedAt)
                    }
                } catch {
                    userWithPhotos.blockedByUsers = []
                    print("⚠️ Failed to load blockedBy users for \(userID): \(error.localizedDescription)")
                }
                await MainActor.run {
                    self.currentUser = userWithPhotos
                }
                
                // Preload photos from Firebase Storage to improve user experience
                print("🔄 Preloading photos from Firebase Storage...")
                await syncPhotosFromStorage()
            } else {
                // User document doesn't exist - don't create automatically
                print("⚠️ User document not found for \(userID)")
                print("📝 User needs to complete their profile")
                await MainActor.run {
                    self.currentUser = nil
                }
            }
        } catch {
            print("Load user data error: \(error.localizedDescription)")
            // If there's an error, don't create default document
            await MainActor.run {
                self.currentUser = nil
            }
        }
    }
    
    
    func updateUserData(_ data: [String: Any]) async throws {
        guard let user = auth.currentUser else { return }
        
        // Use setData with merge to create document if it doesn't exist
        try await db.collection("users").document(user.uid).setData(data, merge: true)
    }
    
    // MARK: - Force Refresh User Data
    func forceRefreshUserData() async {
        guard let user = auth.currentUser else { return }
        
        print("🔄 Force refreshing user data from Firebase...")
        await loadUserData(for: user.uid)
    }
    
    // MARK: - Update Database with App State
    func updateDatabaseWithAppState() async {
        guard let user = auth.currentUser else { return }
        
        print("🔄 Updating database with current app state...")
        
        // Get current app state from AppStateManager
        if let currentUser = self.currentUser {
            print("📸 App state has \(currentUser.photos.count) photos: \(currentUser.photos)")
            print("🖼️ App state profile photo: \(currentUser.profilePhotoURL ?? "nil")")
            
            // Update database to match app state exactly (no validation)
            let userData: [String: Any] = [
                "name": currentUser.name,
                "age": currentUser.age,
                "bio": currentUser.bio,
                "interests": currentUser.interests,
                "lifestyle": currentUser.lifestyle,
                "profilePhotoURL": currentUser.profilePhotoURL ?? NSNull(),
                "photos": currentUser.photos
            ]
            
            do {
                try await updateUserData(userData)
                print("✅ Database updated to match app state")
            } catch {
                print("❌ Error updating database with app state: \(error)")
            }
        } else {
            print("⚠️ No current user in app state")
        }
    }
    
    // MARK: - Debug: Test Firebase Connection
    func testFirebaseConnection() async {
        print("🔍 Testing Firebase connection...")
        do {
            let snapshot = try await db.collection("users").getDocuments()
            print("🔍 Firebase connection successful!")
            print("🔍 Total documents in users collection: \(snapshot.documents.count)")
            
            for document in snapshot.documents {
                let data = document.data()
                let name = data["name"] as? String ?? "No name"
                let email = data["email"] as? String ?? "No email"
                print("🔍 Document ID: \(document.documentID), Name: \(name), Email: \(email)")
            }
        } catch {
            print("❌ Firebase connection failed: \(error)")
        }
    }
    
    // MARK: - Fetch Users for Search
    
    struct UsersPage {
        let users: [SpectRoomUser]
        let lastDocumentId: String?
        let hasMore: Bool
    }
    
    func fetchUsersPage(limit: Int = 15, startAfterDocumentId: String? = nil) async throws -> UsersPage {
        let currentUserID = auth.currentUser?.uid
        
        let snapshot: QuerySnapshot
        do {
            var query: Query = db.collection("users")
                .order(by: FieldPath.documentID())
                .limit(to: limit)
            
            if let startAfterDocumentId {
                let previousDoc = try await db.collection("users").document(startAfterDocumentId).getDocument()
                if previousDoc.exists {
                    query = query.start(afterDocument: previousDoc)
                }
            }
            
            snapshot = try await query.getDocuments()
        } catch {
            print("⚠️ Paginated users fetch failed, falling back to full read: \(error.localizedDescription)")
            snapshot = try await db.collection("users").getDocuments()
        }
        
        let users = snapshot.documents.compactMap { document in
            parseSpectRoomUser(documentID: document.documentID, userData: document.data(), excludingUserId: currentUserID)
        }
        
        let lastDocumentId = snapshot.documents.last?.documentID
        let hasMore = snapshot.documents.count == limit
        
        return UsersPage(users: users, lastDocumentId: lastDocumentId, hasMore: hasMore)
    }
    
    func fetchUsers(byIds userIds: [String]) async throws -> [SpectRoomUser] {
        guard !userIds.isEmpty else { return [] }
        
        let currentUserID = auth.currentUser?.uid
        var users: [SpectRoomUser] = []
        
        var startIndex = userIds.startIndex
        while startIndex < userIds.endIndex {
            let endIndex = userIds.index(startIndex, offsetBy: 10, limitedBy: userIds.endIndex) ?? userIds.endIndex
            let chunk = Array(userIds[startIndex..<endIndex])
            let snapshot = try await db.collection("users")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            
            for document in snapshot.documents {
                if let user = parseSpectRoomUser(
                    documentID: document.documentID,
                    userData: document.data(),
                    excludingUserId: currentUserID
                ) {
                    users.append(user)
                }
            }
            
            startIndex = endIndex
        }
        
        return users
    }
    
    func fetchAllUsers() async throws -> [SpectRoomUser] {
        var allUsers: [SpectRoomUser] = []
        var cursor: String?
        var hasMore = true
        
        while hasMore {
            let page = try await fetchUsersPage(limit: 50, startAfterDocumentId: cursor)
            allUsers.append(contentsOf: page.users)
            cursor = page.lastDocumentId
            hasMore = page.hasMore
        }
        
        print("🔍 Fetched \(allUsers.count) users from database")
        return allUsers
    }
    
    private func parseSpectRoomUser(
        documentID: String,
        userData: [String: Any],
        excludingUserId: String?
    ) -> SpectRoomUser? {
        if documentID == excludingUserId {
            return nil
        }
        
        let locationData = userData["location"] as? [String: Any] ?? [:]
        let lifestyle = userData["lifestyle"] as? String ?? ""
        
        let location = Location(
            displayString: locationData["displayString"] as? String ?? "",
            city: locationData["city"] as? String ?? "",
            state: locationData["state"] as? String ?? "",
            country: locationData["country"] as? String ?? "",
            latitude: locationData["latitude"] as? Double,
            longitude: locationData["longitude"] as? Double
        )
        
        let interests = userData["interests"] as? [String] ?? []
        let gender = userData["gender"] as? String ?? ""
        let interestedIn = userData["interestedIn"] as? [String] ?? []
        let lookingFor = userData["lookingFor"] as? [String] ?? []
        let preferredAgeMin = userData["preferredAgeMin"] as? Int ?? 18
        let preferredAgeMax = userData["preferredAgeMax"] as? Int ?? 80
        
        let dateOfBirth: Date?
        if let timestamp = userData["dateOfBirth"] as? TimeInterval {
            dateOfBirth = Date(timeIntervalSince1970: timestamp)
        } else {
            dateOfBirth = nil
        }
        
        let shareLifestyle = userData["shareLifestyle"] as? Bool ?? false
        let bodyType = userData["bodyType"] as? String ?? ""
        let shareBodyType = userData["shareBodyType"] as? Bool ?? false
        let idealFirstDate = userData["idealFirstDate"] as? [String] ?? []
        let shareIdealFirstDate = userData["shareIdealFirstDate"] as? Bool ?? false
        let sensoryPreferences = userData["sensoryPreferences"] as? [String] ?? []
        let shareSensoryPreferences = userData["shareSensoryPreferences"] as? Bool ?? false
        let energyLevel = userData["energyLevel"] as? Int ?? 2
        let isOnline = userData["isOnline"] as? Bool ?? false
        let lastSeenInterval = userData["lastSeen"] as? TimeInterval
        let lastSeen = lastSeenInterval.map { Date(timeIntervalSince1970: $0) } ?? Date()
        
        let user = SpectRoomUser(
            name: userData["name"] as? String ?? "",
            age: userData["age"] as? Int ?? 0,
            email: userData["email"] as? String ?? "",
            bio: userData["bio"] as? String ?? "",
            interests: interests,
            location: location,
            preferences: UserPreferences(),
            gender: gender,
            interestedIn: interestedIn,
            lookingFor: lookingFor,
            preferredAgeMin: preferredAgeMin,
            preferredAgeMax: preferredAgeMax,
            lifestyle: lifestyle,
            shareLifestyle: shareLifestyle,
            bodyType: bodyType,
            shareBodyType: shareBodyType,
            idealFirstDate: idealFirstDate,
            shareIdealFirstDate: shareIdealFirstDate,
            sensoryPreferences: sensoryPreferences,
            shareSensoryPreferences: shareSensoryPreferences,
            energyLevel: energyLevel
        )
        
        var userWithPhotos = user
        userWithPhotos.photos = userData["photos"] as? [String] ?? []
        userWithPhotos.profilePhotoURL = userData["profilePhotoURL"] as? String
        userWithPhotos.dateOfBirth = dateOfBirth
        userWithPhotos.firebaseDocumentId = documentID
        userWithPhotos.isOnline = isOnline
        userWithPhotos.lastSeen = lastSeen
        
        return userWithPhotos
    }
    
    // MARK: - Sync Photos from Storage
    private var isSyncingPhotos = false
    
    func syncPhotosFromStorage() async {
        guard let user = auth.currentUser else { return }
        
        // Prevent multiple simultaneous syncs
        guard !isSyncingPhotos else {
            print("📸 Photo sync already in progress, skipping...")
            return
        }
        
        isSyncingPhotos = true
        print("🔄 Syncing photos from Firebase Storage for user: \(user.uid)...")
        
        do {
            // Get only the current user's gallery photos
            let photoURLs = try await PhotoStorageService.shared.getUserGalleryPhotos(for: user.uid)
            
            print("📸 Found \(photoURLs.count) photos for user \(user.uid): \(photoURLs)")
            
            // Update the current user's photos array
            if var currentUser = self.currentUser {
                currentUser.photos = photoURLs
                await MainActor.run {
                    self.currentUser = currentUser
                }
                
                // Update Firestore with the synced photos
                let userData: [String: Any] = [
                    "photos": photoURLs
                ]
                
                try await updateUserData(userData)
                print("✅ Synced \(photoURLs.count) photos from Storage to Firestore")
            }
            
        } catch {
            print("❌ Error syncing photos from Storage: \(error)")
        }
        
        isSyncingPhotos = false
    }
    
    // MARK: - Photo URL Validation
    private func validatePhotoURLs(_ photoURLs: [String]) async -> [String] {
        var validURLs: [String] = []
        
        for url in photoURLs {
            if await isPhotoURLValid(url) {
                validURLs.append(url)
            } else {
                print("⚠️ Removing invalid photo URL: \(url)")
            }
        }
        
        return validURLs
    }
    
    private func validateProfilePhotoURL(_ profilePhotoURL: String?) async -> String? {
        guard let url = profilePhotoURL else { return nil }
        
        if await isPhotoURLValid(url) {
            return url
        } else {
            print("⚠️ Removing invalid profile photo URL: \(url)")
            return nil
        }
    }
    
    private func isPhotoURLValid(_ url: String) async -> Bool {
        guard let url = URL(string: url) else { return false }
        
        do {
            let storageRef = Storage.storage().reference(forURL: url.absoluteString)
            _ = try await storageRef.getMetadata()
            return true
        } catch {
            print("⚠️ Photo URL is invalid (file doesn't exist): \(url.absoluteString)")
            return false
        }
    }
    
    // MARK: - Helper Methods
    
    func getCurrentUserID() -> String? {
        return auth.currentUser?.uid
    }
    
    func getCurrentUserEmail() -> String? {
        return auth.currentUser?.email
    }
    
    // MARK: - Blocked Users
    
    private func blockedByMirrorData(blockerName: String, blockedAt: Date) -> [String: Any] {
        [
            "name": blockerName,
            "blockedAt": blockedAt.timeIntervalSince1970
        ]
    }
    
    private func syncBlockedByMirror(blockedUserId: String, blockerName: String, blockedAt: Date) async throws {
        guard let currentUserId = auth.currentUser?.uid else { return }
        
        try await db.collection("users")
            .document(blockedUserId)
            .collection("blockedBy")
            .document(currentUserId)
            .setData(blockedByMirrorData(blockerName: blockerName, blockedAt: blockedAt))
    }
    
    private func removeBlockedByMirror(blockedUserId: String) async throws {
        guard let currentUserId = auth.currentUser?.uid else { return }
        
        try await db.collection("users")
            .document(blockedUserId)
            .collection("blockedBy")
            .document(currentUserId)
            .delete()
    }
    
    private func syncBlockedByMirrors(for blockedUsers: [BlockedUser], blockerName: String) async {
        for blockedUser in blockedUsers {
            do {
                try await syncBlockedByMirror(
                    blockedUserId: blockedUser.id,
                    blockerName: blockerName,
                    blockedAt: blockedUser.blockedAt ?? Date()
                )
            } catch {
                print("⚠️ Failed to sync blockedBy mirror for \(blockedUser.id): \(error.localizedDescription)")
            }
        }
    }
    
    func blockUser(userId: String, name: String) async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }
        
        let blockedAt = Date()
        let data: [String: Any] = [
            "name": name,
            "blockedAt": blockedAt.timeIntervalSince1970
        ]
        
        try await db.collection("users")
            .document(currentUserId)
            .collection("blockedUsers")
            .document(userId)
            .setData(data)
        
        let blockerName = await MainActor.run { self.currentUser?.name ?? "Someone" }
        try await syncBlockedByMirror(blockedUserId: userId, blockerName: blockerName, blockedAt: blockedAt)
        
        await MainActor.run {
            if var current = self.currentUser,
               current.blockedUsers.contains(where: { $0.id == userId }) == false {
                current.blockedUsers.append(BlockedUser(id: userId, name: name, blockedAt: blockedAt))
                self.currentUser = current
            }
        }
    }
    
    func unblockUser(userId: String) async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }
        
        try await db.collection("users")
            .document(currentUserId)
            .collection("blockedUsers")
            .document(userId)
            .delete()
        
        try await removeBlockedByMirror(blockedUserId: userId)
        
        await MainActor.run {
            if var current = self.currentUser {
                current.blockedUsers.removeAll { $0.id == userId }
                self.currentUser = current
            }
        }
    }
    
    func isBlockedBy(userId otherUserId: String) async throws -> Bool {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]
            )
        }
        
        let document = try await db.collection("users")
            .document(currentUserId)
            .collection("blockedBy")
            .document(otherUserId)
            .getDocument()
        
        return document.exists
    }
    
    func fetchBlockedByUsers() async throws -> [BlockedUser] {
        guard let currentUserId = auth.currentUser?.uid else { return [] }
        
        let snapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("blockedBy")
            .getDocuments()
        
        return snapshot.documents.compactMap { document in
            let data = document.data()
            let name = data["name"] as? String ?? "Unknown"
            let blockedAtInterval = data["blockedAt"] as? TimeInterval
            let blockedAt = blockedAtInterval.map { Date(timeIntervalSince1970: $0) }
            return BlockedUser(id: document.documentID, name: name, blockedAt: blockedAt)
        }
    }
    
    // MARK: - Matching Functions
    
    func recordSwipe(to targetUserId: String, action: SwipeType) async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💕 Recording swipe: \(action.rawValue) from \(currentUserId) to \(targetUserId)")
        
        let swipeData: [String: Any] = [
            "id": UUID().uuidString,
            "fromUserId": currentUserId,
            "toUserId": targetUserId,
            "action": action.rawValue,
            "createdAt": Date().timeIntervalSince1970
        ]
        
        // Save swipe action to current user's swipes collection
        let swipeRef = db.collection("users").document(currentUserId).collection("swipes").document()
        try await swipeRef.setData(swipeData)
        
        print("✅ Swipe recorded successfully")
    }
    
    // MARK: - Fetch Swipe Filter State
    
    struct SwipeFilterState {
        let likedUserIds: Set<String>
        let passedUserIds: Set<String>
    }
    
    func fetchSwipeFilterState(preferServer: Bool = false) async throws -> SwipeFilterState {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💕 Fetching swipe filter state\(preferServer ? " from server" : "")...")
        
        let swipesRef = db.collection("users").document(currentUserId).collection("swipes")
        let snapshot: QuerySnapshot
        if preferServer {
            snapshot = try await swipesRef.getDocuments(source: .server)
        } else {
            snapshot = try await swipesRef.getDocuments()
        }
        
        var latestSwipeByUser: [String: (action: String, createdAt: TimeInterval)] = [:]
        for document in snapshot.documents {
            let data = document.data()
            guard let toUserId = data["toUserId"] as? String,
                  let action = data["action"] as? String else {
                continue
            }
            
            let createdAt = data["createdAt"] as? TimeInterval ?? 0
            if let existing = latestSwipeByUser[toUserId], existing.createdAt >= createdAt {
                continue
            }
            
            latestSwipeByUser[toUserId] = (action, createdAt)
        }
        
        var likedUserIds = Set<String>()
        var passedUserIds = Set<String>()
        
        for (userId, state) in latestSwipeByUser {
            switch state.action {
            case SwipeType.like.rawValue, SwipeType.superLike.rawValue:
                likedUserIds.insert(userId)
            case SwipeType.pass.rawValue:
                passedUserIds.insert(userId)
            default:
                print("⚠️ Unknown swipe action '\(state.action)' for user \(userId)")
            }
        }
        
        print("💕 Swipe filter state: \(likedUserIds.count) liked, \(passedUserIds.count) passed")
        return SwipeFilterState(likedUserIds: likedUserIds, passedUserIds: passedUserIds)
    }
    
    // MARK: - Fetch Liked Users
    func fetchLikedUserIds(preferServer: Bool = false) async throws -> Set<String> {
        try await fetchSwipeFilterState(preferServer: preferServer).likedUserIds
    }
    
    func fetchPassedUserIds(preferServer: Bool = false) async throws -> Set<String> {
        try await fetchSwipeFilterState(preferServer: preferServer).passedUserIds
    }
    
    private func isPositiveSwipe(_ action: SwipeType?) -> Bool {
        action == .like || action == .superLike
    }
    
    private func latestSwipeAction(from fromUserId: String, to toUserId: String) async throws -> SwipeType? {
        let snapshot = try await db.collection("users")
            .document(fromUserId)
            .collection("swipes")
            .whereField("toUserId", isEqualTo: toUserId)
            .getDocuments()
        
        var latestAction: String?
        var latestCreatedAt: TimeInterval = 0
        
        for document in snapshot.documents {
            let data = document.data()
            guard let action = data["action"] as? String else { continue }
            let createdAt = data["createdAt"] as? TimeInterval ?? 0
            if createdAt >= latestCreatedAt {
                latestCreatedAt = createdAt
                latestAction = action
            }
        }
        
        guard let latestAction, let swipeType = SwipeType(rawValue: latestAction) else {
            return nil
        }
        return swipeType
    }
    
    func hasMutualLike(currentUserId: String, with otherUserId: String) async throws -> Bool {
        async let currentUserActionTask = latestSwipeAction(from: currentUserId, to: otherUserId)
        async let otherUserActionTask = latestSwipeAction(from: otherUserId, to: currentUserId)
        
        let currentUserAction = try await currentUserActionTask
        let otherUserAction = try await otherUserActionTask
        
        let isMutual = isPositiveSwipe(currentUserAction) && isPositiveSwipe(otherUserAction)
        print("💕 Mutual like check \(currentUserId) <-> \(otherUserId): current=\(currentUserAction?.rawValue ?? "none"), other=\(otherUserAction?.rawValue ?? "none"), mutual=\(isMutual)")
        return isMutual
    }
    
    func matchExists(with targetUserId: String) async throws -> Bool {
        guard let currentUserId = auth.currentUser?.uid else { return false }
        let matchId = matchDocumentId(for: currentUserId, and: targetUserId)
        let snapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("matches")
            .document(matchId)
            .getDocument()
        return snapshot.exists
    }
    
    func matchDocumentId(for userId1: String, and userId2: String) -> String {
        let sortedIds = [userId1, userId2].sorted()
        return "\(sortedIds[0])_\(sortedIds[1])"
    }
    
    func checkForMatch(with targetUserId: String) async throws -> Bool {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💕 Checking for match between \(currentUserId) and \(targetUserId)")
        
        guard try await hasMutualLike(currentUserId: currentUserId, with: targetUserId) else {
            print("💕 No mutual like yet between \(currentUserId) and \(targetUserId)")
            return false
        }
        
        let matchId = matchDocumentId(for: currentUserId, and: targetUserId)
        let existingMatch = try await db.collection("users")
            .document(currentUserId)
            .collection("matches")
            .document(matchId)
            .getDocument()
        
        if existingMatch.exists {
            print("💕 Match already exists between \(currentUserId) and \(targetUserId)")
            return true
        }
        
        try await createMatch(with: targetUserId, matchId: matchId)
        return true
    }
    
    func checkIfConversationExists(with userId: String) async throws -> Bool {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Checking if conversation exists with user: \(userId)")
        
        // Check sent messages
        let sentMessagesRef = db.collection("users").document(currentUserId).collection("sentMessages")
        let sentMessagesSnapshot = try await sentMessagesRef.whereField("recipientId", isEqualTo: userId).limit(to: 1).getDocuments()
        
        if !sentMessagesSnapshot.documents.isEmpty {
            print("💬 Found existing sent message to user: \(userId)")
            return true
        }
        
        // Check incoming messages
        let incomingMessagesRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        let incomingMessagesSnapshot = try await incomingMessagesRef.whereField("senderId", isEqualTo: userId).limit(to: 1).getDocuments()
        
        if !incomingMessagesSnapshot.documents.isEmpty {
            print("💬 Found existing incoming message from user: \(userId)")
            return true
        }
        
        print("💬 No existing conversation found with user: \(userId)")
        return false
    }
    
    func checkForAnyMessages() async throws -> (sentCount: Int, incomingCount: Int) {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Checking for any messages in database...")
        
        // Check sent messages
        let sentSnapshot = try await db.collection("users").document(currentUserId).collection("sentMessages").getDocuments()
        let sentCount = sentSnapshot.documents.count
        
        // Check incoming messages
        let incomingSnapshot = try await db.collection("users").document(currentUserId).collection("incomingMessages").getDocuments()
        let incomingCount = incomingSnapshot.documents.count
        
        print("💬 Database check: \(sentCount) sent messages, \(incomingCount) incoming messages")
        return (sentCount: sentCount, incomingCount: incomingCount)
    }
    
    func countUnreadIncomingMessages() async throws -> Int {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Counting unread incoming messages...")
        
        // Fetch incoming messages and filter for unread ones
        let incomingSnapshot = try await db.collection("users").document(currentUserId).collection("incomingMessages").getDocuments()
        
        var unreadCount = 0
        for document in incomingSnapshot.documents {
            let data = document.data()
            let isRead = data["isRead"] as? Bool ?? false
            if !isRead {
                unreadCount += 1
            }
        }
        
        print("💬 Found \(unreadCount) unread incoming messages")
        return unreadCount
    }
    
    func fetchUnreadCountsBySender() async throws -> [String: Int] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let incomingSnapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("incomingMessages")
            .getDocuments()
        
        var unreadCounts: [String: Int] = [:]
        for document in incomingSnapshot.documents {
            let data = document.data()
            let isRead = data["isRead"] as? Bool ?? false
            guard !isRead, let senderId = data["senderId"] as? String else { continue }
            unreadCounts[senderId, default: 0] += 1
        }
        
        return unreadCounts
    }
    
    func countUnreadMessagesFromUser(_ otherUserId: String) async throws -> Int {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Counting unread messages from user: \(otherUserId)")
        
        // Fetch all incoming messages from this user
        let incomingRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        let snapshot = try await incomingRef.whereField("senderId", isEqualTo: otherUserId).getDocuments()
        
        var unreadCount = 0
        for document in snapshot.documents {
            let data = document.data()
            let isRead = data["isRead"] as? Bool ?? false
            if !isRead {
                unreadCount += 1
            }
        }
        
        print("💬 Found \(unreadCount) unread messages from user: \(otherUserId)")
        return unreadCount
    }
    
    func markMessagesAsRead(from otherUserId: String) async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Marking messages as read from user: \(otherUserId)")
        
        // Fetch all incoming messages from this user
        let incomingRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        let snapshot = try await incomingRef.whereField("senderId", isEqualTo: otherUserId).getDocuments()
        
        let batch = db.batch()
        let readAt = Date().timeIntervalSince1970
        
        for document in snapshot.documents {
            let data = document.data()
            let isRead = data["isRead"] as? Bool ?? false
            
            // Only update unread messages
            if !isRead {
                let messageRef = incomingRef.document(document.documentID)
                batch.updateData([
                    "isRead": true,
                    "readAt": readAt
                ], forDocument: messageRef)
            }
        }
        
        try await batch.commit()
        print("💬 Marked messages as read from user: \(otherUserId)")
    }
    
    private func createMatch(with targetUserId: String, matchId: String) async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        guard try await hasMutualLike(currentUserId: currentUserId, with: targetUserId) else {
            print("💕 Skipping match creation - mutual like requirement not met")
            return
        }
        
        print("💕 Creating match between \(currentUserId) and \(targetUserId)")
        
        let sortedIds = [currentUserId, targetUserId].sorted()
        let matchData: [String: Any] = [
            "id": matchId,
            "user1Id": sortedIds[0],
            "user2Id": sortedIds[1],
            "matchedAt": Date().timeIntervalSince1970,
            "isActive": true,
            "lastMessageAt": NSNull(),
            "conversationId": UUID().uuidString
        ]
        
        let currentUserMatchRef = db.collection("users").document(currentUserId).collection("matches").document(matchId)
        let targetUserMatchRef = db.collection("users").document(targetUserId).collection("matches").document(matchId)
        
        let existingForCurrentUser = try await currentUserMatchRef.getDocument()
        let existingForTargetUser = try await targetUserMatchRef.getDocument()
        
        if existingForCurrentUser.exists && existingForTargetUser.exists {
            print("💕 Match document already exists for both users")
            return
        }
        
        if !existingForCurrentUser.exists {
            try await currentUserMatchRef.setData(matchData)
        }
        if !existingForTargetUser.exists {
            try await targetUserMatchRef.setData(matchData)
        }
        
        print("✅ Match created successfully")
    }
    
    func fetchMatches() async throws -> [MatchDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💕 Fetching matches for user: \(currentUserId)")
        
        let matchesRef = db.collection("users").document(currentUserId).collection("matches")
        let snapshot = try await matchesRef.order(by: "matchedAt", descending: true).getDocuments()
        
        print("💕 Found \(snapshot.documents.count) match documents in database")
        
        var matches: [MatchDisplay] = []
        var processedUserIds: Set<String> = []
        let currentUserLocation = try await fetchCurrentUserLocation()
        
        for (index, document) in snapshot.documents.enumerated() {
            let data = document.data()
            guard let user1Id = data["user1Id"] as? String,
                  let user2Id = data["user2Id"] as? String,
                  let matchedAt = data["matchedAt"] as? TimeInterval else { 
                print("💕 Skipping document \(index + 1) - missing required fields")
                continue 
            }
            
            // Determine the other user's ID
            let otherUserId = user1Id == currentUserId ? user2Id : user1Id
            print("💕 Processing match \(index + 1): user1=\(user1Id), user2=\(user2Id), otherUserId=\(otherUserId)")
            
            // Check for duplicate users
            if processedUserIds.contains(otherUserId) {
                print("💕 Skipping duplicate match for user: \(otherUserId)")
                continue
            }
            processedUserIds.insert(otherUserId)
            
            // Fetch the other user's profile information
            do {
                let otherUserProfile = try await fetchUserProfile(
                    for: otherUserId,
                    currentUserLocation: currentUserLocation,
                    forMatches: true
                )
                let matchDisplay = MatchDisplay(
                    id: document.documentID,
                    otherUser: otherUserProfile,
                    matchedAt: Date(timeIntervalSince1970: matchedAt),
                    lastMessageAt: nil // We'll implement this later
                )
                matches.append(matchDisplay)
            } catch {
                print("❌ Error fetching profile for user \(otherUserId): \(error)")
                continue
            }
        }
        
        print("💕 Successfully fetched \(matches.count) matches")
        for (index, match) in matches.enumerated() {
            print("💕 Match \(index + 1): \(match.otherUser.name) (matched at: \(match.matchedAt))")
        }
        return matches
    }
    
    func fetchUserProfile(for userId: String, currentUserLocation: Location? = nil, forMatches: Bool = false) async throws -> ProfileCard {
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let userData = userDoc.data() else {
            throw NSError(domain: "FirebaseAuthService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        let resolvedCurrentUserLocation: Location?
        if let currentUserLocation {
            resolvedCurrentUserLocation = currentUserLocation
        } else {
            resolvedCurrentUserLocation = try await fetchCurrentUserLocation()
        }
        
        let otherUserLocation = Self.parseLocation(from: userData)
        let distanceString: String
        if let resolvedCurrentUserLocation,
           let distanceKm = Self.distance(from: resolvedCurrentUserLocation, to: otherUserLocation) {
            distanceString = Self.formatDistance(distanceKm, forMatches: forMatches)
        } else {
            distanceString = "Matched"
        }
        
        let name = userData["name"] as? String ?? "Unknown"
        let age = userData["age"] as? Int ?? 0
        let bio = userData["bio"] as? String ?? ""
        let interests = userData["interests"] as? [String] ?? []
        let gender = userData["gender"] as? String ?? ""
        let interestedIn = userData["interestedIn"] as? [String] ?? []
        let lookingFor = userData["lookingFor"] as? [String] ?? []
        let photos = userData["photos"] as? [String] ?? []
        let profilePhotoURL = userData["profilePhotoURL"] as? String
        let lifestyle = userData["lifestyle"] as? String ?? ""
        let shareLifestyle = userData["shareLifestyle"] as? Bool ?? false
        let bodyType = userData["bodyType"] as? String ?? ""
        let shareBodyType = userData["shareBodyType"] as? Bool ?? false
        let idealFirstDate = userData["idealFirstDate"] as? [String] ?? []
        let shareIdealFirstDate = userData["shareIdealFirstDate"] as? Bool ?? false
        let sensoryPreferences = userData["sensoryPreferences"] as? [String] ?? []
        let shareSensoryPreferences = userData["shareSensoryPreferences"] as? Bool ?? false
        let energyLevel = userData["energyLevel"] as? Int ?? 2
        let preferredAgeMin = userData["preferredAgeMin"] as? Int ?? age
        let preferredAgeMax = userData["preferredAgeMax"] as? Int ?? min(age + 5, 80)
        let isOnline = userData["isOnline"] as? Bool ?? false
        let lastSeenInterval = userData["lastSeen"] as? TimeInterval
        let lastSeen = lastSeenInterval.map { Date(timeIntervalSince1970: $0) } ?? Date()
        
        let matchPercentage: Int
        let viewer = currentUser ?? AppStateManager.shared.currentUser
        if let viewer {
            matchPercentage = ProfileCard.calculateMatchPercentage(
                interests: interests,
                age: age,
                gender: gender,
                currentUser: viewer
            )
        } else {
            matchPercentage = 0
        }
        
        return ProfileCard(
            userId: userId,
            name: name,
            age: age,
            bio: bio,
            interests: interests,
            distance: distanceString,
            imageURL: profilePhotoURL,
            gender: gender,
            interestedIn: interestedIn,
            lookingFor: lookingFor,
            photos: photos,
            lifestyle: lifestyle,
            shareLifestyle: shareLifestyle,
            bodyType: bodyType,
            shareBodyType: shareBodyType,
            preferredAgeMin: preferredAgeMin,
            preferredAgeMax: preferredAgeMax,
            isOnline: isOnline,
            lastSeen: lastSeen,
            idealFirstDate: idealFirstDate,
            shareIdealFirstDate: shareIdealFirstDate,
            sensoryPreferences: sensoryPreferences,
            shareSensoryPreferences: shareSensoryPreferences,
            energyLevel: energyLevel,
            matchPercentage: matchPercentage
        )
    }
    
    func stopListeningForMatches() {
        matchesListener?.remove()
        matchesListener = nil
        print("💕 Stopped listening for new matches")
    }
    
    func listenForNewMatches(completion: @escaping (MatchDisplay) -> Void) {
        guard let currentUserId = auth.currentUser?.uid else {
            print("❌ User not authenticated for match listening")
            return
        }
        
        stopListeningForMatches()
        print("💕 Starting to listen for new matches for user: \(currentUserId)")
        
        let matchesRef = db.collection("users").document(currentUserId).collection("matches")
        
        matchesListener = matchesRef.addSnapshotListener { snapshot, error in
            if let error = error {
                print("❌ Error listening for matches: \(error)")
                return
            }
            
            guard let snapshot = snapshot else {
                print("❌ No snapshot received for matches")
                return
            }
            
            // Check for new matches (documents that were added)
            for documentChange in snapshot.documentChanges {
                print("💕 Document change type: \(documentChange.type.rawValue)")
                print("💕 Document ID: \(documentChange.document.documentID)")
                
                if documentChange.type == .added {
                    print("💕 New match document added")
                    let data = documentChange.document.data()
                    guard let user1Id = data["user1Id"] as? String,
                          let user2Id = data["user2Id"] as? String,
                          let matchedAt = data["matchedAt"] as? TimeInterval else { 
                        print("❌ Missing required fields in match document")
                        continue 
                    }
                    
                    print("💕 Match between \(user1Id) and \(user2Id)")
                    
                    // Determine the other user's ID
                    let otherUserId = user1Id == currentUserId ? user2Id : user1Id
                    print("💕 Other user ID: \(otherUserId)")
                    
                    // Log match timing for debugging
                    let matchTime = Date(timeIntervalSince1970: matchedAt)
                    let timeDifference = Date().timeIntervalSince(matchTime)
                    print("💕 Match created \(timeDifference) seconds ago")
                    
                    // Only trigger notification for recently created matches (within last 30 seconds)
                    guard timeDifference < 30.0 else {
                        print("💕 Match is older than 30 seconds, skipping notification (likely initial listener setup)")
                        continue
                    }
                    
                    // Fetch the other user's profile information
                    Task {
                        do {
                            let otherUserProfile = try await self.fetchUserProfile(for: otherUserId, forMatches: true)
                            let matchDisplay = MatchDisplay(
                                id: documentChange.document.documentID,
                                otherUser: otherUserProfile,
                                matchedAt: Date(timeIntervalSince1970: matchedAt),
                                lastMessageAt: nil
                            )
                            
                            print("💕 Calling completion with match: \(otherUserProfile.name)")
                            await MainActor.run {
                                completion(matchDisplay)
                            }
                        } catch {
                            print("❌ Error fetching profile for new match: \(error)")
                        }
                    }
                }
            }
        }
    }
    
    func listenForNewMessages(completion: @escaping (String, String, String?, String, String, MessageType, TimeInterval?, Date, Bool) -> Void) {
        guard let currentUserId = auth.currentUser?.uid else {
            print("❌ User not authenticated for message listening")
            return
        }
        
        print("💬 Starting to listen for new messages for user: \(currentUserId)")
        
        // Listen to incoming messages collection
        let incomingMessagesRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        
        incomingMessagesRef.addSnapshotListener { snapshot, error in
            if let error = error {
                print("❌ Error listening for messages: \(error)")
                return
            }
            
            guard let snapshot = snapshot else {
                print("❌ No snapshot received for messages")
                return
            }
            
            print("💬 Snapshot received: \(snapshot.documentChanges.count) document changes, \(snapshot.documents.count) total documents")
            print("💬 Snapshot metadata - hasPendingWrites: \(snapshot.metadata.hasPendingWrites), isFromCache: \(snapshot.metadata.isFromCache)")
            print("💬 All document change types in snapshot:")
            for change in snapshot.documentChanges {
                print("💬   - Type: \(change.type.rawValue), Doc ID: \(change.document.documentID)")
            }
            
            // Skip notifications for initial cache load
            if snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites {
                print("💬 Snapshot is from cache (initial load), skipping notifications for existing messages")
                return
            }
            
            // Check for new messages (documents that were added)
            for documentChange in snapshot.documentChanges {
                print("💬 Processing document change type: \(documentChange.type.rawValue)")
                print("💬 Message document ID: \(documentChange.document.documentID)")
                
                if documentChange.type == .added {
                    print("💬 New message document added")
                    let data = documentChange.document.data()
                    print("💬 Message data fields: \(data.keys)")
                    guard let senderId = data["senderId"] as? String,
                          let createdAt = data["createdAt"] as? TimeInterval else {
                        print("❌ Missing required fields in message document - senderId: \(data["senderId"] ?? "nil"), createdAt: \(data["createdAt"] ?? "nil")")
                        continue
                    }
                    
                    // Only show notification for recent messages (within last 10 seconds)
                    // This ensures we notify for newly received messages, not old ones when listener first starts
                    let messageTime = Date(timeIntervalSince1970: createdAt)
                    let timeDifference = Date().timeIntervalSince(messageTime)
                    guard timeDifference < 10.0 else {
                        print("💬 Message is older than 10 seconds, skipping notification (likely initial listener setup)")
                        continue
                    }
                    
                    let messageDocId = documentChange.document.documentID
                    print("💬 New message from sender: \(senderId), created \(timeDifference) seconds ago, document ID: \(messageDocId)")
                    
                    let content = data["content"] as? String ?? ""
                    let typeString = data["type"] as? String ?? "text"
                    let messageType = MessageType(rawValue: typeString) ?? .text
                    let voiceDuration = data["voiceDuration"] as? TimeInterval
                    
                    DispatchQueue.main.async {
                        completion(
                            senderId,
                            "",
                            nil,
                            messageDocId,
                            content,
                            messageType,
                            voiceDuration,
                            messageTime,
                            false
                        )
                    }
                    
                    // Fetch sender's profile information for notifications
                    Task {
                        do {
                            let senderProfile = try await self.fetchUserProfile(for: senderId)
                            print("💬 Calling completion with sender: \(senderProfile.name)")
                            await MainActor.run {
                                completion(
                                    senderId,
                                    senderProfile.name,
                                    senderProfile.imageURL,
                                    messageDocId,
                                    content,
                                    messageType,
                                    voiceDuration,
                                    messageTime,
                                    true
                                )
                            }
                        } catch {
                            print("❌ Error fetching sender profile for new message: \(error)")
                            await MainActor.run {
                                completion(
                                    senderId,
                                    "Unknown User",
                                    nil,
                                    messageDocId,
                                    content,
                                    messageType,
                                    voiceDuration,
                                    messageTime,
                                    true
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Message Functions (Simplified Structure)
    
    func sendMessage(to recipientId: String, content: String) async throws -> String {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        if try await isBlockedBy(userId: recipientId) {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "You have been blocked by this user"]
            )
        }
        
        print("💬 Sending message from \(currentUserId) to \(recipientId)")
        
        let messageId = UUID().uuidString
        let timestamp = Date().timeIntervalSince1970
        
        // Create message data
        let messageData: [String: Any] = [
            "id": messageId,
            "senderId": currentUserId,
            "recipientId": recipientId,
            "content": content,
            "type": "text",
            "createdAt": timestamp,
            "isRead": false,
            "readAt": NSNull()
        ]
        
        // Save to sender's "sent" collection
        let senderRef = db.collection("users").document(currentUserId).collection("sentMessages").document(messageId)
        try await senderRef.setData(messageData)
        
        // Save to recipient's "incoming" collection
        let recipientRef = db.collection("users").document(recipientId).collection("incomingMessages").document(messageId)
        try await recipientRef.setData(messageData)
        
        print("✅ Message sent successfully with ID: \(messageId)")
        return messageId
    }
    
    func sendImageMessage(to recipientId: String, imageURL: String) async throws -> String {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        if try await isBlockedBy(userId: recipientId) {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "You have been blocked by this user"]
            )
        }
        
        print("💬 Sending image message from \(currentUserId) to \(recipientId)")
        
        let messageId = UUID().uuidString
        let timestamp = Date().timeIntervalSince1970
        
        // Create message data with image type
        let messageData: [String: Any] = [
            "id": messageId,
            "senderId": currentUserId,
            "recipientId": recipientId,
            "content": imageURL, // Store image URL in content field
            "type": "image",
            "createdAt": timestamp,
            "isRead": false,
            "readAt": NSNull()
        ]
        
        // Save to sender's "sent" collection
        let senderRef = db.collection("users").document(currentUserId).collection("sentMessages").document(messageId)
        try await senderRef.setData(messageData)
        
        // Save to recipient's "incoming" collection
        let recipientRef = db.collection("users").document(recipientId).collection("incomingMessages").document(messageId)
        try await recipientRef.setData(messageData)
        
        print("✅ Image message sent successfully with ID: \(messageId)")
        return messageId
    }
    
    func sendVoiceMessage(to recipientId: String, audioURL: String, duration: TimeInterval) async throws -> String {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        if try await isBlockedBy(userId: recipientId) {
            throw NSError(
                domain: "FirebaseAuthService",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "You have been blocked by this user"]
            )
        }
        
        print("🎙️ Sending voice message from \(currentUserId) to \(recipientId)")
        
        let messageId = UUID().uuidString
        let timestamp = Date().timeIntervalSince1970
        
        let messageData: [String: Any] = [
            "id": messageId,
            "senderId": currentUserId,
            "recipientId": recipientId,
            "content": audioURL,
            "type": "voice",
            "voiceDuration": duration,
            "createdAt": timestamp,
            "isRead": false,
            "readAt": NSNull()
        ]
        
        let senderRef = db.collection("users").document(currentUserId).collection("sentMessages").document(messageId)
        try await senderRef.setData(messageData)
        
        let recipientRef = db.collection("users").document(recipientId).collection("incomingMessages").document(messageId)
        try await recipientRef.setData(messageData)
        
        print("✅ Voice message sent successfully with ID: \(messageId)")
        return messageId
    }
    
    func fetchSentMessages() async throws -> [MessageDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching sent messages for user: \(currentUserId)")
        
        let sentRef = db.collection("users").document(currentUserId).collection("sentMessages")
        let snapshot = try await sentRef.order(by: "createdAt", descending: true).getDocuments()
        
        var messages: [MessageDisplay] = []
        
        for document in snapshot.documents {
            let data = document.data()
            print("💬 fetchSentMessages: Processing document: \(document.documentID)")
            print("💬 fetchSentMessages: Document data: \(data)")
            
            guard let content = data["content"] as? String,
                  let senderId = data["senderId"] as? String,
                  let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { 
                print("❌ fetchSentMessages: Missing required fields in document")
                continue 
            }
            
            print("💬 fetchSentMessages: Message content: \(content)")
            print("💬 fetchSentMessages: Sender ID: \(senderId)")
            print("💬 fetchSentMessages: Recipient ID: \(recipientId)")
            
            // Create a UUID from the Firebase UID string
            // Firebase UIDs are not valid UUID strings, so we'll create a deterministic UUID
            let senderUUID = UUID(uuidString: senderId) ?? UUID()
            
            let message = Message(
                conversationId: UUID(), // Not used in this structure
                senderId: senderUUID,
                senderFirebaseId: senderId,
                content: content,
                type: MessageType(rawValue: (data["type"] as? String) ?? "text") ?? .text,
                voiceDuration: data["voiceDuration"] as? TimeInterval
            )
            
            // Fetch recipient name and profile photo
            let recipientName = try await fetchRecipientName(for: recipientId)
            let recipientProfilePhotoURL = try await fetchUserProfilePhotoURL(for: recipientId)
            
            let messageDisplay = MessageDisplay(
                message: message,
                senderName: "You", // Current user is the sender
                recipientName: recipientName,
                senderId: senderId,
                recipientId: recipientId,
                senderProfilePhotoURL: nil, // Current user's profile photo not needed for sent messages
                recipientProfilePhotoURL: recipientProfilePhotoURL
            )
            
            messages.append(messageDisplay)
        }
        
        print("💬 Fetched \(messages.count) sent messages")
        return messages
    }
    
    func fetchIncomingMessages() async throws -> [MessageDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching incoming messages for user: \(currentUserId)")
        
        let incomingRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        let snapshot = try await incomingRef.order(by: "createdAt", descending: true).getDocuments()
        
        var messages: [MessageDisplay] = []
        
        for document in snapshot.documents {
            let data = document.data()
            guard let content = data["content"] as? String,
                  let senderId = data["senderId"] as? String,
                  let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { continue }
            
            // Create a UUID from the Firebase UID string
            // Firebase UIDs are not valid UUID strings, so we'll create a deterministic UUID
            let senderUUID = UUID(uuidString: senderId) ?? UUID()
            
            let messageTypeString = data["type"] as? String ?? "text"
            let messageType = MessageType(rawValue: messageTypeString) ?? .text
            let voiceDuration = data["voiceDuration"] as? TimeInterval
            
            let message = Message(
                conversationId: UUID(), // Not used in this structure
                senderId: senderUUID,
                senderFirebaseId: senderId,
                content: content,
                createdAt: Date(timeIntervalSince1970: createdAt),
                type: messageType,
                voiceDuration: voiceDuration
            )
            
            // Fetch sender name and profile photo
            let senderName = try await fetchSenderName(for: senderId)
            let senderProfilePhotoURL = try await fetchUserProfilePhotoURL(for: senderId)
            
            let messageDisplay = MessageDisplay(
                message: message,
                senderName: senderName,
                recipientName: "You", // Current user is the recipient
                senderId: senderId,
                recipientId: recipientId,
                senderProfilePhotoURL: senderProfilePhotoURL,
                recipientProfilePhotoURL: nil // Current user's profile photo not needed for incoming messages
            )
            
            messages.append(messageDisplay)
        }
        
        print("💬 Fetched \(messages.count) incoming messages")
        return messages
    }
    
    func fetchSenderName(for senderId: String) async throws -> String {
        let userDoc = try await db.collection("users").document(senderId).getDocument()
        guard let userData = userDoc.data(),
              let name = userData["name"] as? String else {
            return "Unknown User"
        }
        return name
    }
    
    func fetchRecipientName(for recipientId: String) async throws -> String {
        print("💬 fetchRecipientName: Looking up recipient ID: \(recipientId)")
        
        let userDoc = try await db.collection("users").document(recipientId).getDocument()
        
        if !userDoc.exists {
            print("❌ fetchRecipientName: User document does not exist for ID: \(recipientId)")
            return "Unknown User"
        }
        
        guard let userData = userDoc.data() else {
            print("❌ fetchRecipientName: No data found for user ID: \(recipientId)")
            return "Unknown User"
        }
        
        guard let name = userData["name"] as? String else {
            print("❌ fetchRecipientName: No name field found for user ID: \(recipientId)")
            print("💬 fetchRecipientName: User data: \(userData)")
            return "Unknown User"
        }
        
        print("✅ fetchRecipientName: Found name '\(name)' for user ID: \(recipientId)")
        return name
    }
    
    func fetchUserProfilePhotoURL(for userId: String) async throws -> String? {
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let userData = userDoc.data() else {
            return nil
        }
        return userData["profilePhotoURL"] as? String
    }
    
    /// Fetch the latest message content from a sender (for notifications)
    func fetchLatestMessageContent(from senderId: String) async throws -> String? {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching latest message content from sender: \(senderId)")
        
        // Fetch incoming messages from this sender
        let incomingRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        let snapshot = try await incomingRef.whereField("senderId", isEqualTo: senderId).order(by: "createdAt", descending: true).limit(to: 1).getDocuments()
        
        if let document = snapshot.documents.first {
            let data = document.data()
            guard let content = data["content"] as? String else {
                print("❌ Missing content field in message document")
                return nil
            }
            
            let messageTypeString = data["type"] as? String ?? "text"
            let messageType = MessageType(rawValue: messageTypeString) ?? .text
            
            // If it's an image message, return a placeholder text
            if messageType == .image {
                return "messages.preview.photo".localized
            }
            
            if messageType == .voice {
                return "messages.preview.voice".localized
            }
            
            return content
        }
        
        return nil
    }
    
    func fetchLatestMessageFromSender(senderId: String) async throws -> MessageDisplay? {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching latest message from sender: \(senderId)")
        
        // Fetch incoming messages from this sender
        let incomingRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        let snapshot = try await incomingRef.whereField("senderId", isEqualTo: senderId).order(by: "createdAt", descending: true).limit(to: 1).getDocuments()
        
        if let document = snapshot.documents.first {
            let data = document.data()
            guard let content = data["content"] as? String,
                  let senderId = data["senderId"] as? String,
                  let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else {
                print("❌ Missing required fields in message document")
                return nil
            }
            
            let messageTypeString = data["type"] as? String ?? "text"
            let messageType = MessageType(rawValue: messageTypeString) ?? .text
            let voiceDuration = data["voiceDuration"] as? TimeInterval
            
            let message = Message(
                conversationId: UUID(),
                senderId: UUID(uuidString: senderId) ?? UUID(),
                senderFirebaseId: senderId,
                content: content,
                createdAt: Date(timeIntervalSince1970: createdAt),
                type: messageType,
                voiceDuration: voiceDuration
            )
            
            // Fetch sender name and photo
            let senderName = try await fetchSenderName(for: senderId)
            let senderProfilePhotoURL = try await fetchUserProfilePhotoURL(for: senderId)
            
            let messageDisplay = MessageDisplay(
                message: message,
                senderName: senderName,
                recipientName: "You",
                senderId: senderId,
                recipientId: recipientId,
                senderProfilePhotoURL: senderProfilePhotoURL,
                recipientProfilePhotoURL: nil
            )
            
            print("💬 Created MessageDisplay for sender: \(senderName)")
            return messageDisplay
        }
        
        print("💬 No message found from sender: \(senderId)")
        return nil
    }
    
    // Fetch a page of conversation messages (newest first, returned oldest-first for display)
    func fetchConversationMessagesPage(
        with otherUserId: String,
        limit: Int = 10,
        before: Date? = nil
    ) async throws -> ConversationMessagesPage {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching conversation page (limit: \(limit), before: \(before?.formattedTimestamp() ?? "nil")) with \(otherUserId)")
        
        async let otherUserNameTask = fetchSenderName(for: otherUserId)
        async let otherUserPhotoTask = fetchUserProfilePhotoURL(for: otherUserId)
        async let currentUserPhotoTask = fetchUserProfilePhotoURL(for: currentUserId)
        async let sentDocsTask = fetchFilteredMessageDocuments(
            collection: "sentMessages",
            filterField: "recipientId",
            filterValue: otherUserId,
            userId: currentUserId,
            limit: limit,
            before: before
        )
        async let incomingDocsTask = fetchFilteredMessageDocuments(
            collection: "incomingMessages",
            filterField: "senderId",
            filterValue: otherUserId,
            userId: currentUserId,
            limit: limit,
            before: before
        )
        
        let otherUserName = try await otherUserNameTask
        let otherUserPhoto = try await otherUserPhotoTask
        let currentUserPhoto = try await currentUserPhotoTask
        let sentDocs = try await sentDocsTask
        let incomingDocs = try await incomingDocsTask
        
        var merged: [(createdAt: TimeInterval, display: MessageDisplay)] = []
        
        for document in sentDocs {
            if let display = messageDisplay(
                from: document.data(),
                currentUserId: currentUserId,
                otherUserId: otherUserId,
                otherUserName: otherUserName,
                otherUserPhotoURL: otherUserPhoto,
                currentUserPhotoURL: currentUserPhoto,
                isOutgoing: true
            ) {
                merged.append((display.createdAt.timeIntervalSince1970, display))
            }
        }
        
        for document in incomingDocs {
            if let display = messageDisplay(
                from: document.data(),
                currentUserId: currentUserId,
                otherUserId: otherUserId,
                otherUserName: otherUserName,
                otherUserPhotoURL: otherUserPhoto,
                currentUserPhotoURL: currentUserPhoto,
                isOutgoing: false
            ) {
                merged.append((display.createdAt.timeIntervalSince1970, display))
            }
        }
        
        merged.sort { $0.createdAt > $1.createdAt }
        let pageMessages = Array(merged.prefix(limit)).map(\.display).sorted { $0.createdAt < $1.createdAt }
        let hasMoreOlder = merged.count > limit || sentDocs.count == limit || incomingDocs.count == limit
        
        print("💬 Fetched conversation page: \(pageMessages.count) messages, hasMoreOlder: \(hasMoreOlder)")
        return ConversationMessagesPage(messages: pageMessages, hasMoreOlder: hasMoreOlder)
    }
    
    /// Fetch only messages newer than a timestamp (for lightweight refresh)
    func fetchConversationMessagesNewerThan(with otherUserId: String, since: Date) async throws -> [MessageDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let sinceTimestamp = since.timeIntervalSince1970
        
        async let otherUserNameTask = fetchSenderName(for: otherUserId)
        async let otherUserPhotoTask = fetchUserProfilePhotoURL(for: otherUserId)
        async let currentUserPhotoTask = fetchUserProfilePhotoURL(for: currentUserId)
        async let sentDocsTask = fetchFilteredMessageDocuments(
            collection: "sentMessages",
            filterField: "recipientId",
            filterValue: otherUserId,
            userId: currentUserId,
            after: sinceTimestamp
        )
        async let incomingDocsTask = fetchFilteredMessageDocuments(
            collection: "incomingMessages",
            filterField: "senderId",
            filterValue: otherUserId,
            userId: currentUserId,
            after: sinceTimestamp
        )
        
        let otherUserName = try await otherUserNameTask
        let otherUserPhoto = try await otherUserPhotoTask
        let currentUserPhoto = try await currentUserPhotoTask
        let sentDocs = try await sentDocsTask
        let incomingDocs = try await incomingDocsTask
        
        var messages: [MessageDisplay] = []
        
        for document in sentDocs {
            if let display = messageDisplay(
                from: document.data(),
                currentUserId: currentUserId,
                otherUserId: otherUserId,
                otherUserName: otherUserName,
                otherUserPhotoURL: otherUserPhoto,
                currentUserPhotoURL: currentUserPhoto,
                isOutgoing: true
            ) {
                messages.append(display)
            }
        }
        
        for document in incomingDocs {
            if let display = messageDisplay(
                from: document.data(),
                currentUserId: currentUserId,
                otherUserId: otherUserId,
                otherUserName: otherUserName,
                otherUserPhotoURL: otherUserPhoto,
                currentUserPhotoURL: currentUserPhoto,
                isOutgoing: false
            ) {
                messages.append(display)
            }
        }
        
        return messages.sorted { $0.createdAt < $1.createdAt }
    }
    
    // Fetch all messages between current user and another user (legacy — prefer paginated API)
    func fetchConversationMessages(with otherUserId: String) async throws -> [MessageDisplay] {
        let page = try await fetchConversationMessagesPage(with: otherUserId, limit: 10)
        return page.messages
    }
    
    // Fetch only message content without profile photos (for auto-refresh)
    func fetchConversationMessagesContentOnly(with otherUserId: String) async throws -> [Message] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching recent conversation message content only with \(otherUserId)")
        
        async let sentDocsTask = fetchFilteredMessageDocuments(
            collection: "sentMessages",
            filterField: "recipientId",
            filterValue: otherUserId,
            userId: currentUserId,
            limit: 20
        )
        async let incomingDocsTask = fetchFilteredMessageDocuments(
            collection: "incomingMessages",
            filterField: "senderId",
            filterValue: otherUserId,
            userId: currentUserId,
            limit: 20
        )
        
        let sentDocs = try await sentDocsTask
        let incomingDocs = try await incomingDocsTask
        
        var allMessages: [Message] = []
        
        for document in sentDocs + incomingDocs {
            if let message = messageFromDocument(document.data()) {
                allMessages.append(message)
            }
        }
        
        return allMessages.sorted { $0.createdAt < $1.createdAt }
    }
    
    // Get latest message from each user (for conversation list)
    func fetchLatestMessagesFromEachUser() async throws -> [MessageDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching latest messages from each user...")
        
        let recentLimit = 100
        
        async let sentSnapshotTask = db.collection("users")
            .document(currentUserId)
            .collection("sentMessages")
            .order(by: "createdAt", descending: true)
            .limit(to: recentLimit)
            .getDocuments()
        async let incomingSnapshotTask = db.collection("users")
            .document(currentUserId)
            .collection("incomingMessages")
            .order(by: "createdAt", descending: true)
            .limit(to: recentLimit)
            .getDocuments()
        
        let sentSnapshot = try await sentSnapshotTask
        let incomingSnapshot = try await incomingSnapshotTask
        
        struct LatestCandidate {
            let otherUserId: String
            let data: [String: Any]
            let createdAt: TimeInterval
            let isOutgoing: Bool
        }
        
        var latestByUser: [String: LatestCandidate] = [:]
        
        for document in sentSnapshot.documents {
            let data = document.data()
            guard let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { continue }
            
            if let existing = latestByUser[recipientId], existing.createdAt >= createdAt {
                continue
            }
            
            latestByUser[recipientId] = LatestCandidate(
                otherUserId: recipientId,
                data: data,
                createdAt: createdAt,
                isOutgoing: true
            )
        }
        
        for document in incomingSnapshot.documents {
            let data = document.data()
            guard let senderId = data["senderId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { continue }
            
            if let existing = latestByUser[senderId], existing.createdAt >= createdAt {
                continue
            }
            
            latestByUser[senderId] = LatestCandidate(
                otherUserId: senderId,
                data: data,
                createdAt: createdAt,
                isOutgoing: false
            )
        }
        
        let profiles = await fetchUserSummaries(for: Array(latestByUser.keys))
        
        var latestMessages: [MessageDisplay] = []
        for candidate in latestByUser.values {
            let summary = profiles[candidate.otherUserId]
            let otherName = summary?.name ?? "Unknown User"
            let otherPhoto = summary?.photoURL
            
            if let display = messageDisplay(
                from: candidate.data,
                currentUserId: currentUserId,
                otherUserId: candidate.otherUserId,
                otherUserName: otherName,
                otherUserPhotoURL: otherPhoto,
                currentUserPhotoURL: nil,
                isOutgoing: candidate.isOutgoing
            ) {
                latestMessages.append(display)
            }
        }
        
        latestMessages.sort { $0.createdAt > $1.createdAt }
        
        print("💬 Final result: \(latestMessages.count) unique conversations")
        return latestMessages
    }
    
    func fetchLatestMessageForConversation(with otherUserId: String) async throws -> MessageDisplay? {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let sentSnapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("sentMessages")
            .whereField("recipientId", isEqualTo: otherUserId)
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .getDocuments()
        
        let incomingSnapshot = try await db.collection("users")
            .document(currentUserId)
            .collection("incomingMessages")
            .whereField("senderId", isEqualTo: otherUserId)
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .getDocuments()
        
        var sentMessage: MessageDisplay?
        if let document = sentSnapshot.documents.first,
           let candidate = try await conversationCandidate(
            from: document.data(),
            currentUserId: currentUserId,
            isOutgoing: true
           ) {
            sentMessage = candidate.message
        }
        
        var incomingMessage: MessageDisplay?
        if let document = incomingSnapshot.documents.first,
           let candidate = try await conversationCandidate(
            from: document.data(),
            currentUserId: currentUserId,
            isOutgoing: false
           ) {
            incomingMessage = candidate.message
        }
        
        switch (sentMessage, incomingMessage) {
        case (nil, nil):
            return nil
        case (let sent?, nil):
            return sent
        case (nil, let incoming?):
            return incoming
        case (let sent?, let incoming?):
            return sent.createdAt >= incoming.createdAt ? sent : incoming
        }
    }
    
    private func fetchFilteredMessageDocuments(
        collection: String,
        filterField: String,
        filterValue: String,
        userId: String,
        limit: Int? = nil,
        before: Date? = nil,
        after: TimeInterval? = nil
    ) async throws -> [QueryDocumentSnapshot] {
        var query: Query = db.collection("users")
            .document(userId)
            .collection(collection)
            .whereField(filterField, isEqualTo: filterValue)
        
        if let after {
            query = query
                .whereField("createdAt", isGreaterThan: after)
                .order(by: "createdAt", descending: false)
        } else if let before {
            query = query
                .whereField("createdAt", isLessThan: before.timeIntervalSince1970)
                .order(by: "createdAt", descending: true)
        } else {
            query = query.order(by: "createdAt", descending: true)
        }
        
        if let limit {
            query = query.limit(to: limit)
        }
        
        let snapshot = try await query.getDocuments()
        return snapshot.documents
    }
    
    private func messageFromDocument(_ data: [String: Any]) -> Message? {
        guard let content = data["content"] as? String,
              let senderId = data["senderId"] as? String,
              let createdAt = data["createdAt"] as? TimeInterval else {
            return nil
        }
        
        let messageTypeString = data["type"] as? String ?? "text"
        let messageType = MessageType(rawValue: messageTypeString) ?? .text
        let voiceDuration = data["voiceDuration"] as? TimeInterval
        
        return Message(
            conversationId: UUID(),
            senderId: UUID(uuidString: senderId) ?? UUID(),
            senderFirebaseId: senderId,
            content: content,
            createdAt: Date(timeIntervalSince1970: createdAt),
            type: messageType,
            voiceDuration: voiceDuration
        )
    }
    
    private func messageDisplay(
        from data: [String: Any],
        currentUserId: String,
        otherUserId: String,
        otherUserName: String,
        otherUserPhotoURL: String?,
        currentUserPhotoURL: String?,
        isOutgoing: Bool
    ) -> MessageDisplay? {
        guard let message = messageFromDocument(data) else { return nil }
        
        if isOutgoing {
            return MessageDisplay(
                message: message,
                senderName: "You",
                recipientName: otherUserName,
                senderId: currentUserId,
                recipientId: otherUserId,
                senderProfilePhotoURL: currentUserPhotoURL,
                recipientProfilePhotoURL: otherUserPhotoURL
            )
        }
        
        return MessageDisplay(
            message: message,
            senderName: otherUserName,
            recipientName: "You",
            senderId: otherUserId,
            recipientId: currentUserId,
            senderProfilePhotoURL: otherUserPhotoURL,
            recipientProfilePhotoURL: currentUserPhotoURL
        )
    }
    
    private struct UserSummary {
        let name: String
        let photoURL: String?
    }
    
    private func fetchUserSummaries(for userIds: [String]) async -> [String: UserSummary] {
        guard !userIds.isEmpty else { return [:] }
        
        var summaries: [String: UserSummary] = [:]
        
        await withTaskGroup(of: (String, UserSummary?).self) { group in
            for userId in userIds {
                group.addTask {
                    do {
                        let name = try await self.fetchSenderName(for: userId)
                        let photoURL = try await self.fetchUserProfilePhotoURL(for: userId)
                        return (userId, UserSummary(name: name, photoURL: photoURL))
                    } catch {
                        return (userId, nil)
                    }
                }
            }
            
            for await (userId, summary) in group {
                if let summary {
                    summaries[userId] = summary
                }
            }
        }
        
        return summaries
    }
    
    private func conversationCandidate(
        from data: [String: Any],
        currentUserId: String,
        isOutgoing: Bool
    ) async throws -> (otherUserId: String, message: MessageDisplay, createdAt: TimeInterval)? {
        guard let content = data["content"] as? String,
              let senderId = data["senderId"] as? String,
              let recipientId = data["recipientId"] as? String,
              let createdAt = data["createdAt"] as? TimeInterval else {
            return nil
        }
        
        let messageTypeString = data["type"] as? String ?? "text"
        let messageType = MessageType(rawValue: messageTypeString) ?? .text
        let voiceDuration = data["voiceDuration"] as? TimeInterval
        
        let message = Message(
            conversationId: UUID(),
            senderId: UUID(uuidString: senderId) ?? UUID(),
            senderFirebaseId: senderId,
            content: content,
            createdAt: Date(timeIntervalSince1970: createdAt),
            type: messageType,
            voiceDuration: voiceDuration
        )
        
        if isOutgoing {
            let recipientName = try await fetchRecipientName(for: recipientId)
            let recipientProfilePhotoURL = try await fetchUserProfilePhotoURL(for: recipientId)
            let messageDisplay = MessageDisplay(
                message: message,
                senderName: "You",
                recipientName: recipientName,
                senderId: senderId,
                recipientId: recipientId,
                senderProfilePhotoURL: nil,
                recipientProfilePhotoURL: recipientProfilePhotoURL
            )
            return (recipientId, messageDisplay, createdAt)
        } else {
            let senderName = try await fetchSenderName(for: senderId)
            let senderProfilePhotoURL = try await fetchUserProfilePhotoURL(for: senderId)
            let messageDisplay = MessageDisplay(
                message: message,
                senderName: senderName,
                recipientName: "You",
                senderId: senderId,
                recipientId: recipientId,
                senderProfilePhotoURL: senderProfilePhotoURL,
                recipientProfilePhotoURL: nil
            )
            return (senderId, messageDisplay, createdAt)
        }
    }
    
    // Get latest sent message to each user
    func fetchLatestSentMessages() async throws -> [MessageDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching latest sent messages...")
        
        var recipientLatestMessages: [String: MessageDisplay] = [:]
        
        // Fetch sent messages
        let sentSnapshot = try await db.collection("users").document(currentUserId).collection("sentMessages").getDocuments()
        for document in sentSnapshot.documents {
            let data = document.data()
            guard let content = data["content"] as? String,
                  let senderId = data["senderId"] as? String,
                  let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { continue }
            
            let messageTypeString = data["type"] as? String ?? "text"
            let messageType = MessageType(rawValue: messageTypeString) ?? .text
            let voiceDuration = data["voiceDuration"] as? TimeInterval
            
            let message = Message(
                conversationId: UUID(),
                senderId: UUID(uuidString: senderId) ?? UUID(),
                senderFirebaseId: senderId,
                content: content,
                createdAt: Date(timeIntervalSince1970: createdAt),
                type: messageType,
                voiceDuration: voiceDuration
            )
            
            let recipientName = try await fetchRecipientName(for: recipientId)
            let recipientProfilePhotoURL = try await fetchUserProfilePhotoURL(for: recipientId)
            let messageDisplay = MessageDisplay(
                message: message,
                senderName: "You",
                recipientName: recipientName,
                senderId: senderId,
                recipientId: recipientId,
                senderProfilePhotoURL: nil,
                recipientProfilePhotoURL: recipientProfilePhotoURL
            )
            
            // Keep only the latest message for each recipient
            if let existingMessage = recipientLatestMessages[recipientId] {
                if messageDisplay.createdAt > existingMessage.createdAt {
                    recipientLatestMessages[recipientId] = messageDisplay
                }
            } else {
                recipientLatestMessages[recipientId] = messageDisplay
            }
        }
        
        // Convert to array and sort by latest message time
        let latestMessages = Array(recipientLatestMessages.values)
            .sorted { $0.createdAt > $1.createdAt }
        
        print("💬 Fetched \(latestMessages.count) latest sent messages")
        return latestMessages
    }
    
    // Get latest incoming message from each user
    func fetchLatestIncomingMessages() async throws -> [MessageDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching latest incoming messages...")
        
        var senderLatestMessages: [String: MessageDisplay] = [:]
        
        // Fetch incoming messages
        let incomingSnapshot = try await db.collection("users").document(currentUserId).collection("incomingMessages").getDocuments()
        for document in incomingSnapshot.documents {
            let data = document.data()
            guard let content = data["content"] as? String,
                  let senderId = data["senderId"] as? String,
                  let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { continue }
            
            let messageTypeString = data["type"] as? String ?? "text"
            let messageType = MessageType(rawValue: messageTypeString) ?? .text
            let voiceDuration = data["voiceDuration"] as? TimeInterval
            
            let message = Message(
                conversationId: UUID(),
                senderId: UUID(uuidString: senderId) ?? UUID(),
                senderFirebaseId: senderId,
                content: content,
                createdAt: Date(timeIntervalSince1970: createdAt),
                type: messageType,
                voiceDuration: voiceDuration
            )
            
            let senderName = try await fetchSenderName(for: senderId)
            let senderProfilePhotoURL = try await fetchUserProfilePhotoURL(for: senderId)
            let messageDisplay = MessageDisplay(
                message: message,
                senderName: senderName,
                recipientName: "You",
                senderId: senderId,
                recipientId: recipientId,
                senderProfilePhotoURL: senderProfilePhotoURL,
                recipientProfilePhotoURL: nil
            )
            
            // Keep only the latest message for each sender
            if let existingMessage = senderLatestMessages[senderId] {
                if messageDisplay.createdAt > existingMessage.createdAt {
                    senderLatestMessages[senderId] = messageDisplay
                }
            } else {
                senderLatestMessages[senderId] = messageDisplay
            }
        }
        
        // Convert to array and sort by latest message time
        let latestMessages = Array(senderLatestMessages.values)
            .sorted { $0.createdAt > $1.createdAt }
        
        print("💬 Fetched \(latestMessages.count) latest incoming messages")
        return latestMessages
    }
    
    // MARK: - Delete All User Data
    
    /// Delete all swipes for the current user
    func deleteAllSwipes() async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("🗑️ Deleting all swipes for user: \(currentUserId)")
        
        let swipesRef = db.collection("users").document(currentUserId).collection("swipes")
        let snapshot = try await swipesRef.getDocuments()
        
        let batch = db.batch()
        for document in snapshot.documents {
            batch.deleteDocument(document.reference)
        }
        
        try await batch.commit()
        print("✅ Deleted \(snapshot.documents.count) swipes")
    }

    /// Resets all pass swipes so those profiles become new again (removes pass records).
    func resetPassSwipesToNew() async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        print("🔄 Resetting pass swipes to new for user: \(currentUserId)")

        let swipesRef = db.collection("users").document(currentUserId).collection("swipes")
        let snapshot = try await swipesRef.whereField("action", isEqualTo: SwipeType.pass.rawValue).getDocuments(source: .server)

        guard !snapshot.documents.isEmpty else {
            print("✅ No pass swipes to reset")
            return
        }

        let batchSize = 450
        for batchStart in stride(from: 0, to: snapshot.documents.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, snapshot.documents.count)
            let batch = db.batch()
            for document in snapshot.documents[batchStart..<batchEnd] {
                batch.deleteDocument(document.reference)
            }
            try await batch.commit()
        }

        let remainingSnapshot = try await swipesRef.whereField("action", isEqualTo: SwipeType.pass.rawValue).getDocuments(source: .server)
        print("✅ Reset \(snapshot.documents.count) pass swipes to new. Remaining pass swipes: \(remainingSnapshot.documents.count)")
    }
    
    /// Delete only pass swipes for the current user.
    /// Keeps likes intact, so matches history remains untouched.
    func deletePassSwipes() async throws {
        try await resetPassSwipesToNew()
    }
    
    /// Delete all matches for the current user and the other user in each match pair.
    func deleteAllMatches() async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("🗑️ Deleting all matches for user: \(currentUserId)")
        
        let matchesRef = db.collection("users").document(currentUserId).collection("matches")
        let snapshot = try await matchesRef.getDocuments()
        
        var deletedCount = 0
        
        for document in snapshot.documents {
            let data = document.data()
            let matchId = document.documentID
            let user1Id = data["user1Id"] as? String
            let user2Id = data["user2Id"] as? String
            
            var refsToDelete = [document.reference]
            
            if let user1Id, let user2Id {
                let otherUserId = user1Id == currentUserId ? user2Id : user1Id
                let otherRef = db.collection("users")
                    .document(otherUserId)
                    .collection("matches")
                    .document(matchId)
                refsToDelete.append(otherRef)
            }
            
            let batch = db.batch()
            refsToDelete.forEach { batch.deleteDocument($0) }
            try await batch.commit()
            deletedCount += 1
        }
        
        print("✅ Deleted \(deletedCount) match pair(s)")
    }
    
    /// Delete all messages for the current user (both incoming and sent)
    func deleteAllMessages() async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("🗑️ Deleting all messages for user: \(currentUserId)")
        
        // Delete incoming messages
        let incomingMessagesRef = db.collection("users").document(currentUserId).collection("incomingMessages")
        let incomingSnapshot = try await incomingMessagesRef.getDocuments()
        
        // Delete sent messages
        let sentMessagesRef = db.collection("users").document(currentUserId).collection("sentMessages")
        let sentSnapshot = try await sentMessagesRef.getDocuments()
        
        let batch = db.batch()
        for document in incomingSnapshot.documents {
            batch.deleteDocument(document.reference)
        }
        for document in sentSnapshot.documents {
            batch.deleteDocument(document.reference)
        }
        
        try await batch.commit()
        print("✅ Deleted \(incomingSnapshot.documents.count) incoming messages and \(sentSnapshot.documents.count) sent messages")
        
        // Note: Messages sent by this user that are stored in other users' incomingMessages collections
        // will remain, as we cannot easily query all users' collections to find them.
        // This is a limitation but acceptable for a reset operation.
    }
    
    /// Count total matches for the current user
    func countMatches() async throws -> Int {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💕 Counting matches for user: \(currentUserId)")
        
        let matchesRef = db.collection("users").document(currentUserId).collection("matches")
        let snapshot = try await matchesRef.getDocuments()
        
        let count = snapshot.documents.count
        print("💕 Found \(count) matches")
        return count
    }
    
    /// Delete all swipes, matches, and messages for the current user
    func deleteAllUserInteractions() async throws {
        try await deleteAllSwipes()
        try await deleteAllMatches()
        try await deleteAllMessages()
        print("✅ All user interactions deleted successfully")
    }
    
    private func fetchCurrentUserLocation() async throws -> Location? {
        guard let currentUserId = auth.currentUser?.uid else { return nil }
        
        let currentUserDoc = try await db.collection("users").document(currentUserId).getDocument()
        guard let userData = currentUserDoc.data() else { return nil }
        
        return Self.parseLocation(from: userData)
    }
}

private extension FirebaseAuthService {
    static func parseLocation(from userData: [String: Any]) -> Location {
        let locationData = userData["location"] as? [String: Any] ?? [:]
        return Location(
            displayString: locationData["displayString"] as? String ?? "",
            city: locationData["city"] as? String ?? "",
            state: locationData["state"] as? String ?? "",
            country: locationData["country"] as? String ?? "",
            latitude: locationData["latitude"] as? Double,
            longitude: locationData["longitude"] as? Double
        )
    }
    
    static func distance(from sourceLocation: Location, to targetLocation: Location) -> Double? {
        guard let sourceLat = sourceLocation.latitude,
              let sourceLon = sourceLocation.longitude,
              let targetLat = targetLocation.latitude,
              let targetLon = targetLocation.longitude else {
            return nil
        }
        
        let earthRadius: Double = 6371
        let dLat = (targetLat - sourceLat) * .pi / 180.0
        let dLon = (targetLon - sourceLon) * .pi / 180.0
        
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(sourceLat * .pi / 180.0) * cos(targetLat * .pi / 180.0) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return earthRadius * c
    }
    
    static func formatDistance(_ distanceKm: Double, forMatches: Bool = false) -> String {
        if distanceKm < 1.0 {
            let meters = Int(distanceKm * 1000)
            let key = forMatches ? "matches.distance.m" : "search.distance.m"
            return String(format: key.localized, "\(meters)")
        }

        let roundedDistance = round(distanceKm * 10) / 10
        let key = forMatches ? "matches.distance.km" : "search.distance.km"
        if roundedDistance == floor(roundedDistance) {
            return String(format: key.localized, "\(Int(roundedDistance))")
        }

        return String(format: key.localized, String(format: "%.1f", roundedDistance))
    }
}
