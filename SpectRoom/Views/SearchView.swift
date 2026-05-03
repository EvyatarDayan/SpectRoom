//
//  SearchView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import Foundation

struct SearchView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedFilters: Set<String> = []
    @State private var currentCardIndex = 0
    @State private var profiles: [ProfileCard] = []
    @State private var dragOffset = CGSize.zero
    @State private var showingMatchModal = false
    @State private var matchedProfile: ProfileCard?
    @State private var isLoading = true
    @State private var showingProfileModal = false
    @State private var selectedProfile: ProfileCard?
    @State private var showingNewMessageModal = false
    @State private var matchCheckTimer: Timer?
    @State private var matchesCount: Int = 0
    @State private var messagesCount: Int = 0
    @State private var programmaticSwipeDirection: String? = nil // "left" or "right" for button-triggered swipes
    
    let filterOptions = ["Nearby", "Similar Interests", "Same Age Group", "Online Now"]
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // Card stack area
                    ZStack(alignment: .top) {
                        if isLoading {
                            // Loading indicator
                            VStack(spacing: 20) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                
                                Text("search.loading".localized)
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                        } else if currentCardIndex < profiles.count {
                            // Show only 3 cards in the pile (top card + 2 behind it)
                            ForEach(Array(profiles.enumerated().reversed()), id: \.offset) { index, profile in
                                if index >= currentCardIndex && index < currentCardIndex + 3 {
                                    SwipeableProfileCard(
                                        profile: profile,
                                        isTopCard: index == currentCardIndex,
                                        programmaticSwipeDirection: index == currentCardIndex ? Binding(
                                            get: { programmaticSwipeDirection },
                                            set: { programmaticSwipeDirection = $0 }
                                        ) : Binding(get: { nil }, set: { _ in }),
                                        onSwipeRight: {
                                            handleSwipeRight(profile: profile)
                                        },
                                        onSwipeLeft: {
                                            handleSwipeLeft(profile: profile)
                                        },
                                        onTap: {
                                            print("🔍 Card tapped for profile: \(profile.name)")
                                            print("🔍 Profile userId: \(profile.userId), age: \(profile.age)")
                                            print("🔍 Setting selectedProfile to: \(profile.name)")
                                            selectedProfile = profile
                                            print("🔍 selectedProfile after set: \(selectedProfile?.name ?? "nil"), userId: \(selectedProfile?.userId ?? "nil")")
                                            print("🔍 showingProfileModal before: \(showingProfileModal)")
                                            showingProfileModal = true
                                            print("🔍 showingProfileModal after: \(showingProfileModal)")
                                            print("🔍 Selected profile set: \(selectedProfile?.name ?? "nil")")
                                            print("🔍 Modal should show: \(showingProfileModal)")
                                        }
                                    )
                                    .zIndex(Double(3 - (index - currentCardIndex))) // Higher zIndex for cards closer to front
                                    .modifier(StackAppearance(depth: index - currentCardIndex))
                                }
                            }
                        } else {
                            // No more profiles - show card with matches and messages count
                            EmptyStateCard(
                                matchesCount: matchesCount,
                                messagesCount: messagesCount,
                                onMatchesTap: {
                                    selectedTab = 1 // Navigate to Matches tab
                                },
                                onMessagesTap: {
                                    selectedTab = 0 // Navigate to Messages tab
                                }
                            )
                            .onAppear {
                                loadMatchesAndMessagesCount()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, -120) // Lowered cards (less negative = lower position)
                    .padding(.bottom, 10) // Space for floating buttons
                    .background(
                        Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .ignoresSafeArea()
                    )
                }
                
                // Floating action buttons positioned below cards (on top of everything)
                if currentCardIndex < profiles.count {
                    VStack {
                        Spacer()
                        
                        HStack(spacing: 20) {
                            // Pass button (left side)
                            Button(action: {
                                // Haptic feedback for pass
                                let feedback = UINotificationFeedbackGenerator()
                                feedback.notificationOccurred(.error)
                                // Trigger programmatic swipe left
                                programmaticSwipeDirection = "left"
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 24))
                                    .foregroundColor(.red)
                                    .frame(width: 60, height: 60)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                            }
                            
                            Spacer()
                            
                            // Like button (right side)
                            Button(action: {
                                // Haptic feedback for like
                                let feedback = UINotificationFeedbackGenerator()
                                feedback.notificationOccurred(.success)
                                // Trigger programmatic swipe right
                                programmaticSwipeDirection = "right"
                            }) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.green)
                                    .frame(width: 60, height: 60)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                            }
                        }
                        .padding(.horizontal, 260) // Reduced from individual padding
                        .padding(.bottom, 100) // Moved down a bit
                    }
                    .allowsHitTesting(true)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
            
            // Title at the top
