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

    private let gridPadding: CGFloat = 5
    private let columnSpacing: CGFloat = -3
    private let rowSpacing: CGFloat = 5

    private var cardWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let availableWidth = screenWidth - (gridPadding * 2) - columnSpacing
        return floor(availableWidth / 2)
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.fixed(cardWidth), spacing: columnSpacing),
            GridItem(.fixed(cardWidth))
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            matchesHeader

            Group {
                if isLoading {
                    loadingView
                } else if matches.isEmpty {
                    emptyMatchesView
                } else {
                    matchesGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(colorsBackground)
        .onReceive(appState.$cachedMatches) { updatedMatches in
            matches = updatedMatches
            isLoading = false
        }
        .onAppear {
            loadMatches()
            appState.refreshBlockedByUsers()
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

    private func openProfile(for match: MatchDisplay) {
        print("🔍 Match card tapped for profile: \(match.otherUser.name)")
        selectedProfile = match.otherUser
        appState.viewedMatchProfileId = match.otherUser.userId
        showingProfileModal = true
    }

    private func openMessage(for match: MatchDisplay) {
        print("💬 Message button tapped for: \(match.otherUser.name)")
        let userId = match.otherUser.userId
        appState.viewedMatchProfileId = userId
        appState.conversationToOpenProfile = match.otherUser
        appState.conversationToOpenSenderId = userId
        selectedTab = 0
    }
}

private extension MatchesView {
    var colorsBackground: some View {
        Image(colorScheme == .dark ? "ColorsDark" : "Colors")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .ignoresSafeArea()
    }

    var matchesHeader: some View {
        HStack(spacing: 12) {
            Button {
                selectedTab = 2
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
            }

            Text("matches.title".localized)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

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
    }

    var matchesGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: rowSpacing) {
                ForEach(matches) { match in
                    MatchGridCard(
                        match: match,
                        cardWidth: cardWidth,
                        onTap: { openProfile(for: match) },
                        onMessage: { openMessage(for: match) }
                    )
                    .environmentObject(appState)
                }
            }
            .padding(gridPadding)
            .padding(.bottom, 84)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
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
    }
}

struct MatchGridCard: View {
    let match: MatchDisplay
    let cardWidth: CGFloat
    let onTap: () -> Void
    let onMessage: () -> Void
    @EnvironmentObject private var appState: AppStateManager

    private let photoInset: CGFloat = 8
    private let photoAspectRatio: CGFloat = 300 / 333

    private var profile: ProfileCard { match.otherUser }

    private var photoWidth: CGFloat {
        cardWidth - (photoInset * 2)
    }

    private var photoHeight: CGFloat {
        photoWidth * photoAspectRatio
    }

    private var displayDistance: String? {
        let distance = profile.distance
        guard !distance.isEmpty, distance != "Matched" else { return nil }
        return compactDistance(from: distance)
    }

    private func compactDistance(from distance: String) -> String {
        if let kmRange = distance.range(of: " km") {
            return String(distance[distance.startIndex..<kmRange.upperBound])
        }
        if let mRange = distance.range(of: " m") {
            return String(distance[distance.startIndex..<mRange.upperBound])
        }
        return distance
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: onTap) {
                ZStack {
                    profileImage
                        .frame(width: photoWidth, height: photoHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.9), lineWidth: 2)
                        )

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        HStack(alignment: .bottom) {
                            overlayBadge {
                                Text("\(firstName(from: profile.name)), \(profile.age)")
                                    .font(.system(size: 10, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }

                            Spacer(minLength: 4)

                            overlayBadge {
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(profile.isOnline ? Color.green : Color.red)
                                        .frame(width: 5, height: 5)
                                    Text(profile.isOnline ? "search.online.now".localized : "search.offline".localized)
                                        .font(.system(size: 10, weight: .bold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .frame(width: photoWidth, height: photoHeight)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, photoInset)
            .padding(.top, photoInset)

            VStack(spacing: 0) {
                HStack {
                    messageButton
                    Spacer()
                    if let displayDistance {
                        overlayBadge {
                            HStack(spacing: 3) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 9))
                                Text(displayDistance)
                                    .font(.system(size: 10, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: photoWidth, height: photoHeight)
            .padding(.horizontal, photoInset)
            .padding(.top, photoInset)
        }
        .frame(width: cardWidth, height: photoHeight + photoInset, alignment: .top)
        .overlay {
            if isBlockedMatch {
                BlockedProfileLabel(dimmed: false, slanted: false)
                    .allowsHitTesting(false)
            }
        }
    }

    private var isBlockedMatch: Bool {
        appState.isMessagingBlocked(with: profile.userId)
    }

    private var messageButton: some View {
        Button(action: onMessage) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.blue))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var profileImage: some View {
        if let profilePhotoURL = profile.imageURL, !profilePhotoURL.isEmpty {
            CachedAsyncImage(url: URL(string: profilePhotoURL)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                imagePlaceholder
            }
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: photoWidth, height: photoHeight)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.gray)
            )
    }

    private func overlayBadge<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.3))
            )
    }

    private func firstName(from fullName: String) -> String {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return components.first.map(String.init) ?? fullName
    }
}

#Preview {
    MatchesView(selectedTab: .constant(1))
        .environmentObject(AppStateManager.shared)
}
