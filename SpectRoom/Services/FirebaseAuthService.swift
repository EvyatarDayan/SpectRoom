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
    @Published var isAuthenticated = false
    
    let auth = Auth.auth()
    private let db = Firestore.firestore()
    
    private init() {
        // Listen for authentication state changes
        auth.addStateDidChangeListener { [weak self] _, firebaseUser in
            DispatchQueue.main.async {
                self?.isAuthenticated = firebaseUser != nil
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
                let energyLevel = userData["energyLevel"] as? Int ?? 4
                
                print("🔍 Firebase - Loaded lifestyle: \(lifestyle), shareLifestyle: \(shareLifestyle)")
                print("🔍 Firebase - Loaded bodyType: \(bodyType), shareBodyType: \(shareBodyType)")
                print("🔍 Firebase - Loaded idealFirstDate: \(idealFirstDate), shareIdealFirstDate: \(shareIdealFirstDate)")
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
                } catch {
                    userWithPhotos.blockedUsers = []
                    print("⚠️ Failed to load blocked users for \(userID): \(error.localizedDescription)")
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
    
    // MARK: - Fetch All Users for Search
    func fetchAllUsers() async throws -> [SpectRoomUser] {
        print("🔍 Starting to fetch all users from database...")
        let snapshot = try await db.collection("users").getDocuments()
        print("🔍 Found \(snapshot.documents.count) total documents in users collection")
        
        var users: [SpectRoomUser] = []
        let currentUserID = auth.currentUser?.uid
        print("🔍 Current user ID: \(currentUserID ?? "nil")")
        
        for document in snapshot.documents {
            let userData = document.data()
            let documentID = document.documentID
            print("🔍 Processing document ID: \(documentID)")
            
            // Skip current user
            if documentID == currentUserID {
                print("🔍 Skipping current user: \(documentID)")
                continue
            }
            
            let userName = userData["name"] as? String ?? "Unknown"
            let userEmail = userData["email"] as? String ?? "No email"
            print("🔍 Adding user: \(userName) (\(userEmail))")
            
            // Parse location data
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
            
            // Parse interests
            let interests = userData["interests"] as? [String] ?? []
            
            // Parse gender and preferences
            let gender = userData["gender"] as? String ?? ""
            let interestedIn = userData["interestedIn"] as? [String] ?? []
            let lookingFor = userData["lookingFor"] as? [String] ?? []
            let preferredAgeMin = userData["preferredAgeMin"] as? Int ?? 18
            let preferredAgeMax = userData["preferredAgeMax"] as? Int ?? 80
            
            // Parse date of birth
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
            let energyLevel = userData["energyLevel"] as? Int ?? 2
            
            // Load isOnline and lastSeen from Firebase
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
                energyLevel: energyLevel
            )
            
            // Set photos, profile photo, date of birth, and online status
            var userWithPhotos = user
            userWithPhotos.photos = userData["photos"] as? [String] ?? []
            userWithPhotos.profilePhotoURL = userData["profilePhotoURL"] as? String
            userWithPhotos.dateOfBirth = dateOfBirth
            userWithPhotos.firebaseDocumentId = documentID // Set Firebase document ID
            userWithPhotos.isOnline = isOnline
            userWithPhotos.lastSeen = lastSeen
            
            users.append(userWithPhotos)
        }
        
        print("🔍 Successfully fetched \(users.count) users from database")
        for user in users {
            print("🔍 User: \(user.name) (\(user.email))")
        }
        return users
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
        
        await MainActor.run {
            if var current = self.currentUser {
                current.blockedUsers.removeAll { $0.id == userId }
                self.currentUser = current
            }
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
    
    func checkForMatch(with targetUserId: String) async throws -> Bool {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💕 Checking for match between \(currentUserId) and \(targetUserId)")
        
        // Check if target user has swiped right on current user
        let targetUserSwipesRef = db.collection("users").document(targetUserId).collection("swipes")
        let targetUserSwipesSnapshot = try await targetUserSwipesRef.whereField("toUserId", isEqualTo: currentUserId).getDocuments()
        
        var targetUserLikedCurrentUser = false
        for document in targetUserSwipesSnapshot.documents {
            let data = document.data()
            if let action = data["action"] as? String, action == SwipeType.like.rawValue {
                targetUserLikedCurrentUser = true
                break
            }
        }
        
        print("💕 Target user liked current user: \(targetUserLikedCurrentUser)")
        
        if targetUserLikedCurrentUser {
            // Create a match
            try await createMatch(with: targetUserId)
            return true
        }
        
        return false
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
    
    private func createMatch(with targetUserId: String) async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💕 Creating match between \(currentUserId) and \(targetUserId)")
        
        let matchId = UUID().uuidString
        let matchData: [String: Any] = [
            "id": matchId,
            "user1Id": currentUserId,
            "user2Id": targetUserId,
            "matchedAt": Date().timeIntervalSince1970,
            "isActive": true,
            "lastMessageAt": NSNull(),
            "conversationId": UUID().uuidString
        ]
        
        // Save match to both users' matches collections
        let currentUserMatchRef = db.collection("users").document(currentUserId).collection("matches").document(matchId)
        let targetUserMatchRef = db.collection("users").document(targetUserId).collection("matches").document(matchId)
        
        try await currentUserMatchRef.setData(matchData)
        try await targetUserMatchRef.setData(matchData)
        
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
                let otherUserProfile = try await fetchUserProfile(for: otherUserId)
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
    
    func fetchUserProfile(for userId: String) async throws -> ProfileCard {
        let userDoc = try await db.collection("users").document(userId).getDocument()
        guard let userData = userDoc.data() else {
            throw NSError(domain: "FirebaseAuthService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
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
        let energyLevel = userData["energyLevel"] as? Int ?? 2
        let preferredAgeMin = userData["preferredAgeMin"] as? Int ?? age
        let preferredAgeMax = userData["preferredAgeMax"] as? Int ?? min(age + 5, 80)
        let isOnline = userData["isOnline"] as? Bool ?? false
        let lastSeenInterval = userData["lastSeen"] as? TimeInterval
        let lastSeen = lastSeenInterval.map { Date(timeIntervalSince1970: $0) } ?? Date()
        
        return ProfileCard(
            userId: userId,
            name: name,
            age: age,
            bio: bio,
            interests: interests,
            distance: "Matched", // We'll implement distance calculation later
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
            energyLevel: energyLevel
        )
    }
    
    func listenForNewMatches(completion: @escaping (MatchDisplay) -> Void) {
        guard let currentUserId = auth.currentUser?.uid else {
            print("❌ User not authenticated for match listening")
            return
        }
        
        print("💕 Starting to listen for new matches for user: \(currentUserId)")
        
        let matchesRef = db.collection("users").document(currentUserId).collection("matches")
        
        matchesRef.addSnapshotListener { snapshot, error in
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
                    
                    // Only trigger notification for recently created matches (within last 10 seconds)
                    // This ensures we notify for newly created matches, not old ones when listener first starts
                    guard timeDifference < 10.0 else {
                        print("💕 Match is older than 10 seconds, skipping notification (likely initial listener setup)")
                        continue
                    }
                    
                    // Fetch the other user's profile information
                    Task {
                        do {
                            let otherUserProfile = try await self.fetchUserProfile(for: otherUserId)
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
    
    func listenForNewMessages(completion: @escaping (String, String, String?, String) -> Void) {
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
                    
                    // Fetch sender's profile information
                    Task {
                        do {
                            let senderProfile = try await self.fetchUserProfile(for: senderId)
                            print("💬 Calling completion with sender: \(senderProfile.name)")
                            await MainActor.run {
                                completion(senderId, senderProfile.name, senderProfile.imageURL, messageDocId)
                            }
                        } catch {
                            print("❌ Error fetching sender profile for new message: \(error)")
                            // Use sender ID as fallback name
                            await MainActor.run {
                                completion(senderId, "Unknown User", nil, messageDocId)
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
    
    // Fetch all messages between current user and another user
    func fetchConversationMessages(with otherUserId: String) async throws -> [MessageDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching conversation messages between \(currentUserId) and \(otherUserId)")
        
        var allMessages: [MessageDisplay] = []
        
        // Fetch sent messages to this user
        let sentSnapshot = try await db.collection("users").document(currentUserId).collection("sentMessages").getDocuments()
        for document in sentSnapshot.documents {
            let data = document.data()
            guard let content = data["content"] as? String,
                  let senderId = data["senderId"] as? String,
                  let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { continue }
            
            // Only include messages to/from the other user
            if (senderId == currentUserId && recipientId == otherUserId) {
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
                    senderProfilePhotoURL: nil, // Current user's profile photo not needed for sent messages
                    recipientProfilePhotoURL: recipientProfilePhotoURL
                )
                
                allMessages.append(messageDisplay)
            }
        }
        
        // Fetch incoming messages from this user
        let incomingSnapshot = try await db.collection("users").document(currentUserId).collection("incomingMessages").getDocuments()
        for document in incomingSnapshot.documents {
            let data = document.data()
            guard let content = data["content"] as? String,
                  let senderId = data["senderId"] as? String,
                  let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { continue }
            
            // Only include messages from/to the other user
            if (senderId == otherUserId && recipientId == currentUserId) {
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
                    recipientProfilePhotoURL: nil // Current user's profile photo not needed for incoming messages
                )
                
                allMessages.append(messageDisplay)
            }
        }
        
        // Sort messages by creation date (oldest first, newest at bottom)
        allMessages.sort { $0.createdAt < $1.createdAt }
        
        print("💬 Message order after sorting:")
        for (index, msg) in allMessages.enumerated() {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd MMM yyyy HH:mm"
            print("💬 \(index + 1). \(msg.senderName): \(msg.content) - \(formatter.string(from: msg.createdAt))")
        }
        
        print("💬 Fetched \(allMessages.count) conversation messages")
        return allMessages
    }
    
    // Fetch only message content without profile photos (for auto-refresh)
    func fetchConversationMessagesContentOnly(with otherUserId: String) async throws -> [Message] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching conversation message content only between \(currentUserId) and \(otherUserId)")
        
        var allMessages: [Message] = []
        
        // Fetch sent messages to this user
        let sentSnapshot = try await db.collection("users").document(currentUserId).collection("sentMessages").getDocuments()
        for document in sentSnapshot.documents {
            let data = document.data()
            guard let content = data["content"] as? String,
                  let senderId = data["senderId"] as? String,
                  let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { continue }
            
            // Only include messages to/from the other user
            if (senderId == currentUserId && recipientId == otherUserId) {
                let messageTypeString = data["type"] as? String ?? "text"
                let messageType = MessageType(rawValue: messageTypeString) ?? .text
                
                let message = Message(
                    conversationId: UUID(),
                    senderId: UUID(uuidString: senderId) ?? UUID(),
                    senderFirebaseId: senderId,
                    content: content,
                    createdAt: Date(timeIntervalSince1970: createdAt),
                    type: messageType
                )
                
                allMessages.append(message)
            }
        }
        
        // Fetch incoming messages from this user
        let incomingSnapshot = try await db.collection("users").document(currentUserId).collection("incomingMessages").getDocuments()
        for document in incomingSnapshot.documents {
            let data = document.data()
            guard let content = data["content"] as? String,
                  let senderId = data["senderId"] as? String,
                  let recipientId = data["recipientId"] as? String,
                  let createdAt = data["createdAt"] as? TimeInterval else { continue }
            
            // Only include messages from/to the other user
            if (senderId == otherUserId && recipientId == currentUserId) {
                let messageTypeString = data["type"] as? String ?? "text"
                let messageType = MessageType(rawValue: messageTypeString) ?? .text
                
                let message = Message(
                    conversationId: UUID(),
                    senderId: UUID(uuidString: senderId) ?? UUID(),
                    senderFirebaseId: senderId,
                    content: content,
                    createdAt: Date(timeIntervalSince1970: createdAt),
                    type: messageType,
                    voiceDuration: data["voiceDuration"] as? TimeInterval
                )
                
                allMessages.append(message)
            }
        }
        
        // Sort messages chronologically (oldest first, newest last)
        allMessages.sort { $0.createdAt < $1.createdAt }
        
        print("💬 Fetched \(allMessages.count) conversation message content only")
        return allMessages
    }
    
    // Get latest message from each user (for conversation list)
    func fetchLatestMessagesFromEachUser() async throws -> [MessageDisplay] {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("💬 Fetching latest messages from each user...")
        
        var userLatestMessages: [String: MessageDisplay] = [:]
        var sentMessageCount = 0
        var incomingMessageCount = 0
        
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
            
            // Use recipientId as key (the other user in the conversation)
            sentMessageCount += 1
            print("💬 Processing sent message \(sentMessageCount): to \(recipientId), content: \(content.prefix(20))...")
            
            if let existingMessage = userLatestMessages[recipientId] {
                print("💬 Found existing message for \(recipientId), comparing timestamps: new=\(messageDisplay.createdAt), existing=\(existingMessage.createdAt)")
                if messageDisplay.createdAt > existingMessage.createdAt {
                    userLatestMessages[recipientId] = messageDisplay
                    print("💬 Updated message for \(recipientId) with newer message")
                } else {
                    print("💬 Kept existing message for \(recipientId) (older message)")
                }
            } else {
                userLatestMessages[recipientId] = messageDisplay
                print("💬 Added new message for \(recipientId)")
            }
        }
        
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
            
            // Use senderId as key (the other user in the conversation)
            incomingMessageCount += 1
            print("💬 Processing incoming message \(incomingMessageCount): from \(senderId), content: \(content.prefix(20))...")
            
            if let existingMessage = userLatestMessages[senderId] {
                print("💬 Found existing message for \(senderId), comparing timestamps: new=\(messageDisplay.createdAt), existing=\(existingMessage.createdAt)")
                if messageDisplay.createdAt > existingMessage.createdAt {
                    userLatestMessages[senderId] = messageDisplay
                    print("💬 Updated message for \(senderId) with newer message")
                } else {
                    print("💬 Kept existing message for \(senderId) (older message)")
                }
            } else {
                userLatestMessages[senderId] = messageDisplay
                print("💬 Added new message for \(senderId)")
            }
        }
        
        // Convert to array and sort by latest message time
        let latestMessages = Array(userLatestMessages.values)
            .sorted { $0.createdAt > $1.createdAt }
        
        print("💬 Summary: Processed \(sentMessageCount) sent messages, \(incomingMessageCount) incoming messages")
        print("💬 Final result: \(latestMessages.count) unique conversations")
        for (index, message) in latestMessages.enumerated() {
            print("💬 Conversation \(index + 1): \(message.senderName) -> \(message.recipientName), content: \(message.content.prefix(30))...")
        }
        
        return latestMessages
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
    
    /// Delete all matches for the current user
    /// Note: This only deletes matches from the current user's collection
    /// The other user's match record will still exist
    func deleteAllMatches() async throws {
        guard let currentUserId = auth.currentUser?.uid else {
            throw NSError(domain: "FirebaseAuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        print("🗑️ Deleting all matches for user: \(currentUserId)")
        
        let matchesRef = db.collection("users").document(currentUserId).collection("matches")
        let snapshot = try await matchesRef.getDocuments()
        
        let batch = db.batch()
        for document in snapshot.documents {
            batch.deleteDocument(document.reference)
        }
        
        try await batch.commit()
        print("✅ Deleted \(snapshot.documents.count) matches")
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
}