//            VStack {
//                Text("Matches for you!")
//                    .font(.system(size: 24, weight: .bold))
//                    .foregroundColor(.green)
//                    .multilineTextAlignment(.center)
//                    .padding(.top, 60)
////                Spacer()
//            }
//            .frame(maxWidth: .infinity)
//            .allowsHitTesting(false) // Allow taps to pass through to cards
        }
        .onAppear {
            // Clear existing profiles and reset card index for refresh
            profiles = []
            currentCardIndex = 0
            isLoading = true
            // Load fresh data 1 second after opening
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                loadUsersFromDatabase()
            }
            // Disabled to debug duplicate messages issue
            // startCheckingForMatches()
        }
        .onDisappear {
            matchCheckTimer?.invalidate()
            matchCheckTimer = nil
        }
        .sheet(isPresented: Binding(
            get: { 
                let isPresented = showingProfileModal
                print("🔍 Sheet binding GET - isPresented: \(isPresented), selectedProfile: \(selectedProfile?.name ?? "nil")")
                return isPresented
            },
            set: { newValue in
                print("🔍 Sheet binding SET - newValue: \(newValue), current showingProfileModal: \(showingProfileModal)")
                print("🔍 selectedProfile at set time: \(selectedProfile?.name ?? "nil"), userId: \(selectedProfile?.userId ?? "nil")")
                showingProfileModal = newValue
                print("🔍 showingProfileModal after set: \(showingProfileModal)")
            }
        )) {
            let _ = print("🔍 Sheet closure EXECUTING - selectedProfile: \(selectedProfile?.name ?? "nil")")
            if let profile = selectedProfile {
                let _ = print("🔍 Creating UserProfileModal with profile: \(profile.name), userId: \(profile.userId), age: \(profile.age)")
                UserProfileModal(profile: profile)
                    .environmentObject(appState)
            } else {
                let _ = print("❌ selectedProfile is nil in sheet closure!")
                VStack {
                    Text("Error: No profile selected")
                        .foregroundColor(.red)
                    Button("Close") {
                        showingProfileModal = false
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewMessageModal) {
            if let profile = matchedProfile {
                NewMessageModal(profile: profile, isExistingConversation: false)
            }
        }
    }
    
    // MARK: - Helper function to calculate distance between two coordinates using Haversine formula
    private func calculateDistance(from sourceLocation: Location, to targetLocation: Location) -> Double? {
        guard let sourceLat = sourceLocation.latitude,
              let sourceLon = sourceLocation.longitude,
              let targetLat = targetLocation.latitude,
              let targetLon = targetLocation.longitude else {
            return nil
        }
        
        let earthRadius: Double = 6371 // Earth's radius in kilometers
        
        let dLat = (targetLat - sourceLat) * .pi / 180.0
        let dLon = (targetLon - sourceLon) * .pi / 180.0
        
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(sourceLat * .pi / 180.0) * cos(targetLat * .pi / 180.0) *
                sin(dLon / 2) * sin(dLon / 2)
        
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        let distance = earthRadius * c
        return distance
    }
    
    // MARK: - Helper function to format distance string
    private func formatDistance(_ distanceKm: Double) -> String {
        if distanceKm < 1.0 {
            // Less than 1 km, show in meters
            let meters = Int(distanceKm * 1000)
            return String(format: "search.distance.m".localized, "\(meters)")
        } else {
            // 1 km or more, show in kilometers (rounded to 1 decimal place)
            let roundedDistance = round(distanceKm * 10) / 10
            if roundedDistance == floor(roundedDistance) {
                // If it's a whole number, show without decimal
                return String(format: "search.distance.km".localized, "\(Int(roundedDistance))")
            } else {
                return String(format: "search.distance.km".localized, String(format: "%.1f", roundedDistance))
            }
        }
    }
    
    // MARK: - Helper function to check if two users match based on age preferences
    private func matchesAgePreferences(currentUser: SpectRoomUser, otherUser: SpectRoomUser) -> Bool {
        let currentUserPreferredMin = currentUser.preferredAgeMin
        let currentUserPreferredMax = currentUser.preferredAgeMax
        let otherUserAge = otherUser.age
        
        // Filter based on current user's age preferences only (one-way filtering)
        // If current user has no age preferences set (both are 0 or invalid range), show all ages
        if (currentUserPreferredMin == 0 && currentUserPreferredMax == 0) || 
           currentUserPreferredMax < currentUserPreferredMin {
            // Current user has no valid age preferences set, allow match
            return true
        }
        
        // Check if other user's age is within current user's preferred range (inclusive)
        // Example: If preferred range is 32-52, show ages 32, 33, 34, ..., 51, 52
        // But NOT 31 or 53
        let isMatch = otherUserAge >= currentUserPreferredMin && otherUserAge <= currentUserPreferredMax
        
        if !isMatch {
            print("🔍 Age preference mismatch: Current user prefers \(currentUserPreferredMin)-\(currentUserPreferredMax), but other user is age \(otherUserAge)")
        }
        
        return isMatch
    }
    
    // MARK: - Helper function to check if two users match based on gender and interested in preferences
    private func matchesGenderPreferences(currentUser: SpectRoomUser, otherUser: SpectRoomUser) -> Bool {
        let currentUserGender = currentUser.gender
        let currentUserInterestedIn = Set(currentUser.interestedIn)
        let otherUserGender = otherUser.gender
        let otherUserInterestedIn = Set(otherUser.interestedIn)
        
        // Edge case: if either user has no gender or no interested in preferences, allow the match
        // This handles users who haven't completed their profile yet
        if currentUserGender.isEmpty || currentUserInterestedIn.isEmpty || otherUserGender.isEmpty || otherUserInterestedIn.isEmpty {
            print("🔍 Gender preference check: One or more users have incomplete gender/interested in data - allowing match")
            return true
        }
        
        // Check if current user's gender is in other user's interested in (or other user has "Anyone")
        let currentUserMatchesOther: Bool
        if otherUserInterestedIn.contains("Anyone") {
            currentUserMatchesOther = true // "Anyone" covers all genders
        } else {
            currentUserMatchesOther = otherUserInterestedIn.contains(currentUserGender)
        }
        
        // Check if other user's gender is in current user's interested in (or current user has "Anyone")
        let otherUserMatchesCurrent: Bool
        if currentUserInterestedIn.contains("Anyone") {
            otherUserMatchesCurrent = true // "Anyone" covers all genders
        } else {
            otherUserMatchesCurrent = currentUserInterestedIn.contains(otherUserGender)
        }
        
        // Both conditions must be true for a match
        let isMatch = currentUserMatchesOther && otherUserMatchesCurrent
        
        if !isMatch {
            print("🔍 Gender preference mismatch: Current user (\(currentUserGender)) interested in \(currentUserInterestedIn) vs Other user (\(otherUserGender)) interested in \(otherUserInterestedIn)")
        }
        
        return isMatch
    }
    
    private func loadUsersFromDatabase() {
        print("🔍 SearchView: Starting to load users from database...")
        Task {
            do {
                // Fetch all users and liked user IDs in parallel
                async let usersTask = FirebaseAuthService.shared.fetchAllUsers()
                async let likedUserIdsTask = FirebaseAuthService.shared.fetchLikedUserIds()
                
                let users = try await usersTask
                let likedUserIds = try await likedUserIdsTask
                
                print("🔍 SearchView: Received \(users.count) users from Firebase")
                print("💕 SearchView: Found \(likedUserIds.count) already-liked users to filter out")
                
                await MainActor.run {
                    if users.isEmpty {
                        print("⚠️ SearchView: No other users found in database")
                        profiles = []
                        isLoading = false
                    } else {
                        // Get current user's "Looking for" preferences (excluding "Not sure yet")
                        guard let currentUser = FirebaseAuthService.shared.currentUser else {
                            profiles = []
                            isLoading = false
                            return
                        }
                        let currentUserLookingFor = Set(currentUser.lookingFor.filter { $0 != "Not sure yet" })
                        print("🔍 SearchView: Current user looking for: \(currentUserLookingFor)")
                        
                        // Filter out users that have been liked AND filter by mutual "Looking for" values AND gender/interested in preferences
                        let filteredUsers = users.filter { user in
                            let userId = user.firebaseDocumentId ?? user.id.uuidString
                            
                            // Exclude already-liked users
                            if likedUserIds.contains(userId) {
                                print("💕 SearchView: Filtering out already-liked user: \(user.name) (\(userId))")
                                return false
                            }
                            
                            // Filter by mutual "Looking for" values (excluding "Not sure yet")
                            // If current user has no preferences (only "Not sure yet"), show all users
                            if currentUserLookingFor.isEmpty {
                                // Still need to check gender and age preferences even if no "Looking for" preferences
                                if !matchesGenderPreferences(currentUser: currentUser, otherUser: user) {
                                    return false
                                }
                                if !matchesAgePreferences(currentUser: currentUser, otherUser: user) {
                                    return false
                                }
                                return true
                            }
                            
                            let userLookingFor = Set(user.lookingFor.filter { $0 != "Not sure yet" })
                            let hasMutualLookingFor = !currentUserLookingFor.intersection(userLookingFor).isEmpty
                            
                            if !hasMutualLookingFor {
                                print("🔍 SearchView: Filtering out user \(user.name) - no mutual 'Looking for' values. Current user: \(currentUserLookingFor), Other user: \(userLookingFor)")
                                return false
                            }
                            
                            // Check gender and interested in preferences match
                            if !matchesGenderPreferences(currentUser: currentUser, otherUser: user) {
                                print("🔍 SearchView: Filtering out user \(user.name) - gender/interested in preferences don't match")
                                return false
                            }
                            
                            // Check age preferences match
                            if !matchesAgePreferences(currentUser: currentUser, otherUser: user) {
                                print("🔍 SearchView: Filtering out user \(user.name) - age preferences don't match")
                                return false
                            }
                            
                            return true
                        }
                        
                        profiles = filteredUsers.map { user in
                            // Calculate distance from current user to this user
                            let distanceString: String
                            if let distanceKm = calculateDistance(from: currentUser.location, to: user.location) {
                                distanceString = formatDistance(distanceKm)
                            } else {
                                // If coordinates are not available, fallback to "Location not set" or "2 km away" placeholder
                                distanceString = String(format: "search.distance.km".localized, "2") // Placeholder if location data is not available
                            }
                            
                            let profileCard = ProfileCard(
                                userId: user.firebaseDocumentId ?? user.id.uuidString, // Use Firebase document ID if available
                                name: user.name,
                                age: user.age,
                                bio: user.bio,
                                interests: user.interests,
                                distance: distanceString,
                                imageURL: user.profilePhotoURL,
                                gender: user.gender,
                                interestedIn: user.interestedIn,
                                lookingFor: user.lookingFor,
                                photos: user.photos,
                                lifestyle: user.lifestyle,
                                shareLifestyle: user.shareLifestyle,
                                bodyType: user.bodyType,
                                shareBodyType: user.shareBodyType,
                                preferredAgeMin: user.preferredAgeMin,
                                preferredAgeMax: user.preferredAgeMax,
                                isOnline: user.isOnline,
                                lastSeen: user.lastSeen,
                                idealFirstDate: user.idealFirstDate,
                                shareIdealFirstDate: user.shareIdealFirstDate,
                                energyLevel: user.energyLevel
                            )
                            print("🔍 SearchView: Created profile card for \(user.name) (\(user.email)) with userId: \(user.firebaseDocumentId ?? user.id.uuidString), distance: \(distanceString)")
                            return profileCard
                        }
                        print("✅ SearchView: Successfully loaded \(profiles.count) profiles (filtered from \(users.count) total)")
                        isLoading = false
                        
                        // Load matches and messages count if no profiles available
                        if profiles.isEmpty {
                            loadMatchesAndMessagesCount()
                        }
                    }
                }
            } catch {
                print("❌ SearchView: Error loading users: \(error)")
                print("❌ SearchView: Error details: \(error.localizedDescription)")
                await MainActor.run {
                    isLoading = false
                    profiles = []
                    print("⚠️ SearchView: Set profiles to empty array due to error")
                }
            }
        }
    }
    
    private func loadSampleProfiles() {
        profiles = [
            ProfileCard(userId: "sample_alex_id", name: "Alex", age: 25, bio: "Love photography and hiking. Looking for someone to explore the city with!", interests: ["Photography", "Hiking", "Coffee"], distance: "2 km away", imageURL: nil, gender: "Man", interestedIn: ["Woman"], lookingFor: ["Relationship"], photos: [], lifestyle: "independent", shareLifestyle: true, bodyType: "", shareBodyType: false, preferredAgeMin: 25, preferredAgeMax: 30, isOnline: false, lastSeen: Date(), idealFirstDate: [], shareIdealFirstDate: false, energyLevel: 4),
            ProfileCard(userId: "sample_sam_id", name: "Sam", age: 28, bio: "Artist and musician. Always up for a good conversation!", interests: ["Art", "Music", "Reading"], distance: "5 km away", imageURL: nil, gender: "Woman", interestedIn: ["Man"], lookingFor: ["Friendship"], photos: [], lifestyle: "familySupport", shareLifestyle: true, bodyType: "", shareBodyType: false, preferredAgeMin: 28, preferredAgeMax: 33, isOnline: false, lastSeen: Date(), idealFirstDate: [], shareIdealFirstDate: false, energyLevel: 4),
            ProfileCard(userId: "sample_jordan_id", name: "Jordan", age: 23, bio: "Tech enthusiast and gamer. Let's grab coffee and chat!", interests: ["Technology", "Gaming", "Coffee"], distance: "1 km away", imageURL: nil, gender: "Man", interestedIn: ["Woman"], lookingFor: ["Relationship"], photos: [], lifestyle: "assistedSetting", shareLifestyle: true, bodyType: "", shareBodyType: false, preferredAgeMin: 23, preferredAgeMax: 28, isOnline: false, lastSeen: Date(), idealFirstDate: [], shareIdealFirstDate: false, energyLevel: 4),
            ProfileCard(userId: "sample_taylor_id", name: "Taylor", age: 26, bio: "Fitness lover and foodie. Looking for someone to share adventures with!", interests: ["Fitness", "Cooking", "Travel"], distance: "3 km away", imageURL: nil, gender: "Woman", interestedIn: ["Man"], lookingFor: ["Relationship"], photos: [], lifestyle: "independent", shareLifestyle: true, bodyType: "", shareBodyType: false, preferredAgeMin: 26, preferredAgeMax: 31, isOnline: false, lastSeen: Date(), idealFirstDate: [], shareIdealFirstDate: false, energyLevel: 4),
            ProfileCard(userId: "sample_casey_id", name: "Casey", age: 24, bio: "Bookworm and nature enthusiast. Let's go for a walk!", interests: ["Reading", "Nature", "Writing"], distance: "4 km away", imageURL: nil, gender: "Other", interestedIn: ["Man", "Woman"], lookingFor: ["Friendship"], photos: [], lifestyle: "preferNot", shareLifestyle: false, bodyType: "", shareBodyType: false, preferredAgeMin: 24, preferredAgeMax: 29, isOnline: false, lastSeen: Date(), idealFirstDate: [], shareIdealFirstDate: false, energyLevel: 4)
        ]
    }
    
    private func handleSwipeRight(profile: ProfileCard) {
        // Handle like/approve
        print("✅ Liked: \(profile.name)")
        
        Task {
            do {
                // Record the swipe action
                try await FirebaseAuthService.shared.recordSwipe(to: profile.userId, action: .like)
                
                // Check if this creates a match
                let isMatch = try await FirebaseAuthService.shared.checkForMatch(with: profile.userId)
                
                await MainActor.run {
                    if isMatch {
                        // Match created - let the listener handle showing the popup for both users
                        // Don't show popup here, just wait for the listener to trigger
                        print("💕 Match created with \(profile.name)! - listener will show popup")
                        // Move to next card immediately since popup will be handled by listener
                        moveToNextCard()
                    } else {
                        print("💕 Liked \(profile.name), but no match yet")
                        moveToNextCard()
                    }
                }
            } catch {
                print("❌ Error handling swipe right: \(error)")
                await MainActor.run {
                    moveToNextCard()
                }
            }
        }
    }
    
    private func handleSwipeLeft(profile: ProfileCard) {
        // Handle pass/deny
        print("❌ Passed: \(profile.name)")
        
        Task {
            do {
                // Record the swipe action
                try await FirebaseAuthService.shared.recordSwipe(to: profile.userId, action: .pass)
                
                await MainActor.run {
                    moveToNextCard()
                }
            } catch {
                print("❌ Error handling swipe left: \(error)")
                await MainActor.run {
                    moveToNextCard()
                }
            }
        }
    }
    
    private func moveToNextCard() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            currentCardIndex += 1
            
            // Load counts when we reach the end of profiles
            if currentCardIndex >= profiles.count && !profiles.isEmpty {
                loadMatchesAndMessagesCount()
            }
        }
    }
    
    private func calculateMatchPercentage(for profile: ProfileCard) -> Int {
        guard let currentUser = FirebaseAuthService.shared.currentUser else { return 0 }
        
        var matchScore = 0
        var totalFactors = 0
        
        // 1. Interests match (40% weight)
        let currentUserInterests = Set(currentUser.interests)
        let profileInterests = Set(profile.interests)
        let commonInterests = currentUserInterests.intersection(profileInterests)
        let interestsMatch = commonInterests.count > 0 ? Double(commonInterests.count) / Double(max(currentUserInterests.count, profileInterests.count)) : 0.0
        matchScore += Int(interestsMatch * 40)
        totalFactors += 40
        
        // 2. Age compatibility (30% weight)
        let currentUserAge = currentUser.age
        let profileAge = profile.age
        let ageDifference = abs(currentUserAge - profileAge)
        let ageMatch = max(0, 1.0 - Double(ageDifference) / 20.0) // Decreases by 5% per year difference, max 20 years
        matchScore += Int(ageMatch * 30)
        totalFactors += 30
        
        // 3. Gender preferences (30% weight)
        let currentUserInterestedIn = Set(currentUser.interestedIn)
        let profileGender = profile.gender
        let genderMatch = currentUserInterestedIn.contains(profileGender) ? 1.0 : 0.0
        matchScore += Int(genderMatch * 30)
        totalFactors += 30
        
        // Calculate final percentage
        let percentage = totalFactors > 0 ? Int((Double(matchScore) / Double(totalFactors)) * 100) : 0
        return min(max(percentage, 15), 95) // Ensure it's between 15% and 95%
    }
    
    private func startCheckingForMatches() {
        print("💕 Starting periodic match checking")
        
        // Invalidate existing timer if any
        matchCheckTimer?.invalidate()
        
        // Check for matches every 3 seconds
        matchCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task {
                await checkForNewMatches()
            }
        }
    }
    
    private func checkForNewMatches() async {
        // Only check if not already showing a match popup
        guard !showingMatchModal else {
            print("💕 Already showing match popup, skipping check")
            return
        }
        
        // Safety check for Firebase authentication
        guard FirebaseAuthService.shared.isAuthenticated else {
            print("💕 User not authenticated, skipping match check")
            return
        }
        
        do {
            // Fetch recent matches from Firebase
            let matches = try await FirebaseAuthService.shared.fetchMatches()
            
            // Check if there are any new matches
            for match in matches {
                let matchTime = match.matchedAt
                let timeDifference = Date().timeIntervalSince(matchTime)
                
                // Only show popup for matches created in the last 10 seconds
                if timeDifference <= 10.0 {
                    print("💕 Found new match: \(match.otherUser.name)")
                    
                    await MainActor.run {
                        // Set the profile FIRST, then show modal after a tiny delay
                        matchedProfile = match.otherUser
                        print("💕 matchedProfile set to: \(match.otherUser.name)")
                        
                        // Use asyncAfter to ensure state propagates before showing sheet
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            showingMatchModal = true
                            print("💕 showingMatchModal set to: \(showingMatchModal)")
                            print("💕 Showing match popup for: \(match.otherUser.name)")
                        }
                    }
                    break // Only show one popup at a time
                }
            }
        } catch {
            print("❌ Error checking for matches: \(error)")
        }
    }
    
    // MARK: - Load matches and messages count
    private func loadMatchesAndMessagesCount() {
        Task {
            do {
                // Fetch matches count
                let matches = try await FirebaseAuthService.shared.fetchMatches()
                await MainActor.run {
                    matchesCount = matches.count
                }
                
                // Fetch only unread incoming messages count (not sent messages or already read messages)
                let unreadCount = try await FirebaseAuthService.shared.countUnreadIncomingMessages()
                await MainActor.run {
                    messagesCount = unreadCount
                }
                
                print("📊 Loaded counts: \(matchesCount) matches, \(messagesCount) unread messages")
            } catch {
                print("❌ Error loading matches/messages count: \(error)")
            }
        }
    }
}

