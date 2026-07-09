//
//  MatchesView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import Foundation

struct MatchesView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) var colorScheme
    @State private var matches: [MatchDisplay] = []
    @State private var isLoading = true
    @State private var showingProfileModal = false
    @State private var selectedProfile: ProfileCard?
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    loadingView
                } else if matches.isEmpty {
                    emptyMatchesView
                } else {
                    matchesList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("matches.title".localized)
                        .font(.system(size: 28, weight: .bold))
                }
            }
        }
        .navigationViewStyle(.stack)
        .onReceive(appState.$cachedMatches) { updatedMatches in
            matches = updatedMatches
            isLoading = false
        }
        .onAppear {
            loadMatches()
        }
        .sheet(isPresented: Binding(
            get: { 
                let isPresented = showingProfileModal
                print("🔍 MatchesView Sheet binding GET - isPresented: \(isPresented), selectedProfile: \(selectedProfile?.name ?? "nil")")
                return isPresented
            },
            set: { newValue in
                print("🔍 MatchesView Sheet binding SET - newValue: \(newValue), current showingProfileModal: \(showingProfileModal)")
                print("🔍 selectedProfile at set time: \(selectedProfile?.name ?? "nil"), userId: \(selectedProfile?.userId ?? "nil")")
                showingProfileModal = newValue
                print("🔍 showingProfileModal after set: \(showingProfileModal)")
            }
        )) {
            let _ = print("🔍 MatchesView Sheet closure EXECUTING - selectedProfile: \(selectedProfile?.name ?? "nil")")
            if let profile = selectedProfile {
                let _ = print("🔍 MatchesView Creating UserProfileModal with profile: \(profile.name), userId: \(profile.userId), age: \(profile.age)")
                UserProfileModal(profile: profile)
                    .environmentObject(appState)
            } else {
                let _ = print("❌ MatchesView selectedProfile is nil in sheet closure!")
                VStack {
                    Text("matches.error.no.profile".localized)
                        .foregroundColor(.red)
                    Button("common.close".localized) {
                        showingProfileModal = false
                    }
                }
            }
        }
    }
    
    private func loadMatches() {
        if matches.isEmpty {
            isLoading = true
        }
        Task {
            do {
                let cached = try await appState.getCachedOrFreshMatches()
                await MainActor.run {
                    self.matches = cached
                    self.isLoading = false
                }
            } catch {
                print("❌ Error loading matches: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

private extension MatchesView {
    var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
            Text("matches.loading".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        )
    }

    var matchesList: some View {
        List(matches) { match in
            MatchRow(match: match, onTap: {
                print("🔍 Match row tapped for profile: \(match.otherUser.name)")
                print("🔍 Profile userId: \(match.otherUser.userId), age: \(match.otherUser.age)")
                print("🔍 Setting selectedProfile to: \(match.otherUser.name)")
                selectedProfile = match.otherUser
                appState.viewedMatchProfileId = match.otherUser.userId
                print("🔍 selectedProfile after set: \(selectedProfile?.name ?? "nil"), userId: \(selectedProfile?.userId ?? "nil")")
                print("🔍 showingProfileModal before: \(showingProfileModal)")
                showingProfileModal = true
                print("🔍 showingProfileModal after: \(showingProfileModal)")
            }, onMessage: {
                print("💬 Message button tapped for: \(match.otherUser.name)")
                let userId = match.otherUser.userId
                appState.viewedMatchProfileId = userId
                appState.conversationToOpenProfile = match.otherUser
                selectedTab = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    appState.conversationToOpenSenderId = userId
                    print("💬 Navigated to Messages and set conversationToOpenSenderId: \(userId)")
                }
            })
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
        .background(
            Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        )
    }
    
    var emptyMatchesView: some View {
        VStack {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "heart")
                    .font(.system(size: 80))
                    .foregroundColor(.gray.opacity(0.6))
                Text("matches.empty".localized)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Text("matches.empty.description".localized)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button(action: {
                    selectedTab = 2
                }) {
                    Text("matches.start.swiping".localized)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 30)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        )
    }
}

struct MatchRow: View {
    let match: MatchDisplay
    let onTap: () -> Void
    let onMessage: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile image with frame
            if let profilePhotoURL = match.otherUser.imageURL, !profilePhotoURL.isEmpty {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 50, height: 50)
                    .overlay(
                        CachedAsyncImage(url: URL(string: profilePhotoURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .overlay(
                                    Text(String(match.otherUser.name.prefix(1)).uppercased())
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                )
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(String(match.otherUser.name.prefix(1)).uppercased())
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            )
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(match.otherUser.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Text("\(match.otherUser.age) " + "profile.years.old".localized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer()
            
            // Message button
            Button(action: {
                print("💬 Message button action triggered")
                onMessage()
            }) {
                Text("matches.message.button".localized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(20)
            }
            .onTapGesture {
                print("💬 Message button tap gesture triggered")
                onMessage()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture {
            print("💬 Row tapped for profile view")
            onTap()
        }
    }
}

#Preview {
    MatchesView(selectedTab: .constant(0))
}

