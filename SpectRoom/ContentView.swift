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
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingNewMessageModal = false
    @State private var messageRecipient: ProfileCard?
    
    private var isMatchPopupVisible: Bool {
        appState.showingMatchNotification && appState.newMatchProfile != nil
    }
    
    private var matchPopupDimmingOpacity: Double {
        colorScheme == .dark ? 0.55 : 0.45
    }
    
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
            
            if isMatchPopupVisible {
                Color.black.opacity(matchPopupDimmingOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isMatchPopupVisible)
        .sheet(isPresented: Binding(
            get: { isMatchPopupVisible },
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
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
                .presentationCornerRadius(24)
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var matchCount: Int = 0
    @State private var viewedMatches: Set<String> = []
    
    // UserDefaults keys for persisting viewed items
    private let viewedMatchesKey = "viewedMatches"
    
    // Computed property for display count (total matches minus viewed)
    private var displayMatchCount: Int {
        max(0, matchCount - viewedMatches.count)
    }
    
    private var displayUnreadMessageCount: Int {
        max(0, appState.unreadMessageCount)
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
                            Image(systemName: "message.fill")
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
                            .font(.system(size: 11))
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
                            Image(systemName: "heart.fill")
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
                            .font(.system(size: 11))
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
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                        Text("nav.profile".localized)
                            .font(.system(size: 11))
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
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20))
                        Text("nav.settings".localized)
                            .font(.system(size: 11))
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
                    Image(systemName: "house.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundColor(selectedTab == 2 ? .blue : .gray)
                        .floatingCircleButtonStyle(colorScheme: colorScheme)
                }
                .offset(y: -34) // Elevated to extend partially outside menu borders
                
                Spacer()
            }
            .zIndex(1) // Ensure Discover button is on top
        }
        .onAppear {
            loadViewedMatches()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appState.refreshUnreadMessageCount()
                loadMatchCount()
            }
        }
        .onReceive(appState.newMessageReceivedPublisher) { _ in
            appState.refreshUnreadMessageCount()
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == 0 && appState.isAuthenticated {
                appState.refreshUnreadMessageCount()
            }
            if newTab == 1 && appState.isAuthenticated {
                loadMatchCount()
            }
        }
        .onChange(of: appState.currentlyOpenConversationSenderId) { _ in
            if appState.isAuthenticated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    appState.refreshUnreadMessageCount()
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
            UserDefaults.standard.removeObject(forKey: viewedMatchesKey)
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
}

// Extension for rounded corners on specific sides
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
    
    func floatingCircleButtonStyle(colorScheme: ColorScheme, size: CGFloat = 60) -> some View {
        let shadowColor = colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.2)
        return frame(width: size, height: size)
            .background(Color(.systemBackground))
            .clipShape(Circle())
            .shadow(color: shadowColor, radius: 8, x: 0, y: 4)
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
