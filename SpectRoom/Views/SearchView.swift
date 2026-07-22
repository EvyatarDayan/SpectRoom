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
    @State private var canReviewPassedProfiles = false
    @State private var hasCompletedDiscoverLoad = false
    @State private var programmaticSwipeDirection: String? = nil // "left" or "right" for button-triggered swipes
    @State private var lastFetchedUserDocumentId: String?
    @State private var hasMoreUsersToLoad = true
    @State private var hasMoreRemoteUsers = true
    @State private var isLoadingMoreProfiles = false
    @State private var cachedSwipeFilter: FirebaseAuthService.SwipeFilterState?
    @State private var pendingDiscoverProfiles: [ProfileCard] = []
    
    private enum DiscoverConstants {
        /// How many discover cards to surface per load.
        static let profilesPerBatch = 10
        /// Firestore page size used while collecting eligible users for a batch.
        static let firestorePageSize = 20
        /// Prefetch when the user reaches the 7th card of the current 10
        /// (4 cards remaining including the current one: indices 6…9).
        static let prefetchRemainingThreshold = 4
    }
    
    let filterOptions = ["Nearby", "Similar Interests", "Same Age Group", "Online Now"]
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // Card stack area
                    ZStack(alignment: .top) {
                        if isLoading && profiles.isEmpty {
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
                        } else if isLoadingMoreProfiles {
                            VStack(spacing: 20) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                
                                Text("search.loading".localized)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            // No more profiles - show card with matches and messages count
                            EmptyStateCard(
                                matchesCount: matchesCount,
                                messagesCount: messagesCount,
                                canReviewPassedProfiles: canReviewPassedProfiles,
                                onMatchesTap: {
                                    selectedTab = 1 // Navigate to Matches tab
                                },
                                onMessagesTap: {
                                    selectedTab = 0 // Navigate to Messages tab
                                },
                                onStartOverTap: {
                                    resetUnlikedProfiles()
                                }
                            )
                            .onAppear {
                                if hasMoreUsersToLoad {
                                    prefetchMoreProfilesIfNeeded()
                                } else {
                                    loadMatchesAndMessagesCount()
                                }
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
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundColor(.red)
                                    .floatingCircleButtonStyle(colorScheme: colorScheme, size: 76)
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
                                    .font(.system(size: 30))
                                    .foregroundColor(.green)
                                    .floatingCircleButtonStyle(colorScheme: colorScheme, size: 76)
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
            restoreDiscoverSessionIfAvailable()
        }
        .onChange(of: appState.currentUser?.id) { _ in
            guard appState.currentUser != nil else { return }
            guard !appState.hasValidDiscoverProfilesCache else { return }
            guard !hasCompletedDiscoverLoad else { return }
            loadDiscoverProfilesWhenReady()
        }
        .onChange(of: showingProfileModal) { isShowing in
            guard !isShowing else { return }
            let previousCount = profiles.count
            profiles.removeAll { appState.isUserBlocked($0.userId) }
            if profiles.count != previousCount {
                if currentCardIndex >= profiles.count {
                    currentCardIndex = max(0, profiles.count - 1)
                }
                syncDiscoverCache()
            }
        }
        .onDisappear {
            syncDiscoverCache()
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

    private func isUserEligibleForDeck(
        user: SpectRoomUser,
        currentUser: SpectRoomUser,
        likedUserIds: Set<String>,
        passedUserIds: Set<String>,
        blockedUserIds: Set<String>,
        ignorePassedFilter: Bool,
        requirePassedOnly: Bool = false
    ) -> Bool {
        let userId = user.firebaseDocumentId ?? user.id.uuidString

        if blockedUserIds.contains(userId) {
            return false
        }

        if likedUserIds.contains(userId) {
            return false
        }

        if requirePassedOnly {
            guard passedUserIds.contains(userId) else { return false }
        } else if !ignorePassedFilter && passedUserIds.contains(userId) {
            return false
        }

        let currentUserLookingFor = Set(currentUser.lookingFor.filter { $0 != "Not sure yet" })

        if currentUserLookingFor.isEmpty {
            if !matchesGenderPreferences(currentUser: currentUser, otherUser: user) {
                return false
            }
            if !matchesAgePreferences(currentUser: currentUser, otherUser: user) {
                return false
            }
            return true
        }

        let userLookingFor = Set(user.lookingFor.filter { $0 != "Not sure yet" })
        if !userLookingFor.isEmpty && currentUserLookingFor.intersection(userLookingFor).isEmpty {
            return false
        }

        if !matchesGenderPreferences(currentUser: currentUser, otherUser: user) {
            return false
        }

        if !matchesAgePreferences(currentUser: currentUser, otherUser: user) {
            return false
        }

        return true
    }

    private func restoreDiscoverSessionIfAvailable() {
        if appState.hasValidDiscoverProfilesCache, !appState.cachedDiscoverProfiles.isEmpty {
            profiles = appState.cachedDiscoverProfiles
            currentCardIndex = appState.cachedDiscoverCardIndex
            hasCompletedDiscoverLoad = true
            isLoading = false
            print("🔍 SearchView: Restored \(profiles.count) cached profiles at index \(currentCardIndex)")
            if currentCardIndex >= profiles.count {
                if hasMoreUsersToLoad {
                    prefetchMoreProfilesIfNeeded()
                } else {
                    loadMatchesAndMessagesCount()
                }
            }
            return
        }

        if appState.hasValidDiscoverProfilesCache {
            appState.clearDiscoverProfilesCache()
        }
        loadDiscoverProfilesWhenReady()
    }

    private func loadDiscoverProfilesWhenReady() {
        guard appState.isAuthenticated else {
            isLoading = false
            return
        }

        guard appState.currentUser != nil else {
            print("🔍 SearchView: Waiting for current user before loading discover profiles")
            hasCompletedDiscoverLoad = false
            isLoading = true
            return
        }

        hasCompletedDiscoverLoad = false
        isLoading = true
        lastFetchedUserDocumentId = nil
        hasMoreUsersToLoad = true
        hasMoreRemoteUsers = true
        cachedSwipeFilter = nil
        pendingDiscoverProfiles = []
        loadDiscoverProfiles()
    }

    private func syncDiscoverCache() {
        guard appState.isAuthenticated, hasCompletedDiscoverLoad, !isLoading, !profiles.isEmpty else { return }
        appState.updateDiscoverProfilesCache(profiles: profiles, cardIndex: currentCardIndex)
    }

    private func markDiscoverLoadCompleted() {
        hasCompletedDiscoverLoad = true
        isLoading = false
        syncDiscoverCache()
    }
    
    private func makeProfileCard(from user: SpectRoomUser, currentUser: SpectRoomUser) -> ProfileCard {
        let distanceString: String
        if let distanceKm = calculateDistance(from: currentUser.location, to: user.location) {
            distanceString = formatDistance(distanceKm)
        } else {
            distanceString = String(format: "search.distance.km".localized, "2")
        }
        
        let matchPercentage = ProfileCard.calculateMatchPercentage(
            interests: user.interests,
            age: user.age,
            gender: user.gender,
            currentUser: currentUser
        )
        
        return ProfileCard(
            userId: user.firebaseDocumentId ?? user.id.uuidString,
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
            sensoryPreferences: user.sensoryPreferences,
            shareSensoryPreferences: user.shareSensoryPreferences,
            energyLevel: user.energyLevel,
            matchPercentage: matchPercentage
        )
    }
    
    private func sortProfilesByMatchPercentage(_ items: [ProfileCard]) -> [ProfileCard] {
        items.sorted {
            if $0.matchPercentage != $1.matchPercentage {
                return $0.matchPercentage > $1.matchPercentage
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    
    private func appendProfilesFromPendingQueue() {
        guard !pendingDiscoverProfiles.isEmpty else {
            hasMoreUsersToLoad = hasMoreRemoteUsers
            isLoadingMoreProfiles = false
            return
        }
        
        let nextBatch = Array(pendingDiscoverProfiles.prefix(DiscoverConstants.profilesPerBatch))
        pendingDiscoverProfiles.removeFirst(nextBatch.count)
        profiles.append(contentsOf: nextBatch)
        hasMoreUsersToLoad = hasMoreRemoteUsers || !pendingDiscoverProfiles.isEmpty
        isLoadingMoreProfiles = false
        print("✅ SearchView: Appended \(nextBatch.count) profiles from sorted queue (total: \(profiles.count))")
    }
    
    private func loadDiscoverProfiles(
        ignorePassedFilter: Bool = false,
        preferServerSwipeData: Bool = false,
        append: Bool = false
    ) {
        if append {
            guard !isLoadingMoreProfiles, hasMoreUsersToLoad else { return }
            isLoadingMoreProfiles = true
            
            if !pendingDiscoverProfiles.isEmpty {
                appendProfilesFromPendingQueue()
                syncDiscoverCache()
                return
            }
            
            guard hasMoreRemoteUsers else {
                hasMoreUsersToLoad = false
                isLoadingMoreProfiles = false
                return
            }
        } else {
            print("🔍 SearchView: Starting paginated profile load (batch size \(DiscoverConstants.profilesPerBatch))...")
            guard appState.currentUser != nil else {
                print("⚠️ SearchView: currentUser not ready yet, deferring profile load")
                hasCompletedDiscoverLoad = false
                isLoading = true
                return
            }
            isLoading = true
            lastFetchedUserDocumentId = nil
            hasMoreUsersToLoad = true
            hasMoreRemoteUsers = true
            pendingDiscoverProfiles = []
            profiles = []
            currentCardIndex = 0
        }
        
        Task {
            do {
                let swipeFilter: FirebaseAuthService.SwipeFilterState
                if append, let cachedSwipeFilter {
                    swipeFilter = cachedSwipeFilter
                } else {
                    swipeFilter = try await FirebaseAuthService.shared.fetchSwipeFilterState(preferServer: preferServerSwipeData)
                    await MainActor.run {
                        cachedSwipeFilter = swipeFilter
                    }
                }
                
                guard let currentUser = appState.currentUser else {
                    await MainActor.run {
                        hasCompletedDiscoverLoad = false
                        isLoading = false
                        isLoadingMoreProfiles = false
                    }
                    return
                }
                
                let blockedUserIds = Set(appState.blockedUsers.map(\.id))
                var collectedProfiles: [ProfileCard] = []
                var cursor = append ? lastFetchedUserDocumentId : nil
                var hasMore = true
                var seenUserIds = Set(profiles.map(\.userId))
                let minimumProfiles = DiscoverConstants.profilesPerBatch
                
                while hasMore && collectedProfiles.count < minimumProfiles {
                    let page = try await FirebaseAuthService.shared.fetchUsersPage(
                        limit: DiscoverConstants.firestorePageSize,
                        startAfterDocumentId: cursor
                    )
                    
                    cursor = page.lastDocumentId
                    hasMore = page.hasMore
                    
                    let eligibleUsers = page.users.filter { user in
                        let userId = user.firebaseDocumentId ?? user.id.uuidString
                        guard !seenUserIds.contains(userId) else { return false }
                        
                        let isEligible = isUserEligibleForDeck(
                            user: user,
                            currentUser: currentUser,
                            likedUserIds: swipeFilter.likedUserIds,
                            passedUserIds: swipeFilter.passedUserIds,
                            blockedUserIds: blockedUserIds,
                            ignorePassedFilter: ignorePassedFilter
                        )
                        
                        if isEligible {
                            seenUserIds.insert(userId)
                        }
                        
                        return isEligible
                    }
                    
                    collectedProfiles.append(contentsOf: eligibleUsers.map { makeProfileCard(from: $0, currentUser: currentUser) })
                }
                
                let sortedProfiles = sortProfilesByMatchPercentage(collectedProfiles)
                
                await MainActor.run {
                    lastFetchedUserDocumentId = cursor
                    hasMoreRemoteUsers = hasMore
                    
                    if append {
                        profiles.append(contentsOf: sortedProfiles)
                        hasMoreUsersToLoad = hasMoreRemoteUsers || !pendingDiscoverProfiles.isEmpty
                        isLoadingMoreProfiles = false
                        print("✅ SearchView: Loaded \(sortedProfiles.count) more profiles (total: \(profiles.count))")
                    } else {
                        profiles = Array(sortedProfiles.prefix(DiscoverConstants.profilesPerBatch))
                        pendingDiscoverProfiles = Array(sortedProfiles.dropFirst(DiscoverConstants.profilesPerBatch))
                        hasMoreUsersToLoad = hasMoreRemoteUsers || !pendingDiscoverProfiles.isEmpty
                        print("✅ SearchView: Loaded initial \(profiles.count) profiles, \(pendingDiscoverProfiles.count) queued by match %")
                        markDiscoverLoadCompleted()
                        
                        if profiles.isEmpty && !hasMoreUsersToLoad {
                            loadMatchesAndMessagesCount()
                        }
                    }
                    
                    syncDiscoverCache()
                }
            } catch {
                print("❌ SearchView: Error loading users: \(error.localizedDescription)")
                await MainActor.run {
                    if !append {
                        profiles = []
                        pendingDiscoverProfiles = []
                        hasCompletedDiscoverLoad = false
                    }
                    isLoading = false
                    isLoadingMoreProfiles = false
                }
            }
        }
    }
    
    private func prefetchMoreProfilesIfNeeded() {
        let remainingCards = profiles.count - currentCardIndex
        // When the user reaches the 7th card of a 10-card batch, remaining == 4.
        guard remainingCards <= DiscoverConstants.prefetchRemainingThreshold,
              hasMoreUsersToLoad,
              !isLoadingMoreProfiles,
              !isLoading else { return }
        
        print("🔍 SearchView: Prefetching next \(DiscoverConstants.profilesPerBatch) profiles (at card \(currentCardIndex + 1), \(remainingCards) remaining)")
        loadDiscoverProfiles(append: true)
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
        // Advance the deck immediately — never wait on network for the next-card animation.
        print("✅ Liked: \(profile.name)")
        moveToNextCard()
        
        Task {
            do {
                try await FirebaseAuthService.shared.recordSwipe(to: profile.userId, action: .like)
                
                guard let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid else { return }
                
                let matchId = FirebaseAuthService.shared.matchDocumentId(
                    for: currentUserId,
                    and: profile.userId
                )
                
                var isMatch = try await FirebaseAuthService.shared.checkForMatch(with: profile.userId)
                
                if !isMatch {
                    // Cloud Function may create the match shortly after the swipe is saved.
                    // Poll briefly in the background — UI already advanced.
                    for _ in 0..<4 {
                        try await Task.sleep(nanoseconds: 500_000_000)
                        isMatch = try await FirebaseAuthService.shared.matchExists(with: profile.userId)
                        if isMatch { break }
                    }
                }
                
                if isMatch {
                    await MainActor.run {
                        print("💕 Match with \(profile.name)! Showing popup")
                        appState.presentMatchNotification(otherUser: profile, matchId: matchId)
                    }
                } else {
                    print("💕 Liked \(profile.name), but no match yet")
                }
            } catch {
                print("❌ Error handling swipe right: \(error)")
            }
        }
    }
    
    private func handleSwipeLeft(profile: ProfileCard) {
        // Advance the deck immediately — never wait on network for the next-card animation.
        print("❌ Passed: \(profile.name)")
        moveToNextCard()
        
        Task {
            do {
                try await FirebaseAuthService.shared.recordSwipe(to: profile.userId, action: .pass)
            } catch {
                print("❌ Error handling swipe left: \(error)")
            }
        }
    }
    
    private func moveToNextCard() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            currentCardIndex += 1
        }
        syncDiscoverCache()
        
        if currentCardIndex >= profiles.count && !profiles.isEmpty && !hasMoreUsersToLoad {
            loadMatchesAndMessagesCount()
        } else {
            prefetchMoreProfilesIfNeeded()
        }
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
                async let matchesTask = FirebaseAuthService.shared.fetchMatches()
                async let unreadCountTask = FirebaseAuthService.shared.countUnreadIncomingMessages()
                async let swipeFilterTask = FirebaseAuthService.shared.fetchSwipeFilterState(preferServer: true)

                let matches = try await matchesTask
                let unreadCount = try await unreadCountTask
                let swipeFilter = try await swipeFilterTask

                let reviewablePassedCount: Int
                if let currentUser = FirebaseAuthService.shared.currentUser {
                    let passedUsers = try await FirebaseAuthService.shared.fetchUsers(
                        byIds: Array(swipeFilter.passedUserIds)
                    )
                    let blockedUserIds = Set(appState.blockedUsers.map(\.id))
                    reviewablePassedCount = passedUsers.filter { user in
                        isUserEligibleForDeck(
                            user: user,
                            currentUser: currentUser,
                            likedUserIds: swipeFilter.likedUserIds,
                            passedUserIds: swipeFilter.passedUserIds,
                            blockedUserIds: blockedUserIds,
                            ignorePassedFilter: true,
                            requirePassedOnly: true
                        )
                    }.count
                } else {
                    reviewablePassedCount = 0
                }

                await MainActor.run {
                    matchesCount = matches.count
                    messagesCount = unreadCount
                    canReviewPassedProfiles = reviewablePassedCount > 0
                }
                
                print("📊 Loaded counts: \(matches.count) matches, \(unreadCount) unread messages, \(reviewablePassedCount) reviewable passed profiles")
            } catch {
                print("❌ Error loading matches/messages count: \(error)")
                await MainActor.run {
                    canReviewPassedProfiles = false
                }
            }
        }
    }

    private func resetUnlikedProfiles() {
        guard !isLoading, canReviewPassedProfiles else { return }
        isLoading = true
        hasCompletedDiscoverLoad = false
        appState.clearDiscoverProfilesCache()
        lastFetchedUserDocumentId = nil
        hasMoreUsersToLoad = true
        cachedSwipeFilter = nil
        pendingDiscoverProfiles = []

        Task {
            do {
                try await FirebaseAuthService.shared.resetPassSwipesToNew()
                await MainActor.run {
                    currentCardIndex = 0
                    profiles = []
                }
                loadDiscoverProfiles(ignorePassedFilter: true, preferServerSwipeData: true)
            } catch {
                print("❌ Error resetting passed profiles: \(error)")
                await MainActor.run {
                    isLoading = false
                }
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
    private let cardHeight: CGFloat = 500
    private let photoAreaHeight: CGFloat = 340
    
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .frame(width: cardWidth, height: cardHeight)
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
            
            VStack(spacing: 0) {
                // Immersive photo with identity overlays
                ZStack(alignment: .bottomLeading) {
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
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 80))
                                        .foregroundColor(.gray)
                                )
                        }
                    }
                    .frame(width: cardWidth, height: photoAreaHeight)
                    .clipped()
                    
                    // Soft top gradient so distance stays readable on bright photos
                    LinearGradient(
                        colors: [
                            .black.opacity(0.5),
                            .black.opacity(0.18),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 110)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    
                    // Soft bottom gradient for readable name / age
                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(0.15),
                            .black.opacity(0.55)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    
                    // Distance — top trailing
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 5) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(profile.distance)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .padding(.top, 14)
                            .padding(.trailing, 14)
                        }
                        Spacer()
                    }
                    
                    // Name, age, online — bottom of photo
                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(firstName(from: profile.name)), \(profile.age)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 1)
                            
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(profile.isOnline ? Color.green : Color.white.opacity(0.55))
                                    .frame(width: 8, height: 8)
                                Text(profile.isOnline ? "search.online.now".localized : "search.offline".localized)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.95))
                            }
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .frame(width: cardWidth, height: photoAreaHeight)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 24,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 24,
                        style: .continuous
                    )
                )
                
                // Bio + match — clean footer, no nested boxes
                VStack(alignment: .leading, spacing: 30) {
                    Text(profile.bio)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        let matchPercentage = profile.matchPercentage
                        let profileFirstName = firstName(from: profile.name)
                        let matchColor: Color = matchPercentage > 49 ? .green : .secondary
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 6)
                                Capsule()
                                    .fill(matchColor)
                                    .frame(
                                        width: geo.size.width * CGFloat(max(0, min(matchPercentage, 100))) / 100.0,
                                        height: 6
                                    )
                            }
                        }
                        .frame(height: 6)
                        
                        (Text("search.match.prefix".localized)
                         + Text(String(format: "search.match.percent.part".localized, matchPercentage))
                            .foregroundColor(matchColor)
                         + Text(String(format: "search.match.suffix".localized, profileFirstName)))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            
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
        .frame(width: cardWidth, height: cardHeight)
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