struct SwipeableProfileCard: View {
    let profile: ProfileCard
    let isTopCard: Bool
    @Binding var programmaticSwipeDirection: String?
    let onSwipeRight: () -> Void
    let onSwipeLeft: () -> Void
    let onTap: () -> Void
    
    private let cardWidth = UIScreen.main.bounds.width - 60
    
    private func calculateMatchPercentage(for profile: ProfileCard) -> Int {
        guard let currentUser = FirebaseAuthService.shared.currentUser else { return 0 }
        
        var matchScore = 0
        var totalFactors = 0
        
        // 1. Interests match (40% weight)
        let currentUserInterests = Set(currentUser.interests)
        let profileInterests = Set(profile.interests)
        let commonInterests = currentUserInterests.intersection(profileInterests)
        let interestsMatch = commonInterests.count > 0 ? Double(commonInterests.count) / Double(max(currentUserInterests.count, profileInterests.count)) : 0.0
        matchScore += Int(interestsMatch * 40)
        totalFactors += 40
        
        // 2. Age compatibility (30% weight)
        let currentUserAge = currentUser.age
        let profileAge = profile.age
        let ageDifference = abs(currentUserAge - profileAge)
        let ageMatch = max(0, 1.0 - Double(ageDifference) / 20.0) // Decreases by 5% per year difference, max 20 years
        matchScore += Int(ageMatch * 30)
        totalFactors += 30
        
        // 3. Gender preferences (30% weight)
        let currentUserInterestedIn = Set(currentUser.interestedIn)
        let profileGender = profile.gender
        let genderMatch = currentUserInterestedIn.contains(profileGender) ? 1.0 : 0.0
        matchScore += Int(genderMatch * 30)
        totalFactors += 30
        
        // Calculate final percentage
        let percentage = totalFactors > 0 ? Int((Double(matchScore) / Double(totalFactors)) * 100) : 0
        return min(max(percentage, 15), 95) // Ensure it's between 15% and 95%
    }
    
