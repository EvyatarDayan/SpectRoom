//
//  ContentView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import Foundation

struct ContentView: View {
    @State private var selectedTab = 2
    @EnvironmentObject var appState: AppStateManager
    @State private var showingNewMessageModal = false
    @State private var messageRecipient: ProfileCard?
    
    var body: some View {
        ZStack {
            // Content views based on selected tab
            Group {
                switch selectedTab {
                case 0:
                    MessagesView(selectedTab: $selectedTab)
                case 1:
                    MatchesView(selectedTab: $selectedTab)
                case 2:
                    SearchView(selectedTab: $selectedTab)
                case 3:
                    ProfileView()
                case 4:
                    SettingsView()
                default:
                    SearchView(selectedTab: $selectedTab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Custom footer menu
        VStack {
                Spacer()
                CustomFooterMenu(selectedTab: $selectedTab)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: Binding(
            get: { appState.showingMatchNotification && appState.newMatchProfile != nil },
            set: { if !$0 { appState.dismissMatchNotification() } }
        )) {
            if let matchProfile = appState.newMatchProfile {
                MatchModalView(
                    otherUser: matchProfile,
                    onSendMessage: {
                        appState.dismissMatchNotification()
                        messageRecipient = matchProfile
                        selectedTab = 0 // Navigate to Messages tab
                        showingNewMessageModal = true
                    },
                    onMaybeLater: {
                        appState.dismissMatchNotification()
                    }
                )
                .presentationBackground(.clear)
            }
        }
        .sheet(isPresented: $showingNewMessageModal) {
            if let recipient = messageRecipient {
                NewMessageModal(profile: recipient, isExistingConversation: false)
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.showingNewMessageNotification && !appState.newMessageSenderName.isEmpty },
            set: { if !$0 { appState.dismissNewMessageNotification() } }
        )) {
            NewMessageNotificationModal(
                senderName: appState.newMessageSenderName,
                senderProfilePhotoURL: appState.newMessageSenderPhotoURL,
                onOpen: {
                    appState.dismissNewMessageNotification()
                    let senderId = appState.newMessageSenderId
                    selectedTab = 0 // Navigate to Messages tab
                    // Wait for MessagesView to be ready before setting conversationToOpenSenderId
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        appState.conversationToOpenSenderId = senderId
                        print("💬 Set conversationToOpenSenderId to: \(senderId) after navigation delay")
                    }
                },
                onLater: {
                    appState.dismissNewMessageNotification()
                }
            )
            .presentationBackground(.clear)
        }
        .onChange(of: appState.shouldOpenMessageModal) { shouldOpen in
            print("💬 shouldOpenMessageModal changed to: \(shouldOpen)")
            print("💬 newMatchProfile: \(appState.newMatchProfile?.name ?? "nil")")
            
            if shouldOpen && appState.newMatchProfile != nil {
                print("💬 Opening message modal for: \(appState.newMatchProfile?.name ?? "unknown")")
                // Handle the "Send a message" action from the global match notification
                messageRecipient = appState.newMatchProfile
                selectedTab = 0 // Navigate to Messages tab
                showingNewMessageModal = true
                appState.dismissMatchNotification()
            }
        }
    }
}

struct CustomFooterMenu: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var appState: AppStateManager
    @State private var unreadMessageCount: Int = 0
    @State private var matchCount: Int = 0
    @State private var viewedMatches: Set<String> = []
    @State private var viewedConversations: Set<String> = [] // Track which conversations have been viewed
    
    // UserDefaults keys for persisting viewed items
    private let viewedMatchesKey = "viewedMatches"
    private let viewedConversationsKey = "viewedConversations"
    
    // Computed property for display count (total matches minus viewed)
    private var displayMatchCount: Int {
        max(0, matchCount - viewedMatches.count)
    }
    
    // Computed property for display count (total unread messages)
    // When conversations are viewed, we track them and the badge will be updated via Firebase refresh
    // This computed property ensures the badge doesn't show negative numbers
    private var displayUnreadMessageCount: Int {
        max(0, unreadMessageCount)
    }
    
    // Load viewed matches from UserDefaults
    private func loadViewedMatches() {
        if let data = UserDefaults.standard.data(forKey: viewedMatchesKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            viewedMatches = decoded
        }
    }
    
    // Save viewed matches to UserDefaults
    private func saveViewedMatches() {
        if let encoded = try? JSONEncoder().encode(viewedMatches) {
            UserDefaults.standard.set(encoded, forKey: viewedMatchesKey)
        }
    }
    
    // Load viewed conversations from UserDefaults
    private func loadViewedConversations() {
        if let data = UserDefaults.standard.data(forKey: viewedConversationsKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            viewedConversations = decoded
        }
    }
    
    // Save viewed conversations to UserDefaults
    private func saveViewedConversations() {
        if let encoded = try? JSONEncoder().encode(viewedConversations) {
            UserDefaults.standard.set(encoded, forKey: viewedConversationsKey)
        }
    }
    
    var body: some View {
        ZStack {
            // Background and other buttons
            HStack(spacing: 0) {
                // Messages button
                Button(action: {
                    selectedTab = 0
                }) {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "message")
                                .font(.system(size: 20))
                                .foregroundColor(selectedTab == 0 ? .blue : .gray)
                            
                            // Badge for unread messages - positioned on the icon
                            if displayUnreadMessageCount > 0 {
                                Text("\(displayUnreadMessageCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(3)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .offset(x: 6, y: -6)
                            }
                        }
                        
                        Text("nav.messages".localized)
                            .font(.system(size: 10))
                            .foregroundColor(selectedTab == 0 ? .blue : .gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                }
                
                // Matches button
                Button(action: {
                    selectedTab = 1
                }) {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "heart")
                                .font(.system(size: 20))
                                .foregroundColor(selectedTab == 1 ? .blue : .gray)
                            
                            // Badge for unviewed matches - positioned on the icon
                            if displayMatchCount > 0 {
                                Text("\(displayMatchCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(3)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .offset(x: 6, y: -6)
                            }
                        }
                        
                        Text("nav.matches".localized)
                            .font(.system(size: 10))
                            .foregroundColor(selectedTab == 1 ? .blue : .gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                }
                
                // Spacer for Discover button position
                Spacer()
                    .frame(width: 64) // Space for Discover button
                
                // Profile button
                Button(action: {
                    selectedTab = 3
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: "person")
                            .font(.system(size: 20))
                        Text("nav.profile".localized)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(selectedTab == 3 ? .blue : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                }
                
                // Settings button
                Button(action: {
                    selectedTab = 4
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20))
                        Text("nav.settings".localized)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(selectedTab == 4 ? .blue : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 18)
            .background(Color(.systemBackground))
            .cornerRadius(15, corners: [.topLeft, .topRight])
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
            
            // Discover button (elevated on top of everything)
            HStack {
                Spacer()
                
                Button(action: {
                    selectedTab = 2
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 25))
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.green)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .offset(y: -34) // Elevated to extend partially outside menu borders
                
                Spacer()
            }
            .zIndex(1) // Ensure Discover button is on top
        }
        .onAppear {
            // Load persisted viewed matches and conversations
            loadViewedMatches()
            loadViewedConversations()
            // Delay slightly to ensure view is fully initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                loadUnreadMessageCount()
                loadMatchCount()
            }
        }
        .onChange(of: appState.showingNewMessageNotification) { newValue in
            // Refresh count when new message notification appears
            if newValue {
                loadUnreadMessageCount()
            }
        }
        .onChange(of: selectedTab) { newTab in
            // Refresh count when switching to messages tab (to clear badge after reading)
            if newTab == 0 && appState.isAuthenticated {
                loadUnreadMessageCount()
            }
            // When switching to matches tab, refresh match count
            if newTab == 1 && appState.isAuthenticated {
                loadMatchCount()
            }
        }
        .onChange(of: appState.currentlyOpenConversationSenderId) { newValue in
            if appState.isAuthenticated {
                if let userId = newValue {
                    // Conversation opened - mark as viewed (same logic as matches)
                    if !viewedConversations.contains(userId) {
                        viewedConversations.insert(userId)
                        saveViewedConversations() // Persist to UserDefaults
                        print("💬 ContentView: Marked conversation with user \(userId) as viewed")
                        
                        // Count unread messages from this user and subtract from badge immediately
                        Task {
                            do {
                                let unreadFromUser = try await FirebaseAuthService.shared.countUnreadMessagesFromUser(userId)
                                await MainActor.run {
                                    if unreadFromUser > 0 {
                                        unreadMessageCount = max(0, unreadMessageCount - unreadFromUser)
                                        print("💬 ContentView: Subtracted \(unreadFromUser) unread messages from badge. New count: \(unreadMessageCount)")
                                    }
                                }
                            } catch {
                                print("⚠️ Could not count unread messages from user: \(error)")
                                // Fallback: subtract 1 optimistically
                                await MainActor.run {
                                    if unreadMessageCount > 0 {
                                        unreadMessageCount = max(0, unreadMessageCount - 1)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Refresh count from Firebase after a delay to get accurate count
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        loadUnreadMessageCount()
                    }
                } else {
                    // Conversation closed - refresh count after a small delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        loadUnreadMessageCount()
                    }
                }
            }
        }
        .onChange(of: appState.viewedMatchProfileId) { matchId in
            // When a match profile is viewed, mark it as viewed and update count
            if let matchId = matchId, !viewedMatches.contains(matchId) {
                viewedMatches.insert(matchId)
                saveViewedMatches() // Persist to UserDefaults
                // Reset after processing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    appState.viewedMatchProfileId = nil
                }
            }
        }
        .onChange(of: appState.showingMatchNotification) { isShowing in
            // When a new match notification appears or is dismissed, refresh match count
            if appState.isAuthenticated {
                if isShowing {
                    // Match popup appeared - refresh count after a delay to ensure match is saved
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        loadMatchCount()
                    }
                } else {
                    // Match popup dismissed ("Maybe later" or "Send a message") - refresh count immediately
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        loadMatchCount()
                    }
                }
            }
        }
    }
    
    private func loadMatchCount() {
        // Only fetch if user is authenticated
        guard appState.isAuthenticated else {
            matchCount = 0
            viewedMatches = []
            viewedConversations = []
            // Clear persisted viewed matches and conversations on sign out
            UserDefaults.standard.removeObject(forKey: viewedMatchesKey)
            UserDefaults.standard.removeObject(forKey: viewedConversationsKey)
            return
        }
        
        Task {
            do {
                let count = try await FirebaseAuthService.shared.countMatches()
                await MainActor.run {
                    matchCount = count
                }
            } catch {
                print("❌ Error loading match count: \(error)")
                await MainActor.run {
                    matchCount = 0
                }
            }
        }
    }
    
    private func loadUnreadMessageCount() {
        // Only fetch if user is authenticated
        guard appState.isAuthenticated else {
            unreadMessageCount = 0
            return
        }
        
        Task {
            do {
                let count = try await FirebaseAuthService.shared.countUnreadIncomingMessages()
                await MainActor.run {
                    unreadMessageCount = count
                }
            } catch {
                print("❌ Error loading unread message count: \(error)")
                await MainActor.run {
                    unreadMessageCount = 0
                }
            }
        }
    }
}

// Extension for rounded corners on specific sides
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    ContentView()
}