private struct BlueFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.28), lineWidth: 1.5)
            )
    }
}

private extension View {
    func blueFieldStyle() -> some View {
        modifier(BlueFieldStyle())
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
            return Color(hex: "#C9A000")
        case .fullySocialMode:
            return Color(hex: "#69c440")
        }
    }
}

struct UserProfileModal: View {
    let profile: ProfileCard
    let showsUnlikeOption: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var appState: AppStateManager
    @State private var showingPhotoViewer = false
    @State private var selectedPhotoIndex = 0
    @State private var refreshedProfile: ProfileCard?
    @State private var showingBlockConfirmation = false
    @State private var showingUnlikeConfirmation = false
    @State private var isProfileUnliked = false
    @State private var hasLoadedUnlikeState = false
    
    init(profile: ProfileCard, showsUnlikeOption: Bool = false) {
        self.profile = profile
        self.showsUnlikeOption = showsUnlikeOption
        print("🔍 UserProfileModal INIT called with profile: \(profile.name), userId: \(profile.userId), showsUnlikeOption: \(showsUnlikeOption)")
    }
    
    private var profileTitle: String {
        let name = displayProfile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "profile.title".localized : name
    }

    private var displayProfile: ProfileCard {
        refreshedProfile ?? profile
    }
    
    /// Always compute against the logged-in user so Matches (which used to omit %)
    /// shows the same value as Home cards.
    private var resolvedMatchPercentage: Int {
        if let currentUser = appState.currentUser {
            return ProfileCard.calculateMatchPercentage(
                interests: displayProfile.interests,
                age: displayProfile.age,
                gender: displayProfile.gender,
                currentUser: currentUser
            )
        }
        return displayProfile.matchPercentage
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
                    
                    // Match percentage (same as home card)
                    matchSection
                    
                    // Age Section
                    ageSection
                    
                    // Location Section
                    locationSection
                    
                    // Energy Level Section
                    energyLevelSection
                    
                    // Gender & Preferences Section
                    genderPreferencesSection
                    
                    // About Me Section
                    aboutMeSection
                    
                    // My Interests Section
                    myInterestsSection
                    
                    profileActionsSection
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(profileTitle)
                        .font(.headline)
                        .lineLimit(1)
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
            loadUnlikeStateIfNeeded()
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
        .alert("profile.block.confirm.title".localized, isPresented: $showingBlockConfirmation) {
            Button("common.cancel".localized, role: .cancel) {}
            Button("profile.block.confirm.action".localized, role: .destructive) {
                appState.blockUser(userId: displayProfile.userId, name: displayProfile.name)
            }
        } message: {
            Text(String(format: "profile.block.confirm.message".localized, firstName(from: displayProfile.name)))
        }
        .alert("profile.unlike.confirm.title".localized, isPresented: $showingUnlikeConfirmation) {
            Button("common.cancel".localized, role: .cancel) {}
            Button("profile.unlike.confirm.action".localized, role: .destructive) {
                isProfileUnliked = true
                appState.unlikeUser(userId: displayProfile.userId)
                dismiss()
            }
        } message: {
            Text("profile.unlike.confirm.message".localized)
        }
    }
    