    // MARK: - Helper function to extract first name
    private func firstName(from fullName: String) -> String {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return components.first.map(String.init) ?? fullName
    }
    
    @State private var dragOffset = CGSize.zero
    @State private var rotationAngle: Double = 0
    @State private var isDragging = false
    @State private var programmaticDragOffset = CGSize.zero
    @State private var isProcessingProgrammaticSwipe = false
    
    var body: some View {
        ZStack {
            // Card background with fixed width
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
                .frame(width: cardWidth, height: 500)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            
            VStack(spacing: 0) {
                // Profile image area with padding
                ZStack(alignment: .bottomLeading) {
                    // Photo container with padding
                    ZStack {
                        if let imageURL = profile.imageURL, let url = URL(string: imageURL) {
                            CachedAsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 80))
                                            .foregroundColor(.gray)
                                    )
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.gray.opacity(0.3))
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 80))
                                        .foregroundColor(.gray)
                                )
                        }
                    }
                    .frame(width: cardWidth - 32, height: 300) // Fixed width: card width minus padding (16 * 2)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 16) // Padding creates space inside the card
                    
                    // Distance label positioned relative to card edges (top right)
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                
                                Text(profile.distance)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black.opacity(0.3))
                            )
                            .padding(.top, 15)
                            .padding(.trailing, 30)
                        }
                        Spacer()
                    }
                    .frame(width: cardWidth) // Full card width for positioning
                    
                    // Name and age label positioned relative to card edges (bottom left)
                    VStack {
                        Spacer()
                        HStack {
                            Text("\(firstName(from: profile.name)), \(profile.age)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.black.opacity(0.3))
                                )
                                .padding(.leading, 30)
                                .padding(.bottom, 15)
                            Spacer()
                        }
                    }
                    .frame(width: cardWidth) // Full card width for positioning
                    
                    // Online/Offline indicator positioned relative to card edges (bottom right)
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(profile.isOnline ? Color.green : Color.red)
                                    .frame(width: 6, height: 6)
                                Text(profile.isOnline ? "search.online.now".localized : "search.offline".localized)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black.opacity(0.3))
                            )
                            .padding(.trailing, 30)
                            .padding(.bottom, 15)
                        }
                    }
                    .frame(width: cardWidth) // Full card width for positioning
                }
                .frame(height: 300) // Fixed height for photo area
                .padding(.top, 16) // Consistent vertical padding at top
                .padding(.bottom, 12) // Consistent vertical padding after photo
                
                // Bio and match % sections
                VStack(alignment: .leading, spacing: 12) {
                    // About me framed block (content only, limited to two lines) - fixed height
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .frame(height: 70)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.15), lineWidth: 3)
                            )
                        
                        VStack(alignment: .leading, spacing: 0) {
                            Text(profile.bio)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                    .frame(height: 80)
                    
                    // Match percentage framed block (two lines) - fixed height
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                            .frame(height: 70)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.15), lineWidth: 3)
                            )
                        
                        VStack(spacing: 6) {
                            Text(String(format: "search.match.with".localized, "\(calculateMatchPercentage(for: profile))"))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.green)
                            Text(profile.name)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                    .frame(height: 80)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .frame(width: cardWidth)
            
            // Swipe indicators overlay (centered on card)
            if isTopCard {
                let combinedOffset = CGSize(
                    width: dragOffset.width + programmaticDragOffset.width,
                    height: dragOffset.height + programmaticDragOffset.height
                )
                
                // X indicator for left swipe (pass)
                if combinedOffset.width < 0 {
                    Image(systemName: "xmark")
                        .font(.system(size: 160))
                        .foregroundColor(.red)
                        .opacity(min(abs(combinedOffset.width) / 170.0, 1.0))
                }
                
                // Heart indicator for right swipe (like)
                if combinedOffset.width > 0 {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 160))
                        .foregroundColor(.green)
                        .opacity(min(combinedOffset.width / 170.0, 1.0))
                }
            }
        }
        .frame(width: cardWidth, height: 500)
        .offset(CGSize(
            width: dragOffset.width + programmaticDragOffset.width,
            height: dragOffset.height + programmaticDragOffset.height
        ))
        .rotationEffect(.degrees(rotationAngle + Double(programmaticDragOffset.width / 20)))
        .onTapGesture {
            onTap()
        }
        .onAppear {
            // Reset state when card becomes the top card
            if isTopCard {
                programmaticDragOffset = .zero
                dragOffset = .zero
                rotationAngle = 0
                isProcessingProgrammaticSwipe = false
            }
        }
        .onChange(of: isTopCard) { newValue in
            // Reset state when card becomes the top card
            if newValue {
                programmaticDragOffset = .zero
                dragOffset = .zero
                rotationAngle = 0
                isProcessingProgrammaticSwipe = false
            }
        }
        .onChange(of: programmaticSwipeDirection) { newDirection in
            guard let direction = newDirection, isTopCard, !isProcessingProgrammaticSwipe else { return }
            
            // Set flag to prevent re-triggering
            isProcessingProgrammaticSwipe = true
            
            // Store the direction locally before clearing
            let swipeDirection = direction
            
            // Reset programmatic drag state
            programmaticDragOffset = .zero
            
            // Clear the binding immediately to prevent onChange from triggering again
            programmaticSwipeDirection = nil
            
            // Step 1: Animate indicator appearing fully (reach 170pt for full opacity)
            withAnimation(.easeOut(duration: 0.6)) {
                if swipeDirection == "right" {
                    programmaticDragOffset = CGSize(width: 170, height: 0)
                } else if swipeDirection == "left" {
                    programmaticDragOffset = CGSize(width: -170, height: 0)
                }
            }
            
            // Step 2: After indicator is fully visible (full opacity), animate card off-screen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    if swipeDirection == "right" {
                        programmaticDragOffset = CGSize(width: 1000, height: 0)
                        rotationAngle = 30
                    } else if swipeDirection == "left" {
                        programmaticDragOffset = CGSize(width: -1000, height: 0)
                        rotationAngle = -30
                    }
                }
                
                // Call handler after animation starts
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if swipeDirection == "right" {
                        onSwipeRight()
                    } else if swipeDirection == "left" {
                        onSwipeLeft()
                    }
                    
                    // Reset flag after handler is called
                    // Don't reset visual state - keep card off-screen
                    // The state will be reset when a new card becomes the top card
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isProcessingProgrammaticSwipe = false
                    }
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if isTopCard {
                        // Set dragging flag to prevent premature completion
                        if !isDragging {
                            isDragging = true
                        }
                        // Update visual feedback during drag
                        dragOffset = value.translation
                        rotationAngle = Double(value.translation.width / 20)
                    }
                }
                .onEnded { value in
                    if isTopCard {
                        // Mark dragging as ended - user lifted their hand
                        isDragging = false
                        
                        let threshold: CGFloat = 100
                        
                        // Only complete swipe action if user lifted their hand (drag ended)
                        if value.translation.width > threshold {
                            // Swipe right - Like
                            withAnimation(.spring()) {
                                dragOffset = CGSize(width: 1000, height: 0)
                                rotationAngle = 30
                            }
                            // Action only executes after user lifts hand (onEnded)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                // Double-check: only execute if user has lifted hand
                                if !isDragging {
                                    onSwipeRight()
                                }
                            }
                        } else if value.translation.width < -threshold {
                            // Swipe left - Pass
                            withAnimation(.spring()) {
                                dragOffset = CGSize(width: -1000, height: 0)
                                rotationAngle = -30
                            }
                            // Action only executes after user lifts hand (onEnded)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                // Double-check: only execute if user has lifted hand
                                if !isDragging {
                                    onSwipeLeft()
                                }
                            }
                        } else {
                            // Return to center
                            withAnimation(.spring()) {
                                dragOffset = .zero
                                rotationAngle = 0
                            }
                        }
                    }
                }
        )
    }
}