    private var isProfileBlocked: Bool {
        appState.isUserBlocked(displayProfile.userId)
    }
    
    private var blockToggleBinding: Binding<Bool> {
        Binding(
            get: { isProfileBlocked },
            set: { newValue in
                if newValue {
                    showingBlockConfirmation = true
                } else {
                    appState.unblockUser(userId: displayProfile.userId)
                }
            }
        )
    }
    
    private var unlikeToggleBinding: Binding<Bool> {
        Binding(
            get: { isProfileUnliked },
            set: { newValue in
                if newValue {
                    showingUnlikeConfirmation = true
                } else {
                    isProfileUnliked = false
                    appState.relikeUser(userId: displayProfile.userId)
                }
            }
        )
    }
    
    private var profileActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.actions.title".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 0) {
                if showsUnlikeOption {
                    HStack {
                        Image(systemName: "heart.slash.circle.fill")
                            .foregroundColor(.pink)
                            .font(.title2)
                        Text(isProfileUnliked ? "profile.relike.title".localized : "profile.unlike.title".localized)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Spacer()
                        Toggle("", isOn: unlikeToggleBinding)
                            .scaleEffect(0.8, anchor: .trailing)
                            .frame(width: 46, height: 28, alignment: .trailing)
                    }
                    
                    Divider()
                        .padding(.vertical, 10)
                }
                
                HStack {
                    Image(systemName: "hand.raised.circle.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                    Text(isProfileBlocked ? "profile.unblock.title".localized : "profile.block.title".localized)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer()
                    Toggle("", isOn: blockToggleBinding)
                        .scaleEffect(0.8, anchor: .trailing)
                        .frame(width: 46, height: 28, alignment: .trailing)
                }
            }
            .blueFieldStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private func loadUnlikeStateIfNeeded() {
        guard showsUnlikeOption else { return }
        
        // Prefer cached match presence for a fast initial value.
        let isMatch = appState.cachedMatches.contains { $0.otherUser.userId == displayProfile.userId }
        if isMatch {
            isProfileUnliked = false
            hasLoadedUnlikeState = true
        }
        
        Task {
            do {
                let swipeFilter = try await FirebaseAuthService.shared.fetchSwipeFilterState()
                await MainActor.run {
                    // Latest pass wins; otherwise keep matched/liked as not unliked.
                    isProfileUnliked = swipeFilter.passedUserIds.contains(displayProfile.userId)
                    hasLoadedUnlikeState = true
                }
            } catch {
                await MainActor.run {
                    if !hasLoadedUnlikeState {
                        isProfileUnliked = !isMatch
                        hasLoadedUnlikeState = true
                    }
                }
            }
        }
    }
    