// Appearance for stacked cards under the top card
private struct StackAppearance: ViewModifier {
    let depth: Int
    func body(content: Content) -> some View {
        let clampedDepth = max(0, depth)
        
        // Pile effect: cards behind peek out from top center
        // Scale down slightly for cards behind
        let scale = max(0.95, 1.0 - CGFloat(clampedDepth) * 0.02)
        
        // Offset cards behind: move up only (centered horizontally, creating vertical pile effect)
        // Increased spacing for clearer pile effect
        let yOffset = CGFloat(clampedDepth) * -24  // Move up (negative = up), increased from -12 to -24 for more separation
        
        return content
            .scaleEffect(scale)
            .offset(y: yOffset)
            .opacity(clampedDepth == 0 ? 1.0 : 0.95)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}

// MARK: - Energy Level Option Enum (shared with ProfileEditView and ProfileView)
private enum EnergyLevelOption: Int, CaseIterable {
    case quietAndCalm = 0
    case softAndSteady = 1
    case balancedEnergy = 2
    case readyToChat = 3
    case fullySocialMode = 4
    
    var title: String {
        switch self {
        case .quietAndCalm:
            return "profile.edit.energy.quiet.calm".localized
        case .softAndSteady:
            return "profile.edit.energy.soft.steady".localized
        case .balancedEnergy:
            return "profile.edit.energy.balanced".localized
        case .readyToChat:
            return "profile.edit.energy.ready.chat".localized
        case .fullySocialMode:
            return "profile.edit.energy.fully.social".localized
        }
    }
    
    var color: Color {
        switch self {
        case .quietAndCalm:
            return Color(hex: "#950404")
        case .softAndSteady:
            return Color(hex: "#da0808")
        case .balancedEnergy:
            return Color(hex: "#ff9323")
        case .readyToChat:
            return Color(hex: "#f1dc32")
        case .fullySocialMode:
            return Color(hex: "#69c440")
        }
    }
}

struct UserProfileModal: View {
    let profile: ProfileCard
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var appState: AppStateManager
    @State private var showingPhotoViewer = false
    @State private var selectedPhotoIndex = 0
    @State private var photosCarouselIndex = 0
    @State private var refreshedProfile: ProfileCard?
    