    private func firstName(from fullName: String) -> String {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return components.first.map(String.init) ?? fullName
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
            
            // Keep the original distance from the profile card (already calculated).
            // Recalculate match % from the latest current user + refreshed profile data.
            let matchPercentage: Int
            if let currentUser = appState.currentUser {
                matchPercentage = ProfileCard.calculateMatchPercentage(
                    interests: refreshed.interests,
                    age: refreshed.age,
                    gender: refreshed.gender,
                    currentUser: currentUser
                )
            } else {
                matchPercentage = refreshed.matchPercentage
            }
            
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
                sensoryPreferences: refreshed.sensoryPreferences,
                shareSensoryPreferences: refreshed.shareSensoryPreferences,
                energyLevel: refreshed.energyLevel,
                matchPercentage: matchPercentage
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
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.edit.profile.photo".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            ProfileMainPhotoCard(
                imageURL: displayProfile.imageURL,
                onTap: {
                    let hasProfilePhoto = displayProfile.imageURL != nil && !(displayProfile.imageURL?.isEmpty ?? true)
                    let hasGalleryPhotos = !displayProfile.photos.isEmpty
                    if hasProfilePhoto || hasGalleryPhotos {
                        selectedPhotoIndex = 0
                        showingPhotoViewer = true
                    }
                }
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ProfilePhotoStyle.cardCorner, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }
    