    init(profile: ProfileCard) {
        self.profile = profile
        print("🔍 UserProfileModal INIT called with profile: \(profile.name), userId: \(profile.userId)")
    }
    
    private var profileTitle: String {
        let name = displayProfile.name
        if !name.isEmpty {
            return String(format: "profile.title.with.name".localized, name)
        }
        return "profile.title".localized
    }

    private var displayProfile: ProfileCard {
        refreshedProfile ?? profile
    }
    
    var body: some View {
        let _ = print("🔍 UserProfileModal body being computed, profile name: \(profile.name)")
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Profile Header Section
                    profileHeaderSection
                    
                    // My Photos Section (moved right after profile photo)
                    myPhotosSection
                    
                    // Age Section
                    ageSection
                    
                    // Location Section
                    locationSection
                    
                    // Energy Level Section
                    energyLevelSection
                    
                    // About Me Section
                    aboutMeSection
                    
                    // My Interests Section
                    myInterestsSection
                    
                    // Gender & Preferences Section
                    genderPreferencesSection
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 100) // Increased bottom padding
            }
            .background(
                Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            )
            .navigationTitle(profileTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 30) {
                        Spacer()
                            .frame(height: 16)
                        Text(profileTitle)
                            .font(.system(size: 28, weight: .bold))
                            .padding(.bottom, 30)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            print("🔍 UserProfileModal appeared for: \(profile.name)")
            print("🔍 Profile userId: \(profile.userId), name: \(profile.name)")
            // Reset refreshed profile to ensure we use the original profile initially
            refreshedProfile = nil
            // Ensure profile data is available
            guard !profile.userId.isEmpty else {
                print("❌ Profile userId is empty!")
                return
            }
            // Refresh profile data in background after view renders
            // Use a longer delay to ensure view is fully rendered first
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                await refreshProfileAsync()
            }
        }
        .refreshable {
            // Allow pull-to-refresh
            await refreshProfileAsync()
        }
        .sheet(isPresented: $showingPhotoViewer) {
            let allPhotos: [String] = {
                var photos = displayProfile.photos
                if let profilePhotoURL = displayProfile.imageURL, !profilePhotoURL.isEmpty {
                    photos.insert(profilePhotoURL, at: 0)
                }
                return photos
            }()
            
            if !allPhotos.isEmpty {
                PhotoViewerModal(
                    photos: allPhotos,
                    selectedIndex: $selectedPhotoIndex
                )
                .presentationBackground(.clear)
            }
        }
    }
    
    // MARK: - Refresh Profile
    private func refreshProfile() {
        Task {
            await refreshProfileAsync()
        }
    }
    
    private func refreshProfileAsync() async {
        do {
            // Fetch latest profile data from Firebase
            let refreshed = try await FirebaseAuthService.shared.fetchUserProfile(for: profile.userId)
            
            // Keep the original distance from the profile card (already calculated)
            // Update the refreshed profile with the original distance
            let updatedProfile = ProfileCard(
                userId: refreshed.userId,
                name: refreshed.name,
                age: refreshed.age,
                bio: refreshed.bio,
                interests: refreshed.interests,
                distance: profile.distance, // Keep original distance from card
                imageURL: refreshed.imageURL,
                gender: refreshed.gender,
                interestedIn: refreshed.interestedIn,
                lookingFor: refreshed.lookingFor,
                photos: refreshed.photos,
                lifestyle: refreshed.lifestyle,
                shareLifestyle: refreshed.shareLifestyle,
                bodyType: refreshed.bodyType,
                shareBodyType: refreshed.shareBodyType,
                preferredAgeMin: refreshed.preferredAgeMin,
                preferredAgeMax: refreshed.preferredAgeMax,
                isOnline: refreshed.isOnline,
                lastSeen: refreshed.lastSeen,
                idealFirstDate: refreshed.idealFirstDate,
                shareIdealFirstDate: refreshed.shareIdealFirstDate,
                energyLevel: refreshed.energyLevel
            )
            
            await MainActor.run {
                refreshedProfile = updatedProfile
                print("✅ Profile refreshed for: \(updatedProfile.name)")
            }
        } catch {
            print("❌ Error refreshing profile: \(error)")
            // Keep using original profile if refresh fails
        }
    }
    
    // MARK: - Profile Header Section
    private var profileHeaderSection: some View {
        ZStack {
            if let imageURL = displayProfile.imageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 25)
                        .scaleEffect(1.2)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .overlay(
            VStack {
                Button(action: {
                    // Check if there are any photos to show
                    let hasProfilePhoto = displayProfile.imageURL != nil && !displayProfile.imageURL!.isEmpty
                    let hasGalleryPhotos = !displayProfile.photos.isEmpty
                    if hasProfilePhoto || hasGalleryPhotos {
                        selectedPhotoIndex = 0 // Profile photo will be at index 0
                        showingPhotoViewer = true
                    }
                }) {
                    Group {
                        if let imageURL = displayProfile.imageURL, let url = URL(string: imageURL) {
                            CachedAsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 50))
                                            .foregroundColor(.gray)
                                    )
                            }
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.gray)
                                )
                        }
                    }
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.8), lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.vertical, 20)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
    }
    
    // MARK: - Age Section
    private var ageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.age".localized)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            Text("\(displayProfile.age) " + "profile.years.old".localized)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Location Section
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.location".localized)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            Text(displayProfile.distance)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Energy Level Section
    private var energyLevelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.edit.energy.level".localized)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            let energyOption = EnergyLevelOption(rawValue: displayProfile.energyLevel) ?? .fullySocialMode
            Text(energyOption.title)
                .font(.subheadline)
                .foregroundColor(energyOption.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - About Me Section
    private var aboutMeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("profile.about.me".localized)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            Text(displayProfile.bio.isEmpty ? "profile.no.bio".localized : displayProfile.bio)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            Divider()
                .frame(height: 2)
                .background(Color.gray.opacity(0.3))
                .padding(.vertical, 4)
            
            if displayProfile.shareLifestyle {
                Text("profile.lifestyle.title".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                Text(formattedLifestyle(displayProfile.lifestyle))
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            if displayProfile.shareBodyType, !displayProfile.bodyType.isEmpty {
                if displayProfile.shareLifestyle {
                    Divider()
                        .frame(height: 2)
                        .background(Color.gray.opacity(0.3))
                        .padding(.vertical, 4)
                }
                
                Text("profile.body.type".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                Text(formattedBodyType(displayProfile.bodyType))
                    .font(.body)
                    .foregroundColor(.primary)
            }
            
            if displayProfile.shareIdealFirstDate, !displayProfile.idealFirstDate.isEmpty {
                if displayProfile.shareLifestyle || displayProfile.shareBodyType {
                    Divider()
                        .frame(height: 2)
                        .background(Color.gray.opacity(0.3))
                        .padding(.vertical, 4)
                }
                
                Text("profile.ideal.first.date".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                Text(formattedIdealFirstDate(displayProfile.idealFirstDate))
                    .font(.body)
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - My Interests Section
    private var myInterestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.my.interests".localized)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            if displayProfile.interests.isEmpty {
                Text("profile.no.interests".localized)
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                Text(displayProfile.interests.map { localizedInterest($0) }.joined(separator: ", "))
                    .font(.body)
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Gender & Preferences Section
    private var genderPreferencesSection: some View {
        let hasGenderOrInterestedIn = !displayProfile.gender.isEmpty || !displayProfile.interestedIn.isEmpty
        let hasLookingFor = !displayProfile.lookingFor.isEmpty
        let defaultMin = displayProfile.age
        let defaultMax = min(displayProfile.age + 5, 70)
        let hasCustomPreferredAge = displayProfile.preferredAgeMin != defaultMin || displayProfile.preferredAgeMax != defaultMax
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("profile.preferences".localized)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            
            if hasGenderOrInterestedIn || hasLookingFor || hasCustomPreferredAge {
                VStack(alignment: .leading, spacing: 8) {
                    if hasGenderOrInterestedIn {
                        if !displayProfile.gender.isEmpty && !displayProfile.interestedIn.isEmpty {
                            Text("profile.im.a".localized + " \(formatGender(displayProfile.gender)), " + "profile.interested.in".localized + " \(formatInterestedIn(displayProfile.interestedIn))")
                                .font(.body)
                                .foregroundColor(.primary)
                                .italic()
                        } else if !displayProfile.gender.isEmpty {
                            Text("profile.im.a".localized + " \(formatGender(displayProfile.gender))")
                                .font(.body)
                                .foregroundColor(.primary)
                                .italic()
                        } else if !displayProfile.interestedIn.isEmpty {
                            Text("profile.interested.in".localized.capitalized + " \(formatInterestedIn(displayProfile.interestedIn))")
                                .font(.body)
                                .foregroundColor(.primary)
                                .italic()
                        }
                    }
                    
                    if hasGenderOrInterestedIn && hasLookingFor {
                        Divider()
                            .frame(height: 2)
                            .background(Color.gray.opacity(0.3))
                            .padding(.vertical, 4)
                    }
                    
                    if hasLookingFor {
                        Text("profile.looking.for".localized + " \(formatLookingFor(displayProfile.lookingFor))")
                            .font(.body)
                            .foregroundColor(.primary)
                            .italic()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    
                    if hasLookingFor && hasCustomPreferredAge {
                        Divider()
                            .frame(height: 2)
                            .background(Color.gray.opacity(0.3))
                            .padding(.vertical, 4)
                    }
                    
                    if hasCustomPreferredAge {
                        Text(String(format: "profile.preferred.age".localized, "\(displayProfile.preferredAgeMin)", "\(displayProfile.preferredAgeMax)"))
                            .font(.body)
                            .foregroundColor(.primary)
                            .italic()
                    }
                }
            } else {
                Text("profile.no.preferences".localized)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func formatInterestedIn(_ preferences: [String]) -> String {
        if preferences.contains("Anyone") {
            return "profile.interested.anyone".localized
        } else if preferences.isEmpty {
            return "profile.no.one".localized
        } else {
            let formatted = preferences.map { formatPreference($0) }
            return formatted.joined(separator: " / ")
        }
    }
    
    private func formatGender(_ gender: String) -> String {
        gender.lowercased()
    }
    
    private func formatLookingFor(_ lookingFor: [String]) -> String {
        if lookingFor.isEmpty {
            return "profile.nothing.specific".localized
        } else {
            let formatted = lookingFor.map { formatPreference($0) }
            return formatted.joined(separator: " / ")
        }
    }

    private func formattedLifestyle(_ lifestyle: String) -> String {
        switch lifestyle {
        case "independent":
            return "profile.edit.lifestyle.independent".localized
        case "familySupport":
            return "profile.edit.lifestyle.family".localized
        case "assistedSetting":
            return "profile.edit.lifestyle.assisted".localized
        case "preferNot":
            // Migration: handle old "preferNot" value gracefully
            return ""
        default:
            return lifestyle.isEmpty ? "" : "profile.lifestyle.placeholder".localized
        }
    }
    
    private func formattedBodyType(_ bodyType: String) -> String {
        switch bodyType {
        case "slim":
            return "profile.edit.body.type.slim".localized
        case "average":
            return "profile.edit.body.type.average".localized
        case "athletic":
            return "profile.edit.body.type.athletic".localized
        case "fullBodied":
            return "profile.edit.body.type.full.bodied".localized
        case "preferNot":
            // Migration: handle old "preferNot" value gracefully
            return ""
        default:
            return bodyType
        }
    }
    
    // MARK: - Helper function to localize interest names
    private func localizedInterest(_ interest: String) -> String {
        let key = "profile.edit.interest.\(interest.lowercased())"
        let localized = key.localized
        // If localization key doesn't exist, return original
        return localized == key ? interest : localized
    }
    
    private func formattedIdealFirstDate(_ idealFirstDate: [String]) -> String {
        let formatted = idealFirstDate.map { option in
            switch option {
            case "relaxingParkWalk":
                return "profile.edit.ideal.date.relaxing.park.walk".localized
            case "cozyCafeMeet":
                return "profile.edit.ideal.date.cozy.cafe.meet".localized
            case "museumGalleryStroll":
                return "profile.edit.ideal.date.museum.gallery.stroll".localized
            case "cinemaMovieNight":
                return "profile.edit.ideal.date.cinema.movie.night".localized
            case "friendlyVideoChat":
                return "profile.edit.ideal.date.friendly.video.chat".localized
            default:
                return option
            }
        }
        return formatted.joined(separator: ", ")
    }
    
    private func formatPreference(_ preference: String) -> String {
        if preference == "Not sure yet" {
            return "profile.edit.looking.not.sure".localized
        }
        return preference
    }

    // MARK: - My Photos Section
    private var myPhotosSection: some View {
        ZStack {
            // Same blurry background as profile photo
            if let imageURL = displayProfile.imageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 25)
                        .scaleEffect(1.2)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .overlay(
            VStack(alignment: .leading, spacing: 8) {
                if displayProfile.photos.isEmpty {
                    Text("profile.no.photos".localized)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                } else if displayProfile.photos.count <= 3 {
                    // Show all photos if 3 or fewer
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 6) {
                        ForEach(Array(displayProfile.photos.enumerated()), id: \.offset) { index, photoURL in
                            Button(action: {
                                selectedPhotoIndex = index + 1
                                showingPhotoViewer = true
                            }) {
                                ZStack {
                                    CachedAsyncImage(url: URL(string: photoURL)) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .overlay(
                                                Image(systemName: "photo")
                                                    .foregroundColor(.gray)
                                            )
                                    }
                                    .frame(width: 92, height: 92)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .frame(width: 100, height: 100)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.8), lineWidth: 2)
                                )
                                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 20)
                } else {
                    // Carousel for more than 3 photos
                    VStack(spacing: 8) {
                        TabView(selection: $photosCarouselIndex) {
                            ForEach(0..<((displayProfile.photos.count + 2) / 3), id: \.self) { pageIndex in
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 6) {
                                    ForEach(0..<3, id: \.self) { gridIndex in
                                        let photoIndex = pageIndex * 3 + gridIndex
                                        if photoIndex < displayProfile.photos.count {
                                            Button(action: {
                                                selectedPhotoIndex = photoIndex + 1
                                                showingPhotoViewer = true
                                            }) {
                                                ZStack {
                                                    CachedAsyncImage(url: URL(string: displayProfile.photos[photoIndex])) { image in
                                                        image
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                    } placeholder: {
                                                        Rectangle()
                                                            .fill(Color.gray.opacity(0.3))
                                                            .overlay(
                                                                Image(systemName: "photo")
                                                                    .foregroundColor(.gray)
                                                            )
                                                    }
                                                    .frame(width: 92, height: 92)
                                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                                }
                                                .frame(width: 100, height: 100)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                        .stroke(Color.white.opacity(0.8), lineWidth: 2)
                                                )
                                                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                                            }
                                        } else {
                                            // Empty space for incomplete rows
                                            Color.clear
                                                .aspectRatio(1, contentMode: .fit)
                                        }
                                    }
                                }
                                .tag(pageIndex)
                            }
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                        .frame(height: 105)
                        
                        // Custom smaller page indicator dots
                        HStack(spacing: 4) {
                            ForEach(0..<((displayProfile.photos.count + 2) / 3), id: \.self) { index in
                                Circle()
                                    .fill(photosCarouselIndex == index ? Color.white.opacity(0.8) : Color.white.opacity(0.3))
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 20)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
    }
}

struct PhotoViewerModal: View {
    let photos: [String]
    @Binding var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset = CGSize.zero
    
    var body: some View {
        ZStack {
            // Semi-transparent background overlay (same as recording popup)
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }
            
            if !photos.isEmpty {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, photoURL in
                        CachedAsyncImage(url: URL(string: photoURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } placeholder: {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                )
                        }
                        .padding(.horizontal, 40)
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                .onAppear {
                    preloadAllPhotos()
                }
            } else {
                VStack {
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                    
                    Text("profile.no.photos".localized)
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 35)
                    .padding(.top, 24)
                }
                Spacer()
            }
        }
    }
    
    private func preloadAllPhotos() {
        Task {
            await withTaskGroup(of: Void.self) { group in
                for photoURL in photos {
                    group.addTask {
                        guard let url = URL(string: photoURL) else { return }
                        // Check if already cached
                        if ImageCacheService.shared.image(for: photoURL) != nil {
                            return
                        }
                        // Preload image
                        do {
                            let (data, _) = try await URLSession.shared.data(from: url)
                            if let uiImage = UIImage(data: data) {
                                ImageCacheService.shared.insert(uiImage, for: photoURL)
                            }
                        } catch {
                            // Silently fail - image will load when viewed
                        }
                    }
                }
            }
        }
    }
}

struct NewMessageModal: View {
    let profile: ProfileCard
    let isExistingConversation: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var messageText: String = ""
    @State private var showingPreMessageOptions = false
    
    init(profile: ProfileCard, isExistingConversation: Bool) {
        self.profile = profile
        self.isExistingConversation = isExistingConversation
        print("💬 NewMessageModal INIT called with profile: \(profile.name), userId: \(profile.userId), isExistingConversation: \(isExistingConversation)")
    }
    
    var body: some View {
        let _ = print("💬 NewMessageModal body being computed, profile name: \(profile.name), isExistingConversation: \(isExistingConversation)")
        NavigationView {
            VStack(spacing: 20) {
                // Header with profile info
                VStack(spacing: 12) {
                    // Profile image
                    CachedAsyncImage(url: URL(string: profile.imageURL ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundColor(.gray)
                            )
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                }
                .padding(.top, 20)
                
                // Message input
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("matches.message.label".localized)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: {
                            showingPreMessageOptions = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 14))
                                Text("matches.pre.message.button".localized)
                                    .font(.subheadline)
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    TextEditor(text: $messageText)
                        .frame(minHeight: 120)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Send button
                Button(action: {
                    Task {
                        await sendMessage()
                    }
                }) {
                    Text("messages.send.message".localized)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(12)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(
                Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("matches.new.message".localized)
                            .font(.headline)
                        Text(String(format: "matches.new.message.to".localized, profile.name))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("profile.edit.cancel".localized) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingPreMessageOptions) {
            PreMessageOptionsModal(
                profileName: profile.name,
                onSelect: { selectedMessage in
                    messageText = selectedMessage
                    showingPreMessageOptions = false
                }
            )
        }
        .onAppear {
            print("💬 NewMessageModal appeared for: \(profile.name)")
            print("💬 Profile userId: \(profile.userId), isExistingConversation: \(isExistingConversation)")
            print("💬 Modal appeared - messageText will be set: \(!isExistingConversation)")
            if !isExistingConversation {
                messageText = "matches.default.message".localized
                print("💬 Default message text set: \(messageText)")
            }
        }
    }
    
    // Helper function to extract first name
    private func firstName(from fullName: String) -> String {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return components.first.map(String.init) ?? fullName
    }
    
    private func sendMessage() async {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        do {
            let messageId = try await FirebaseAuthService.shared.sendMessage(
                to: profile.userId,
                content: messageText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            
            print("✅ Message sent successfully with ID: \(messageId)")
            
            await MainActor.run {
                dismiss()
            }
            
        } catch {
            print("❌ Error sending message: \(error)")
            // TODO: Show error alert to user
        }
    }
}

struct EmptyStateCard: View {
    let matchesCount: Int
    let messagesCount: Int
    let onMatchesTap: () -> Void
    let onMessagesTap: () -> Void
    
    var body: some View {
        ZStack {
            // Card background
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            
            VStack(spacing: 0) {
                // Profile photo with text overlay
                ZStack {
                    // Profile photo with 50% opacity
                    Image("profile1")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 300)
                        .padding(.horizontal, 15)
                        .opacity(0.1)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    // Text overlay on top
                    VStack(spacing: 12) {
                        Text("search.empty.no.more.profiles.line1".localized)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text("search.empty.no.more.profiles.line2".localized)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20)
                }
                
                // Matches and messages sections
                VStack(alignment: .leading, spacing: 12) {
                    // First box: Matches count (Button)
                    Button(action: {
                        onMatchesTap()
                    }) {
                        (Text("search.empty.matches.prefix".localized)
                         + Text(" \(matchesCount)").foregroundColor(.green)
                         + Text(" " + "search.empty.matches.suffix".localized))
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    
                    // Second box: Messages count (Button)
                    Button(action: {
                        onMessagesTap()
                    }) {
                        (Text("search.empty.messages.prefix".localized)
                         + Text(" \(messagesCount)").foregroundColor(.green)
                         + Text(" " + "search.empty.messages.suffix".localized))
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: UIScreen.main.bounds.width - 60, height: 500)
    }
}

// MARK: - Pre-Message Options Modal
struct PreMessageOptionsModal: View {
    let profileName: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var isDragging = false
    @State private var dragStartLocation: CGPoint = .zero
    
    private let preMessages: [String] = [
        "matches.pre.message.option1",
        "matches.pre.message.option2",
        "matches.pre.message.option3",
        "matches.pre.message.option4",
        "matches.pre.message.option5",
        "matches.pre.message.option6",
        "matches.pre.message.option7",
        "matches.pre.message.option8",
        "matches.pre.message.option9",
        "matches.pre.message.option10",
        "matches.pre.message.option11",
        "matches.pre.message.option12"
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(preMessages.enumerated()), id: \.offset) { index, messageKey in
                            Button(action: {
                                // Only select if we're not dragging
                                if !isDragging {
                                    let message = messageKey.localized
                                    onSelect(message)
                                }
                            }) {
                                HStack(alignment: .top, spacing: 12) {
                                    Text(messageKey.localized)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .lineLimit(nil)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 2)
                                }
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 200)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                            }
                        }
                        .onEnded { _ in
                            // Reset dragging state after a short delay to allow button action to check
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isDragging = false
                            }
                        }
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("matches.pre.message.title".localized)
                            .font(.headline)
                        Text("matches.pre.message.subtitle".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, -50)
                    }

                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.close".localized) {
                        dismiss()
                    }
                }
            }
            .padding(.top, 140)
        }
    }
}

#Preview {
    SearchView(selectedTab: .constant(1))
        .environmentObject(AppStateManager.shared)
}