    // MARK: - Age Section
    private var ageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.age".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("\(displayProfile.age) " + "profile.years.old".localized)
                .font(.subheadline)
                .blueFieldStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Location Section
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.location".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(displayProfile.distance)
                .font(.subheadline)
                .blueFieldStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Energy Level Section
    private var energyLevelSection: some View {
        let energyOption = EnergyLevelOption(rawValue: displayProfile.energyLevel) ?? .fullySocialMode
        let levelColor = energyOption.color
        let levelBinding = Binding<Int>(
            get: { displayProfile.energyLevel },
            set: { _ in }
        )
        
        return VStack(alignment: .leading, spacing: 14) {
            Text("profile.edit.energy.level".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(energyOption.title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(levelColor)
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
                energyLevel: levelBinding,
                levelColor: levelColor,
                isEnabled: false
            )
            .frame(height: 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - About Me Section
    private var aboutMeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("profile.about.me".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(displayProfile.bio.isEmpty ? "profile.no.bio".localized : displayProfile.bio)
                .font(.body)
                .foregroundColor(displayProfile.bio.isEmpty ? .secondary : .primary)
                .multilineTextAlignment(.leading)
                .blueFieldStyle()
            
            if displayProfile.shareLifestyle {
                Text("profile.lifestyle.title".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(formattedLifestyle(displayProfile.lifestyle))
                    .font(.body)
                    .foregroundColor(.primary)
                    .blueFieldStyle()
            }
            
            if displayProfile.shareBodyType, !displayProfile.bodyType.isEmpty {
                Text("profile.body.type".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(formattedBodyType(displayProfile.bodyType))
                    .font(.body)
                    .foregroundColor(.primary)
                    .blueFieldStyle()
            }
            
            if displayProfile.shareIdealFirstDate, !displayProfile.idealFirstDate.isEmpty {
                Text("profile.ideal.first.date".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(formattedIdealFirstDate(displayProfile.idealFirstDate))
                    .font(.body)
                    .foregroundColor(.primary)
                    .blueFieldStyle()
            }
            
            if displayProfile.shareSensoryPreferences, !displayProfile.sensoryPreferences.isEmpty {
                Text("profile.sensory.preferences".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(SensoryPreferenceOption.formattedTitles(displayProfile.sensoryPreferences))
                    .font(.body)
                    .foregroundColor(.primary)
                    .blueFieldStyle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - My Interests Section
    private var myInterestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("profile.my.interests".localized)
                .font(.headline)
                .fontWeight(.semibold)
            
            if displayProfile.interests.isEmpty {
                Text("profile.no.interests".localized)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .blueFieldStyle()
            } else {
                Text(displayProfile.interests.map { localizedInterest($0) }.joined(separator: ", "))
                    .font(.body)
                    .foregroundColor(.primary)
                    .blueFieldStyle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
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
                .blueFieldStyle()
            } else {
                Text("profile.no.preferences".localized)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
                    .blueFieldStyle()
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
        ProfileGalleryPhotosCard(
            photoURLs: displayProfile.photos,
            allowsPaging: false,
            onSelectRemote: { index in
                selectedPhotoIndex = index + 1
                showingPhotoViewer = true
            },
            usesWhiteBackground: true
        )
    }
    
    private var matchSection: some View {
        let matchPercentage = resolvedMatchPercentage
        let profileFirstName = firstName(from: displayProfile.name)
        let matchColor: Color = matchPercentage > 49 ? .green : .secondary
        
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 6)
                    Capsule()
                        .fill(matchColor)
                        .frame(
                            width: geo.size.width * CGFloat(max(0, min(matchPercentage, 100))) / 100.0,
                            height: 6
                        )
                }
            }
            .frame(height: 6)
            
            (Text("search.match.prefix".localized)
             + Text(String(format: "search.match.percent.part".localized, matchPercentage))
                .foregroundColor(matchColor)
             + Text(String(format: "search.match.suffix".localized, profileFirstName)))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
        }
        .blueFieldStyle()
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
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
            
            // Done button
            VStack {
                HStack {
                    Spacer()
                    Button("common.done".localized) {
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundColor(.white)
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
    @EnvironmentObject private var appState: AppStateManager
    @State private var messageText: String = ""
    @State private var showingPreMessageOptions = false
    @State private var isBlockedByRecipient = false
    @State private var showingBlockedAlert = false
    
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
                        .disabled(isBlockedByRecipient)
                        .opacity(isBlockedByRecipient ? 0.5 : 1)
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
                        .disabled(isBlockedByRecipient)
                        .opacity(isBlockedByRecipient ? 0.5 : 1)
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
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBlockedByRecipient)
                .opacity(isBlockedByRecipient ? 0.5 : 1)
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.done".localized) {
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
        .overlay {
            if showingBlockedAlert {
                BlockedUserAlertOverlay(
                    firstName: firstName(from: profile.name),
                    onDismiss: { dontShowAgain in
                        if dontShowAgain {
                            appState.suppressBlockedAlert(for: profile.userId)
                        }
                        showingBlockedAlert = false
                    }
                )
            }
        }
        .onAppear {
            print("💬 NewMessageModal appeared for: \(profile.name)")
            print("💬 Profile userId: \(profile.userId), isExistingConversation: \(isExistingConversation)")
            print("💬 Modal appeared - messageText will be set: \(!isExistingConversation)")
            Task {
                await checkBlockStatus()
            }
        }
    }
    
    private func checkBlockStatus() async {
        do {
            let blocked = try await FirebaseAuthService.shared.isBlockedBy(userId: profile.userId)
            print("🚫 Block status for \(profile.userId): blocked=\(blocked)")
            await MainActor.run {
                isBlockedByRecipient = blocked
                if blocked {
                    messageText = ""
                    if appState.shouldShowBlockedAlert(for: profile.userId) {
                        showingBlockedAlert = true
                    }
                } else if !isExistingConversation {
                    messageText = "matches.default.message".localized
                    print("💬 Default message text set: \(messageText)")
                }
            }
        } catch {
            print("⚠️ Unable to check block status for \(profile.userId): \(error.localizedDescription)")
            await MainActor.run {
                if !isExistingConversation {
                    messageText = "matches.default.message".localized
                }
            }
        }
    }
    
    // Helper function to extract first name
    private func firstName(from fullName: String) -> String {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return components.first.map(String.init) ?? fullName
    }
    
    private func sendMessage() async {
        guard !isBlockedByRecipient else { return }
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        
        await MainActor.run {
            appState.recordOutgoingMessage(
                to: profile.userId,
                recipientName: profile.name,
                recipientPhotoURL: profile.imageURL,
                content: trimmedMessage
            )
        }
        
        do {
            let messageId = try await FirebaseAuthService.shared.sendMessage(
                to: profile.userId,
                content: trimmedMessage
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
    let canReviewPassedProfiles: Bool
    let onMatchesTap: () -> Void
    let onMessagesTap: () -> Void
    let onStartOverTap: () -> Void
    
    private let cardWidth = UIScreen.main.bounds.width - 60
    private let cardHeight: CGFloat = 500
    private let photoAreaHeight: CGFloat = 340
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .frame(width: cardWidth, height: cardHeight)
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
            
            VStack(spacing: 0) {
                // Immersive faded photo header — same proportions as discover cards
                ZStack {
                    Color.clear
                        .frame(width: cardWidth, height: photoAreaHeight)
                        .overlay {
                            Image("profile1")
                                .resizable()
                                .scaledToFill()
                                .opacity(0.1)
                        }
                        .clipped()
                    
                    VStack(spacing: 10) {
                        Text("search.empty.no.more.profiles.line1".localized)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text("search.empty.no.more.profiles.line2".localized)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                }
                .frame(width: cardWidth, height: photoAreaHeight)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 24,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 24,
                        style: .continuous
                    )
                )
                
                // Clean footer actions
                VStack(spacing: 12) {
                    emptyStateActionButton(
                        icon: "heart.fill",
                        label: Text("search.empty.matches.prefix".localized)
                            + Text(" \(matchesCount)")
                            + Text(" " + "search.empty.matches.suffix".localized),
                        action: onMatchesTap
                    )
                    
                    emptyStateActionButton(
                        icon: "message.fill",
                        label: Text("search.empty.messages.prefix".localized)
                            + Text(" \(messagesCount)")
                            + Text(" " + "search.empty.messages.suffix".localized),
                        action: onMessagesTap
                    )
                    
                    Button(action: onStartOverTap) {
                        Text("search.empty.start.over".localized)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(canReviewPassedProfiles ? .blue : .secondary.opacity(0.45))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canReviewPassedProfiles)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .frame(width: cardWidth, height: cardHeight)
    }
    
    private func emptyStateActionButton(
        icon: String,
        label: Text,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                label
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.blue)
            )
        }
        .buttonStyle(.plain)
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
