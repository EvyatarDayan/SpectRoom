//
//  MessagesView.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import SwiftUI
import PhotosUI
import UIKit
import Photos
import Foundation
import AVFoundation

struct MessagesView: View {
    @EnvironmentObject var appState: AppStateManager
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedTab: Int
    @State private var conversations: [MessageDisplay] = []
    @State private var isLoading = true
    @State private var showingMessageModal = false
    @State private var selectedMessage: MessageDisplay?
    @State private var conversationMessages: [MessageDisplay] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isLoading {
                    VStack(spacing: 20) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("messages.loading".localized)
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
                } else if conversations.isEmpty {
                    VStack {
                        Spacer()
                        VStack(spacing: 20) {
                            Image(systemName: "message")
                                .font(.system(size: 80))
                                .foregroundColor(.gray.opacity(0.6))
                            Text("messages.empty".localized)
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            Text("messages.empty.description".localized)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            
                            // Action button
                            Button(action: {
                                selectedTab = 2 // Navigate to Discover tab
                            }) {
                                Text("messages.start.swiping".localized)
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
                } else {
                    List(conversations) { conversation in
                        let _ = print("💬 List: Rendering conversation with ID: \(conversation.id), recipient: \(conversation.recipientName)")
                        ConversationRow(conversation: conversation) {
                            handleConversationTap(conversation)
                        }
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
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("messages.title".localized)
                        .font(.system(size: 28, weight: .bold))
                }
            }
        }
        .navigationViewStyle(.stack)
        .onReceive(appState.$cachedMessageConversations) { updatedConversations in
            let sorted = sortedConversations(updatedConversations)
            conversations = sorted
            if isLoading {
                isLoading = false
            }
        }
        .onReceive(appState.newMessageReceivedPublisher) { conversation in
            let sorted = sortedConversations(appState.cachedMessageConversations)
            conversations = sorted
        }
        .onAppear {
            loadConversationsFromCache()
            // If we have a conversation to open and we're just appearing, try to open it
            if let senderId = appState.conversationToOpenSenderId, !senderId.isEmpty {
                print("💬 MessagesView appeared with conversationToOpenSenderId: \(senderId)")
                // Wait for conversations to load, then open
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if self.appState.conversationToOpenSenderId == senderId {
                    self.openConversationForSender(senderId: senderId)
                    }
                }
            }
        }
        .onChange(of: appState.conversationToOpenSenderId) { senderId in
            print("💬 conversationToOpenSenderId changed to: \(senderId ?? "nil")")
            if let senderId = senderId, !senderId.isEmpty {
                print("💬 Opening conversation for sender: \(senderId)")
                // First ensure conversations are loaded
                if conversations.isEmpty {
                    print("💬 Conversations list is empty, loading first...")
                loadConversations()
                }
                // Wait a bit longer to ensure conversations are loaded
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if self.appState.conversationToOpenSenderId == senderId {
                        print("💬 Attempting to open conversation for: \(senderId)")
                        self.openConversationForSender(senderId: senderId)
                    }
                }
            }
        }
        .onChange(of: conversations.count) { count in
            // If we have a conversation to open and conversations just loaded, try to open it
            if let senderId = appState.conversationToOpenSenderId, !senderId.isEmpty, count > 0 {
                print("💬 Conversations loaded (\(count) items), checking if we can open conversation for: \(senderId)")
                // Small delay to ensure conversations array is fully populated
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if self.appState.conversationToOpenSenderId == senderId {
                        print("💬 Opening conversation after conversations loaded")
                        self.openConversationForSender(senderId: senderId)
                    }
                }
            }
        }
        .onChange(of: isLoading) { loading in
            // When loading finishes, check if we need to open a conversation
            if !loading, let senderId = appState.conversationToOpenSenderId, !senderId.isEmpty, !conversations.isEmpty {
                print("💬 Loading finished with \(conversations.count) conversations, checking if we can open conversation for: \(senderId)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if self.appState.conversationToOpenSenderId == senderId {
                        print("💬 Attempting to open conversation after loading finished")
                        self.openConversationForSender(senderId: senderId)
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { 
                let isPresented = showingMessageModal
                print("💬 MessagesView Sheet binding GET - isPresented: \(isPresented), selectedMessage: \(selectedMessage?.recipientName ?? "nil")")
                return isPresented
            },
            set: { newValue in
                print("💬 MessagesView Sheet binding SET - newValue: \(newValue), current showingMessageModal: \(showingMessageModal)")
                print("💬 selectedMessage at set time: \(selectedMessage?.recipientName ?? "nil"), content: \(selectedMessage?.content.prefix(20) ?? "nil")...")
                showingMessageModal = newValue
                
                // Track which conversation is currently open
                if newValue, let message = selectedMessage {
                    // Determine the other user's ID (the one we're conversing with)
                    let otherUserId = message.senderName == "You" ? message.recipientId : message.senderId
                    appState.currentlyOpenConversationSenderId = otherUserId
                    print("💬 Conversation opened with user: \(otherUserId)")
                    
                    // Mark messages as read when conversation opens
                    if message.senderName != "You" {
                        Task {
                            do {
                                print("💬 Marking messages as read from user: \(otherUserId)")
                                try await FirebaseAuthService.shared.markMessagesAsRead(from: otherUserId)
                                print("💬 Successfully marked messages as read from user: \(otherUserId)")
                            } catch {
                                print("❌ Failed to mark messages as read: \(error)")
                            }
                        }
                    }
                    
                    // Store in Firestore so Cloud Function can check if conversation is open
                    Task {
                        await updateConversationOpenState(userId: otherUserId, isOpen: true)
                    }
                } else {
                    // Conversation closed
                    let previousUserId = appState.currentlyOpenConversationSenderId
                    appState.currentlyOpenConversationSenderId = nil
                    print("💬 Conversation closed")
                    
                    // Clear from Firestore
                    if let userId = previousUserId {
                        Task {
                            await updateConversationOpenState(userId: userId, isOpen: false)
                        }
                    }
                    DispatchQueue.main.async {
                        self.loadConversations()
                    }
                }
                
                print("💬 showingMessageModal after set: \(showingMessageModal)")
            }
        )) {
            let _ = print("💬 MessagesView Sheet closure EXECUTING - selectedMessage: \(selectedMessage?.recipientName ?? "nil")")
            if let message = selectedMessage {
                let _ = print("💬 MessagesView Creating MessageConversationModal with message: \(message.recipientName), content: \(message.content.prefix(20))...")
                MessageConversationModal(
                    message: message,
                    conversationMessages: $conversationMessages
                )
                .interactiveDismissDisabled()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            } else {
                let _ = print("❌ MessagesView selectedMessage is nil in sheet closure!")
                VStack {
                    Text("messages.error.no.message".localized)
                        .foregroundColor(.red)
                    Button("common.close".localized) {
                        showingMessageModal = false
                    }
                }
            }
        }
    }
    
    // Update conversation open state in Firestore
    private func updateConversationOpenState(userId: String, isOpen: Bool) async {
        await updateConversationOpenStateInFirestore(userId: userId, isOpen: isOpen)
    }
    
    // Helper function to update conversation open state in Firestore
    private func updateConversationOpenStateInFirestore(userId: String, isOpen: Bool) async {
        guard let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid else {
            return
        }
        
        do {
            let state: [String: Any] = [
                "openConversationUserId": isOpen ? userId : NSNull(),
                "updatedAt": Date().timeIntervalSince1970
            ]
            try await FirebaseAuthService.shared.updateUserData(state)
            print("💬 Updated conversation open state in Firestore: \(isOpen ? "open with \(userId)" : "closed")")
        } catch {
            print("❌ Failed to update conversation open state: \(error)")
        }
    }
    
    private func loadConversationsFromCache() {
        print("💬 MessagesView: Loading conversations from cache...")
        print("💬 MessagesView: Current conversations count: \(conversations.count)")
        
        // Check if user is authenticated
        guard FirebaseAuthService.shared.isAuthenticated else {
            print("❌ MessagesView: User not authenticated, skipping conversations load")
            return
        }
        
        if conversations.isEmpty {
            print("💬 MessagesView: Conversations list empty, showing loading spinner")
            isLoading = true
        }
        
        // First, load from cache instantly if available
        Task {
            do {
                // Try to get cached conversations first (fast)
                let cachedOrFresh = try await appState.getCachedOrFreshConversations()
                
                await MainActor.run {
                    print("💬 MessagesView: Setting conversations from cache to \(cachedOrFresh.count) items")
                    conversations = sortedConversations(cachedOrFresh)
                    isLoading = false
                    print("💬 MessagesView: Conversations loaded from cache")
                }
                
                // Then refresh in background (slow, but updates cache)
                Task {
                    do {
                        let refreshed = try await appState.refreshMessageConversationsCache()
                        await MainActor.run {
                            // Only update if count changed or if we got more recent data
                            if refreshed.count != conversations.count {
                                print("💬 MessagesView: Refreshing conversations from \(conversations.count) to \(refreshed.count) items")
                                conversations = sortedConversations(refreshed)
                            } else {
                                // Check if any conversation was updated (newer timestamp)
                                var updated = false
                                for refreshedConv in refreshed {
                                    if let existingIndex = conversations.firstIndex(where: { conv in
                                        let otherUserId = conv.senderName == "You" ? conv.recipientId : conv.senderId
                                        let newOtherUserId = refreshedConv.senderName == "You" ? refreshedConv.recipientId : refreshedConv.senderId
                                        return otherUserId == newOtherUserId
                                    }) {
                                        if refreshedConv.createdAt > conversations[existingIndex].createdAt {
                                            conversations[existingIndex] = refreshedConv
                                            updated = true
                                        }
                                    }
                                }
                                if updated {
                                    print("💬 MessagesView: Updated conversations with newer messages")
                                    conversations = sortedConversations(conversations)
                                }
                            }
                        }
                    } catch {
                        print("❌ MessagesView: Error refreshing conversations: \(error)")
                    }
                }
            } catch {
                print("❌ MessagesView: Error loading conversations: \(error)")
                await MainActor.run {
                    conversations = []
                    isLoading = false
                }
            }
        }
    }
    
    private func loadConversations() {
        // Legacy function - now just calls the cache version
        loadConversationsFromCache()
    }
    
    private func sortedConversations(_ list: [MessageDisplay]) -> [MessageDisplay] {
        list.sorted { $0.createdAt > $1.createdAt }
    }
    
    private func handleConversationTap(_ conversation: MessageDisplay) {
        print("💬 Conversation tapped for: \(conversation.recipientName)")
        print("💬 Message content: \(conversation.content)")
        print("💬 Message senderId: \(conversation.senderId), recipientId: \(conversation.recipientId)")
        print("💬 Setting selectedMessage to conversation")
        selectedMessage = conversation
        
        // Determine the other user's ID (the one we're conversing with)
        let otherUserId = conversation.senderName == "You" ? conversation.recipientId : conversation.senderId
        appState.currentlyOpenConversationSenderId = otherUserId
        print("💬 Set currentlyOpenConversationSenderId to: \(otherUserId)")
        
        print("💬 selectedMessage after set: \(selectedMessage?.recipientName ?? "nil"), content: \(selectedMessage?.content.prefix(20) ?? "nil")...")
        print("💬 showingMessageModal before: \(showingMessageModal)")
        showingMessageModal = true
        print("💬 showingMessageModal after: \(showingMessageModal)")
    }
    
    private func openConversationForSender(senderId: String, retryCount: Int = 0) {
        print("💬 Opening conversation for sender: \(senderId) (retry: \(retryCount))")
        print("💬 Current conversations count: \(conversations.count)")
        print("💬 isLoading: \(isLoading)")
        print("💬 Conversation list: \(conversations.map { "\($0.recipientName) (sender: \($0.senderId), recipient: \($0.recipientId))" })")
        
        // If conversations are still loading and we haven't retried much, wait a bit
        if isLoading && retryCount < 3 {
            print("💬 Conversations still loading, will retry in 0.5 seconds (retry: \(retryCount + 1))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.appState.conversationToOpenSenderId == senderId {
                    self.openConversationForSender(senderId: senderId, retryCount: retryCount + 1)
                }
            }
            return
        }
        
        // Find the conversation with this sender
        // For incoming messages, senderId matches the sender
        // For sent messages, recipientId matches the sender
        if let conversation = conversations.first(where: { conv in
            // If message was sent by current user, check recipientId
            // If message was received from sender, check senderId
            let otherUserId = conv.senderName == "You" ? conv.recipientId : conv.senderId
            print("💬 Checking conversation: sender=\(conv.senderName), senderId=\(conv.senderId), recipientId=\(conv.recipientId), otherUserId=\(otherUserId), target=\(senderId)")
            return otherUserId == senderId
        }) {
            print("💬 ✅ Found conversation with sender: \(conversation.recipientName)")
            print("💬 Setting selectedMessage and showingMessageModal to true")
            // Set selectedMessage first
            selectedMessage = conversation
            print("💬 selectedMessage set: \(selectedMessage?.recipientName ?? "nil")")
            
                    // Set the currently open conversation ID to prevent notifications for this conversation
            appState.currentlyOpenConversationSenderId = senderId
                    print("💬 Set currentlyOpenConversationSenderId to: \(senderId)")
                    
            // Store in Firestore so Cloud Function can check if conversation is open
            Task {
                await updateConversationOpenState(userId: senderId, isOpen: true)
            }
            
            // Use a small delay to ensure SwiftUI has processed selectedMessage before opening modal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                print("💬 Opening message modal now - showingMessageModal: \(self.showingMessageModal)")
                print("💬 selectedMessage check: \(self.selectedMessage != nil ? "exists" : "nil")")
                if self.selectedMessage != nil {
                    // Force open the modal
                    self.showingMessageModal = true
                    print("💬 ✅ showingMessageModal set to: \(self.showingMessageModal)")
                    print("💬 ✅ Modal should now be visible")
                    // Clear the conversationToOpenSenderId after opening
                    self.appState.conversationToOpenSenderId = nil
                    // Clear the sender info from AppStateManager
                    self.appState.newMessageSenderName = ""
                    self.appState.newMessageSenderPhotoURL = nil
                    self.appState.newMessageSenderId = ""
                } else {
                    print("❌ selectedMessage is nil when trying to open modal - retrying...")
                    // Retry if selectedMessage is still nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        if self.selectedMessage != nil {
                            self.showingMessageModal = true
                            print("💬 ✅ Retry successful - showingMessageModal set to: \(self.showingMessageModal)")
                        } else {
                            print("❌ selectedMessage still nil after retry")
                        }
                    }
                }
            }
        } else if retryCount == 0 {
            // First attempt failed, try fetching directly from Firebase immediately
            print("💬 No conversation found in list, fetching directly from Firebase")
            Task {
                await fetchAndCreateConversationForSender(senderId: senderId)
            }
        } else if retryCount < 3 {
            print("💬 No conversation found with sender: \(senderId) - will retry (\(retryCount + 1)/3)")
            // Refresh conversations and retry
            loadConversations()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if self.appState.conversationToOpenSenderId == senderId {
                self.openConversationForSender(senderId: senderId, retryCount: retryCount + 1)
                }
            }
        } else {
            print("💬 Conversation not found after retries, clearing state")
            // Clear the conversationToOpenSenderId even if not found
            appState.conversationToOpenSenderId = nil
            // Clear the sender info from AppStateManager
            appState.newMessageSenderName = ""
            appState.newMessageSenderPhotoURL = nil
            appState.newMessageSenderId = ""
        }
    }
    
    private func fetchAndCreateConversationForSender(senderId: String) async {
        print("💬 Fetching latest message from sender: \(senderId)")
        do {
            // Fetch the latest message from this sender using FirebaseAuthService helper
            if let messageDisplay = try await FirebaseAuthService.shared.fetchLatestMessageFromSender(senderId: senderId) {
                await MainActor.run {
                    print("💬 Found and created MessageDisplay for sender: \(messageDisplay.senderName)")
                    print("💬 Setting selectedMessage and showingMessageModal to true")
                    // Set selectedMessage first
                    selectedMessage = messageDisplay
                    print("💬 selectedMessage set: \(selectedMessage?.recipientName ?? "nil")")
                    // Use a small delay to ensure SwiftUI has processed selectedMessage before opening modal
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        print("💬 Opening message modal now - showingMessageModal: \(self.showingMessageModal)")
                        if self.selectedMessage != nil {
                            // Set the currently open conversation ID to prevent notifications for this conversation
                            self.appState.currentlyOpenConversationSenderId = senderId
                            print("💬 Set currentlyOpenConversationSenderId to: \(senderId)")
                            
                            // Store in Firestore so Cloud Function can check if conversation is open
                            Task {
                                await self.updateConversationOpenState(userId: senderId, isOpen: true)
                            }
                            
                            self.showingMessageModal = true
                            print("💬 ✅ showingMessageModal set to: \(self.showingMessageModal)")
                            print("💬 ✅ Modal should now be visible")
                            // Clear the conversationToOpenSenderId
                            self.appState.conversationToOpenSenderId = nil
                            // Clear the sender info from AppStateManager
                            self.appState.newMessageSenderName = ""
                            self.appState.newMessageSenderPhotoURL = nil
                            self.appState.newMessageSenderId = ""
                        } else {
                            print("❌ selectedMessage is nil when trying to open modal - retrying...")
                            // Retry if selectedMessage is still nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                if self.selectedMessage != nil {
                                    self.showingMessageModal = true
                                    print("💬 ✅ Retry successful - showingMessageModal set to: \(self.showingMessageModal)")
                                } else {
                                    print("❌ selectedMessage still nil after retry")
                                }
                            }
                        }
                    }
                }
            } else {
                print("❌ No message found from sender: \(senderId)")
                await MainActor.run {
                    appState.conversationToOpenSenderId = nil
                    appState.newMessageSenderName = ""
                    appState.newMessageSenderPhotoURL = nil
                    appState.newMessageSenderId = ""
                }
            }
        } catch {
            print("❌ Error fetching message from sender: \(error)")
            await MainActor.run {
                appState.conversationToOpenSenderId = nil
                appState.newMessageSenderName = ""
                appState.newMessageSenderPhotoURL = nil
                appState.newMessageSenderId = ""
            }
        }
    }
}

struct ConversationRow: View {
    let conversation: MessageDisplay
    let onTap: () -> Void
    
    var body: some View {
        let _ = print("💬 ConversationRow: Rendering row for \(conversation.recipientName), content: \(conversation.content.prefix(20))...")
        HStack(spacing: 12) {
            // Profile image with frame
            if let profilePhotoURL = otherUserProfilePhotoURL, !profilePhotoURL.isEmpty {
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
                                    Text(String(otherUserName.prefix(1)).uppercased())
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
                                Text(String(otherUserName.prefix(1)).uppercased())
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
                HStack {
                    Text(otherUserName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(conversation.createdAt.timeAgoDisplay())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text(previewText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Show direction indicator
                    Image(systemName: conversation.senderName == "You" ? "paperplane.fill" : "envelope.fill")
                        .foregroundColor(conversation.senderName == "You" ? .blue : .green)
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    private var otherUserName: String {
        if conversation.senderName == "You" {
            return conversation.recipientName
        } else {
            return conversation.senderName
        }
    }
    
    private var otherUserProfilePhotoURL: String? {
        if conversation.senderName == "You" {
            return conversation.recipientProfilePhotoURL
        } else {
            return conversation.senderProfilePhotoURL
        }
    }
    
    private var previewText: String {
        switch conversation.messageType {
        case .image:
            return "messages.preview.photo".localized
        case .voice:
            if let duration = conversation.voiceDuration {
                return String(format: "messages.preview.voice.duration".localized, formattedDuration(duration))
            } else {
                return "messages.preview.voice".localized
            }
        default:
            return conversation.content
        }
    }
}

struct MessageConversationModal: View {
    let message: MessageDisplay
    @Binding var conversationMessages: [MessageDisplay]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var appState: AppStateManager
    
    // Helper function to update conversation open state in Firestore
    private func updateConversationOpenStateInFirestore(userId: String, isOpen: Bool) async {
        guard let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid else {
            return
        }
        
        do {
            let state: [String: Any] = [
                "openConversationUserId": isOpen ? userId : NSNull(),
                "updatedAt": Date().timeIntervalSince1970
            ]
            try await FirebaseAuthService.shared.updateUserData(state)
            print("💬 MessageConversationModal: Updated conversation open state in Firestore: \(isOpen ? "open with \(userId)" : "closed")")
        } catch {
            print("❌ MessageConversationModal: Failed to update conversation open state: \(error)")
        }
    }
    @FocusState private var isTextFieldFocused: Bool
    @State private var replyText: String = ""
    @State private var isSendingReply = false
    @State private var isLoadingMessages = true
    @State private var refreshTimer: Timer?
    @State private var currentUserProfilePhotoURL: String?
    @State private var otherUserProfilePhotoURL: String?
    @State private var hasMarkedAsRead = false
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isUploadingImage = false
    @State private var showingConversationPhotoViewer = false
    @State private var selectedPhotoIndex = 0
    @State private var previousMessageCount = 0
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioRecordingURL: URL?
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var isRecording = false
    @State private var showRecordingPreview = false
    @State private var isSendingVoice = false
    @State private var showingMicrophonePermissionAlert = false
    @State private var loadError = false
    @State private var showingPreMessageOptions = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var playbackTimer: Timer?
    @State private var tempFileURL: URL?
    @State private var pendingAutoPlay = false
    @State private var showElapsedTime = false
    
    init(message: MessageDisplay, conversationMessages: Binding<[MessageDisplay]>) {
        self.message = message
        self._conversationMessages = conversationMessages
        print("💬 MessageConversationModal INIT called with message: \(message.recipientName), content: \(message.content.prefix(20))...")
    }
    
    var conversationTitle: String {
        if message.senderName == "You" {
            return message.recipientName
        } else {
            return message.senderName
        }
    }
    
    var body: some View {
        let _ = print("💬 MessageConversationModal body being computed, message: \(message.recipientName), isLoadingMessages: \(isLoadingMessages)")
        NavigationView {
            ZStack {
                // Background image - render first to display immediately
                Image(colorScheme == .dark ? "ColorsDark" : "Colors")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                
            VStack(spacing: 0) {
                    // Fixed top spacer - this creates a non-scrollable buffer zone above messages
                    Color.clear
                        .frame(height: 120) // Status bar + navigation bar area + button area
                    
                if isLoadingMessages {
                    // Loading State
                    VStack(spacing: 20) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                            Text("messages.loading.conversation".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    // Messages List
                    if conversationMessages.isEmpty {
                        VStack(spacing: 20) {
                            Spacer()
                                Text("messages.no.messages.found".localized)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                    LazyVStack(spacing: 12) {
                                        ForEach(conversationMessages) { msg in
                                            MessageBubble(
                                                message: msg,
                                                currentUserProfilePhotoURL: currentUserProfilePhotoURL,
                                                otherUserProfilePhotoURL: otherUserProfilePhotoURL,
                                                conversationMessages: conversationMessages,
                                                showingConversationPhotoViewer: $showingConversationPhotoViewer,
                                                selectedPhotoIndex: $selectedPhotoIndex
                                            )
                                            .id(msg.id)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, 20) // Padding for messages list
                                    .padding(.bottom, 8) // Minimal space for input area
                            }
                                .scrollContentBackground(.hidden) // Ensure transparent background
                                .scrollIndicators(.hidden) // Hide scroll indicators for cleaner look
                            .onAppear {
                                // Add a small delay to ensure messages are rendered before scrolling
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    if let lastMessage = conversationMessages.last {
                                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                }
                            }
                            .onChange(of: conversationMessages.count) { _ in
                                if let lastMessage = conversationMessages.last {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Reply Input (only show when messages are loaded)
                if !isLoadingMessages {
                    HStack(spacing: 12) {
//                            // Text input field with rounded corners and light gray background
//                            TextField("messages.type.something".localized, text: $replyText)
//                                .focused($isTextFieldFocused)
//                            .disabled(isSendingReply)
//                                .padding(.horizontal, 16)
//                                .padding(.vertical, 12)
//                                .background(Color(.red))
//                                .cornerRadius(24)
                        
                            // Camera button
//                        Button(action: {
//                                showingImagePicker = true
//                            }) {
//                                Image(systemName: "camera")
//                                    .font(.system(size: 20))
//                                    .foregroundColor(Color(.systemGray))
//                                    .frame(width: 44, height: 44)
//                                    .background(Color(.systemGray6))
//                                    .clipShape(Circle())
//                            }
                            
                            // Microphone button with tap & hold recording
                            Circle()
                                .fill(Color(.clear))
                                .frame(width: 44, height: 44)
//                                .overlay(
//                                    Image(systemName: isRecording ? "mic.fill" : "mic")
//                                        .font(.system(size: 20))
//                                        .foregroundColor(isRecording ? .red : Color(.systemGray))
//                                )
                                .overlay(
                                    Circle()
                                        .stroke(isRecording ? Color.red.opacity(0.4) : Color.clear, lineWidth: 2)
                                )
                                .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 60, pressing: { pressing in
                                    if pressing {
                                        if !isRecording {
                                            startRecording()
                                        }
                                    } else {
                                        if isRecording {
                                            stopRecording()
                                        }
                                    }
                                }, perform: {})
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 80)
                        .background(Color.clear)
                     }
                }
             }
         }
         .navigationTitle(conversationTitle)
         .navigationBarTitleDisplayMode(.inline)
         .toolbarBackground(.hidden, for: .navigationBar)
         .toolbarColorScheme(.dark, for: .navigationBar)
         .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        refreshMessagesOnly()
                        // Restart the auto-refresh timer
                        stopAutoRefresh()
                        startAutoRefresh()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("common.done".localized) {
                    dismiss()
                }
            }
            
            // Keyboard toolbar with Send button
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(action: {
                    sendReply()
                }) {
                    if isSendingReply {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("messages.send".localized)
                            .fontWeight(.semibold)
                    }
                }
                .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingReply)
                .foregroundColor(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
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
                Spacer()
                Button("common.done".localized) {
                    dismiss()
                }
                .font(.headline)
                .foregroundColor(.blue)
                .padding(.horizontal, 14)
                .padding(.vertical, 2)
//                .background(.ultraThinMaterial)
//                .clipShape(Capsule())
//                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isLoadingMessages {
                messageComposer
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            print("💬 MessageConversationModal appeared for: \(conversationTitle)")
            print("💬 Message senderId: \(message.senderId), recipientId: \(message.recipientId)")
            print("💬 Modal appeared - conversationMessages count: \(conversationMessages.count)")
            
            // Determine the other user's ID
            let otherUserId = message.senderName == "You" ? message.recipientId : message.senderId
            
            // Set the currently open conversation ID immediately
            appState.currentlyOpenConversationSenderId = otherUserId
            print("💬 Set currentlyOpenConversationSenderId to: \(otherUserId) (from modal onAppear)")
            
            // Store in Firestore so Cloud Function can check if conversation is open
            Task {
                await updateConversationOpenStateInFirestore(userId: otherUserId, isOpen: true)
            }
            
            loadConversationMessages()
            startAutoRefresh()
        }
        .onDisappear {
            // Determine the other user's ID
            let otherUserId = message.senderName == "You" ? message.recipientId : message.senderId
            
            // Clear the currently open conversation ID
            appState.currentlyOpenConversationSenderId = nil
            print("💬 Cleared currentlyOpenConversationSenderId (from modal onDisappear)")
            
            // Clear from Firestore
            Task {
                await updateConversationOpenStateInFirestore(userId: otherUserId, isOpen: false)
            }
            
            stopAutoRefresh()
        }
        .sheet(isPresented: $showingImagePicker) {
            MessageImagePicker(selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { newImage in
            if let image = newImage {
                sendImageMessage(image: image)
            }
        }
        .sheet(isPresented: $showingConversationPhotoViewer) {
            let imageMessages = conversationMessages.filter { $0.messageType == .image }
            let imageURLs = imageMessages.map { $0.content }
            ConversationPhotoViewerModal(
                photos: imageURLs,
                selectedIndex: $selectedPhotoIndex,
                conversationMessages: conversationMessages
            )
        }
        .alert("Microphone Access Needed", isPresented: $showingMicrophonePermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please enable microphone access in Settings to record voice messages.")
        }
        .sheet(isPresented: $showingPreMessageOptions) {
            PreMessageOptionsModal(
                profileName: message.senderName == "You" ? message.recipientName : message.senderName,
                onSelect: { selectedMessage in
                    replyText = selectedMessage
                    showingPreMessageOptions = false
                    // Open keyboard after a short delay to ensure the text field is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isTextFieldFocused = true
                    }
                }
            )
        }
        .overlay {
            Group {
                if isRecording {
                    ZStack {
                        Color.black.opacity(0.8)
                            .ignoresSafeArea()
                        RecordingIndicatorView(durationText: formattedDuration(recordingDuration))
                            .padding(.vertical, 20)
                            .padding(.horizontal, 24)
                            .background(.ultraThinMaterial)
                            .cornerRadius(28)
                            .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                            .frame(maxWidth: 360)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale))
                } else if showRecordingPreview, let audioRecordingURL {
                    ZStack {
                        Color.black.opacity(0.8)
                            .ignoresSafeArea()
                            .transition(.opacity)
                        
                        RecordingPreviewView(
                            audioURL: audioRecordingURL,
                            duration: recordingDuration,
                            isSending: isSendingVoice,
                            onSend: {
                                sendVoiceMessage(audioURL: audioRecordingURL, duration: recordingDuration)
                            },
                            onDiscard: {
                                discardRecording()
                            }
                        )
                        .padding(.vertical, 20)
                        .padding(.horizontal, 24)
                        .background(.ultraThinMaterial)
                        .cornerRadius(28)
                        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                        .frame(maxWidth: 360)
                    }
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
    }
    
    private var messageComposer: some View {
        HStack(spacing: 12) {
            TextField("messages.type.something".localized, text: $replyText)
                .focused($isTextFieldFocused)
                .disabled(isSendingReply)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(24)
            
            Button(action: {
                showingImagePicker = true
            }) {
                Image(systemName: "camera")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            
            Circle()
                .fill(Color(.systemGray6))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 20))
                        .foregroundColor(isRecording ? .red : .blue)
                )
                .overlay(
                    Circle()
                        .stroke(isRecording ? Color.red.opacity(0.4) : Color.clear, lineWidth: 2)
                )
                .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 60, pressing: { pressing in
                    if pressing {
                        if !isRecording {
                            startRecording()
                        }
                    } else {
                        if isRecording {
                            stopRecording()
                        }
                    }
                }, perform: {})
        }
    }
    
    private func formattedDuration(_ time: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = time >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        return formatter.string(from: time) ?? "0:00"
    }
    
    private func loadConversationMessages() {
        print("💬 MessageConversationModal: Loading conversation messages for: \(message.content)")
        print("💬 MessageConversationModal: Current isLoadingMessages: \(isLoadingMessages)")
        print("💬 MessageConversationModal: Current conversationMessages count: \(conversationMessages.count)")
        
        // Determine the other user's ID
        let otherUserId: String
        if message.senderName == "You" {
            otherUserId = message.recipientId
        } else {
            otherUserId = message.senderId
        }
        
        print("💬 MessageConversationModal: Other user ID: \(otherUserId)")
        
        // Check cache first
        if let cachedMessages = appState.getCachedConversationMessages(for: otherUserId) {
            print("💬 MessageConversationModal: Using cached messages (\(cachedMessages.count) messages)")
            Task {
                // Mark messages as read when conversation first opens (only once)
                if !hasMarkedAsRead && message.senderName != "You" {
                    try? await FirebaseAuthService.shared.markMessagesAsRead(from: otherUserId)
                    await MainActor.run {
                        hasMarkedAsRead = true
                    }
                }
                
                await MainActor.run {
                    // Use cached messages immediately
                    conversationMessages = cachedMessages.sorted { $0.createdAt < $1.createdAt }
                    isLoadingMessages = false
                    previousMessageCount = conversationMessages.count
                    
                    // Fetch profile photos if needed
                    if currentUserProfilePhotoURL == nil || otherUserProfilePhotoURL == nil {
                        Task {
                            await fetchProfilePhotosIfNeeded(otherUserId: otherUserId)
                        }
                    }
                }
                
                // Refresh from DB in background to get any new messages
                await refreshConversationMessagesInBackground(otherUserId: otherUserId)
            }
            return
        }
        
        // No cache available, fetch from DB
        Task {
            do {
                // Mark messages as read when conversation first opens (only once)
                if !hasMarkedAsRead && message.senderName != "You" {
                    try await FirebaseAuthService.shared.markMessagesAsRead(from: otherUserId)
                    await MainActor.run {
                        hasMarkedAsRead = true
                    }
                }
                
                print("💬 MessageConversationModal: Calling fetchConversationMessages...")
                let messages = try await FirebaseAuthService.shared.fetchConversationMessages(with: otherUserId)
                print("💬 MessageConversationModal: Received \(messages.count) messages from Firebase")
                
                // Cache the messages
                appState.cacheConversationMessages(messages, for: otherUserId)
                
                // Fetch profile photos only once (not on every refresh)
                if currentUserProfilePhotoURL == nil || otherUserProfilePhotoURL == nil {
                    print("💬 MessageConversationModal: Fetching profile photos...")
                    await fetchProfilePhotosIfNeeded(otherUserId: otherUserId)
                }
                
                await MainActor.run {
                    // Ensure messages are sorted chronologically (oldest at top, newest at bottom)
                    conversationMessages = messages.sorted { $0.createdAt < $1.createdAt }
                    isLoadingMessages = false
                    
                    // Initialize previous message count after initial load
                    previousMessageCount = conversationMessages.count
                    
                    print("💬 MessageConversationModal: Conversation messages loaded and sorted:")
                    print("💬 MessageConversationModal: Final conversationMessages count: \(conversationMessages.count)")
                    for (index, msg) in conversationMessages.enumerated() {
                        print("💬 \(index + 1). \(msg.senderName): \(msg.content) - \(msg.createdAt.formattedTimestamp())")
                    }
                }
            } catch {
                print("❌ MessageConversationModal: Error loading conversation messages: \(error)")
                await MainActor.run {
                    // Ensure fallback message is also properly sorted
                    conversationMessages = [message].sorted { $0.createdAt < $1.createdAt }
                    isLoadingMessages = false
                    print("💬 MessageConversationModal: Using fallback message, isLoadingMessages set to false")
                }
            }
        }
        
        // Add a timeout to prevent infinite loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if isLoadingMessages {
                print("⚠️ MessageConversationModal: Loading timeout reached, showing fallback")
                conversationMessages = [message].sorted { $0.createdAt < $1.createdAt }
                isLoadingMessages = false
            }
        }
    }
    
    private func startAutoRefresh() {
        print("🔄 MessageConversationModal: Starting auto-refresh timer (10 seconds)")
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            print("🔄 MessageConversationModal: Auto-refreshing conversation...")
            refreshMessagesOnly()
        }
    }
    
    private func refreshMessagesOnly() {
        print("💬 MessageConversationModal: Refreshing message content only (no profile photos)...")
        print("💬 MessageConversationModal: Current cached profile photos - Current: \(currentUserProfilePhotoURL != nil), Other: \(otherUserProfilePhotoURL != nil)")
        
        // Determine the other user's ID
        let otherUserId: String
        if message.senderName == "You" {
            otherUserId = message.recipientId
        } else {
            otherUserId = message.senderId
        }
        
        // Refresh in background
        Task {
            await refreshConversationMessagesInBackground(otherUserId: otherUserId)
        }
    }
    
    private func refreshConversationMessagesInBackground(otherUserId: String) async {
            do {
                print("💬 MessageConversationModal: Calling fetchConversationMessagesContentOnly...")
                let messageContent = try await FirebaseAuthService.shared.fetchConversationMessagesContentOnly(with: otherUserId)
                print("💬 MessageConversationModal: Received \(messageContent.count) message content from Firebase")
                
                await MainActor.run {
                // Store previous count before update
                let oldCount = conversationMessages.count
                
                    // Update only the message content, preserve existing MessageDisplay objects
                    updateMessageContentOnly(with: messageContent)
                
                // Update cache with latest messages
                appState.updateConversationMessagesCache(conversationMessages, for: otherUserId)
                
                // Check if new messages arrived (from the other user)
                let newCount = conversationMessages.count
                if newCount > oldCount {
                    // Check if any of the new messages are from the other user (not "You")
                    let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid ?? ""
                    let hasNewIncomingMessage = conversationMessages.suffix(newCount - oldCount).contains { msg in
                        msg.senderId != currentUserId
                    }
                    
                    if hasNewIncomingMessage {
                        // Play sound for new incoming message
                        SoundService.shared.playNewMessageSound()
                        print("🔊 Played new message sound for incoming message in conversation")
                    }
                }
                
                // Update previous count
                previousMessageCount = newCount
                    
                    print("💬 MessageConversationModal: Message content refreshed (profile photos unchanged)")
                    print("💬 MessageConversationModal: Final conversationMessages count: \(conversationMessages.count)")
                    print("💬 MessageConversationModal: Profile photos still cached - Current: \(currentUserProfilePhotoURL != nil), Other: \(otherUserProfilePhotoURL != nil)")
                }
            } catch {
                print("❌ MessageConversationModal: Error refreshing message content: \(error)")
            }
    }
    
    private func fetchProfilePhotosIfNeeded(otherUserId: String) async {
        // Get current user ID
        guard let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid else {
            return
        }
        
        // Fetch both profile photos in parallel
        do {
            async let currentUserPhoto = FirebaseAuthService.shared.fetchUserProfilePhotoURL(for: currentUserId)
            async let otherUserPhoto = FirebaseAuthService.shared.fetchUserProfilePhotoURL(for: otherUserId)
            
            let (currentPhoto, otherPhoto) = try await (currentUserPhoto, otherUserPhoto)
            
            await MainActor.run {
                currentUserProfilePhotoURL = currentPhoto
                otherUserProfilePhotoURL = otherPhoto
                print("💬 MessageConversationModal: Profile photos cached - Current: \(currentPhoto != nil), Other: \(otherPhoto != nil)")
            }
        } catch {
            print("❌ MessageConversationModal: Error fetching profile photos: \(error)")
        }
    }
    
    private func updateMessageContentOnly(with newMessages: [Message]) {
        // Determine the other user's ID
        let otherUserId: String
        if message.senderName == "You" {
            otherUserId = message.recipientId
        } else {
            otherUserId = message.senderId
        }
        // Create a map of existing messages by their content and timestamp for quick lookup
        var existingMessagesMap: [String: MessageDisplay] = [:]
        for msg in conversationMessages {
            let key = "\(msg.content)_\(msg.createdAt.timeIntervalSince1970)"
            existingMessagesMap[key] = msg
        }
        
        // Create new MessageDisplay objects only for new messages
        var updatedMessages: [MessageDisplay] = []
        
        for message in newMessages {
            let key = "\(message.content)_\(message.createdAt.timeIntervalSince1970)"
            
            if let existingMessage = existingMessagesMap[key] {
                // Message already exists, keep the existing MessageDisplay object
                updatedMessages.append(existingMessage)
            } else {
                // New message, create MessageDisplay with cached profile photos
                let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid ?? ""
                let senderName = message.senderFirebaseId == currentUserId ? "You" : "Other User"
                let recipientName = senderName == "You" ? "Other User" : "You"
                
                let messageDisplay = MessageDisplay(
                    message: message,
                    senderName: senderName,
                    recipientName: recipientName,
                    senderId: message.senderFirebaseId,
                    recipientId: message.senderFirebaseId == currentUserId ? otherUserId : currentUserId,
                    senderProfilePhotoURL: senderName == "You" ? currentUserProfilePhotoURL : otherUserProfilePhotoURL,
                    recipientProfilePhotoURL: senderName == "You" ? otherUserProfilePhotoURL : currentUserProfilePhotoURL
                )
                
                updatedMessages.append(messageDisplay)
            }
        }
        
        conversationMessages = updatedMessages
        print("💬 MessageConversationModal: Updated \(updatedMessages.count) messages, preserved existing profile photos")
    }
    
    private func stopAutoRefresh() {
        print("🔄 MessageConversationModal: Stopping auto-refresh timer")
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func sendReply() {
        guard !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSendingReply = true
        let trimmedContent = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            do {
                // Determine recipient ID based on message type
                let recipientId: String
                if message.senderName == "You" {
                    // This is a sent message, so we're replying to the recipient
                    recipientId = message.recipientId
                } else {
                    // This is an incoming message, so we're replying to the sender
                    recipientId = message.senderId
                }
                
                let messageId = try await FirebaseAuthService.shared.sendMessage(
                    to: recipientId,
                    content: trimmedContent
                )
                
                print("✅ Reply sent successfully with ID: \(messageId)")
                
                    await MainActor.run {
                        updateConversationListAfterOutgoingMessage(content: trimmedContent, type: .text, voiceDuration: nil)
                        replyText = ""
                        isSendingReply = false
                        // Don't dismiss the modal - let user continue the conversation
                        // Modal will only close when user taps "Done"
                        
                        // Update cache and refresh the conversation to show the new message
                        let otherUserId = message.senderName == "You" ? message.recipientId : message.senderId
                        // Refresh will update the cache automatically
                        refreshMessagesOnly()
                    }
                
            } catch {
                print("❌ Error sending reply: \(error)")
                await MainActor.run {
                    isSendingReply = false
                }
            }
        }
    }
    
    private func sendImageMessage(image: UIImage) {
        guard let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid else {
            print("❌ Cannot send image - user not authenticated")
            return
        }
        
        isUploadingImage = true
        
        Task {
            do {
                // Determine recipient ID based on message type
                let recipientId: String
                if message.senderName == "You" {
                    // This is a sent message, so we're replying to the recipient
                    recipientId = message.recipientId
                } else {
                    // This is an incoming message, so we're replying to the sender
                    recipientId = message.senderId
                }
                
                // Upload image to Firebase Storage
                let imageURL = try await PhotoStorageService.shared.uploadMessageImage(image, for: currentUserId)
                print("✅ Image uploaded successfully: \(imageURL)")
                
                // Send message with image URL
                let messageId = try await FirebaseAuthService.shared.sendImageMessage(
                    to: recipientId,
                    imageURL: imageURL
                )
                
                print("✅ Image message sent successfully with ID: \(messageId)")
                
                await MainActor.run {
                    selectedImage = nil
                    isUploadingImage = false
                    
                    // Update cache with new message
                    updateConversationListAfterOutgoingMessage(content: imageURL, type: .image, voiceDuration: nil)
                    let otherUserId = message.senderName == "You" ? message.recipientId : message.senderId
                    // Refresh will update the cache
                    refreshMessagesOnly()
                }
                
            } catch {
                print("❌ Error sending image message: \(error)")
                await MainActor.run {
                    selectedImage = nil
                    isUploadingImage = false
                }
            }
        }
    }
    
    private func startRecording() {
        // Remove any existing preview and file before starting a new recording
        if showRecordingPreview {
            discardRecording()
        }
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    beginRecordingSession()
                } else {
                    showingMicrophonePermissionAlert = true
                }
            }
        }
    }
    
    private func beginRecordingSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice_\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
            
            audioRecordingURL = fileURL
            recordingDuration = 0
            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                recordingDuration = audioRecorder?.currentTime ?? recordingDuration
            }
            
            withAnimation {
                isRecording = true
            }
        } catch {
            print("❌ Failed to begin recording session: \(error)")
            showingMicrophonePermissionAlert = true
            discardRecording()
        }
    }
    
    private func stopRecording() {
        guard isRecording else { return }
        
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        let capturedDuration = audioRecorder?.currentTime ?? recordingDuration
        audioRecorder = nil
        
        withAnimation {
            isRecording = false
        }
        
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        
        recordingDuration = max(capturedDuration, 0.1)
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85, blendDuration: 0.2)) {
                showRecordingPreview = true
            }
        }
    }
    
    private func discardRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        audioRecorder?.stop()
        audioRecorder = nil
        
        if let url = audioRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioRecordingURL = nil
        recordingDuration = 0
        
        withAnimation {
            showRecordingPreview = false
        }
    }
    
    private func sendVoiceMessage(audioURL: URL, duration: TimeInterval) {
        guard !isSendingVoice else { return }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            discardRecording()
            return
        }
        guard let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid else {
            discardRecording()
            return
        }
        
        isSendingVoice = true
        
        Task {
            do {
                let recipientId = message.senderName == "You" ? message.recipientId : message.senderId
                let remoteURL = try await PhotoStorageService.shared.uploadVoiceMessage(audioURL, for: currentUserId)
                let messageId = try await FirebaseAuthService.shared.sendVoiceMessage(
                    to: recipientId,
                    audioURL: remoteURL,
                    duration: duration
                )
                
                print("✅ Voice message sent successfully with ID: \(messageId)")
                
                // Cleanup local file
                try? FileManager.default.removeItem(at: audioURL)
                
                await MainActor.run {
                    isSendingVoice = false
                    discardRecording()
                    refreshMessagesOnly()
                }
            } catch {
                print("❌ Error sending voice message: \(error)")
                await MainActor.run {
                    isSendingVoice = false
                }
            }
        }
    }
    
    private func updateConversationListAfterOutgoingMessage(content: String, type: MessageType, voiceDuration: TimeInterval?) {
        guard let currentUserId = FirebaseAuthService.shared.auth.currentUser?.uid else { return }
        let otherUserId = message.senderName == "You" ? message.recipientId : message.senderId
        let otherUserName = message.senderName == "You" ? message.recipientName : message.senderName
        let newMessage = Message(
            conversationId: UUID(),
            senderId: UUID(),
            senderFirebaseId: currentUserId,
            content: content,
            type: type,
            voiceDuration: voiceDuration
        )
        let messageDisplay = MessageDisplay(
            message: newMessage,
            senderName: "You",
            recipientName: otherUserName,
            senderId: currentUserId,
            recipientId: otherUserId,
            senderProfilePhotoURL: currentUserProfilePhotoURL,
            recipientProfilePhotoURL: otherUserProfilePhotoURL
        )
        appState.updateConversationInCache(messageDisplay)
    }
}

struct MessageImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MessageImagePicker
        
        init(_ parent: MessageImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let result = results.first else { return }
            
            result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                if let image = image as? UIImage {
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image
                    }
                }
            }
        }
    }
}

struct RecordingIndicatorView: View {
    let durationText: String
    @State private var animate = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("messages.voice.recording".localized)
                     .font(.headline)
                     .fontWeight(.semibold)
                 Spacer()
             }
             HStack(spacing: 12) {
                 Circle()
                     .fill(Color.red)
                     .frame(width: 12, height: 12)
                     .scaleEffect(animate ? 1.2 : 0.9)
                     .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: animate)
                     .onAppear {
                         animate = true
                     }
                 Text(durationText)
                     .font(.title3)
                     .fontWeight(.medium)
                     .monospacedDigit()
                     .foregroundColor(.secondary)
             }
         }
     }
 }

struct RecordingPreviewView: View {
    let audioURL: URL
    let duration: TimeInterval
    let isSending: Bool
    let onSend: () -> Void
    let onDiscard: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("messages.voice.ready".localized)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                 Spacer()
             }
             
             VoiceMessagePlayerView(
                 audioURL: audioURL,
                 displayDuration: duration,
                 accentColor: .white,
                 textColor: .white,
                 baseColor: Color.gray,
                 waveColor: Color.white
             )
             
             HStack {
                 Button(role: .destructive) {
                     onDiscard()
                 } label: {
                     Label("common.delete".localized, systemImage: "trash")
                         .font(.subheadline)
                 }
                 .buttonStyle(.borderedProminent)
                 .tint(.red)
                 
                 Spacer()
                 
                 Button(action: onSend) {
                     if isSending {
                         ProgressView()
                             .progressViewStyle(CircularProgressViewStyle())
                             .scaleEffect(0.8)
                     } else {
                         Label("messages.send".localized, systemImage: "paperplane.fill")
                             .font(.subheadline)
                     }
                 }
                 .buttonStyle(.borderedProminent)
                 .tint(.green)
                 .disabled(isSending)
             }
         }
         .padding(.vertical, 20)
         .padding(.horizontal, 24)
     }
 }

struct VoiceMessagePlayerView: View {
    let audioURL: URL?
    let displayDuration: TimeInterval?
    let accentColor: Color
    let textColor: Color
    let baseColor: Color
    let waveColor: Color
    
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isLoading = false
    @State private var isPlaying = false
    @State private var loadError = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var playbackTimer: Timer?
    @State private var tempFileURL: URL?
    @State private var pendingAutoPlay = false
    @State private var showElapsedTime = false
    
    var body: some View {
        let bubbleHeight: CGFloat = 80
        ZStack(alignment: .bottomTrailing) {
            VoiceMessageBackground(
                baseColor: baseColor,
                waveColor: waveColor,
                progress: progress
            )
            .frame(height: bubbleHeight)
            
            HStack(spacing: 12) {
                Button(action: togglePlayback) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.18))
                            .frame(width: 44, height: 44)
                        if isLoading {
                            ProgressView()
                                .tint(accentColor)
                        } else if loadError {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                        } else {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .foregroundColor(accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLoading || loadError || audioURL == nil)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: bubbleHeight, alignment: .center)
            
            Text(displayTime)
                .font(.caption)
                .foregroundColor(textColor.opacity(0.75))
                .padding(.trailing, 16)
                .padding(.bottom, 10)
        }
        .onAppear {
            if duration == 0, let displayDuration {
                duration = displayDuration
            }
            prepareAudioIfNeeded(autoPlay: false)
        }
        .onDisappear {
            stopPlayback(resetPosition: true)
            if let tempFileURL {
                try? FileManager.default.removeItem(at: tempFileURL)
            }
            audioPlayer = nil
        }
    }
    
    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
    
    private var displayTime: String {
        if showElapsedTime {
            return formattedDuration(currentTime)
        }
        return formattedDuration(duration > 0 ? duration : (displayDuration ?? 0))
    }
    
    private func togglePlayback() {
        if isPlaying {
            stopPlayback(resetPosition: false)
        } else {
            if audioPlayer == nil {
                prepareAudioIfNeeded(autoPlay: true)
            } else {
                startPlayback()
            }
        }
    }
    
    private func prepareAudioIfNeeded(autoPlay: Bool) {
        guard audioPlayer == nil, !isLoading else {
            if autoPlay {
                startPlayback()
            }
            return
        }
        guard let audioURL else {
            loadError = true
            return
        }
        
        isLoading = true
        loadError = false
        pendingAutoPlay = autoPlay
        
        Task {
            do {
                let localURL: URL
                if audioURL.isFileURL {
                    localURL = audioURL
                } else {
                    let (data, _) = try await URLSession.shared.data(from: audioURL)
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice_preview_\(UUID().uuidString).m4a")
                    try data.write(to: tempURL, options: .atomic)
                    localURL = tempURL
                    await MainActor.run {
                        tempFileURL = tempURL
                    }
                }
                
                let player = try AVAudioPlayer(contentsOf: localURL)
                player.prepareToPlay()
                let actualDuration = player.duration
                
                await MainActor.run {
                    audioPlayer = player
                    if actualDuration > 0 {
                        duration = actualDuration
                    } else if let displayDuration, displayDuration > 0 {
                        duration = displayDuration
                    }
                    isLoading = false
                    
                    if pendingAutoPlay {
                        startPlayback()
                    }
                }
            } catch {
                print("❌ Failed to load audio: \(error)")
                await MainActor.run {
                    isLoading = false
                    loadError = true
                    showElapsedTime = false
                }
            }
        }
    }
    
    private func startPlayback() {
        guard let player = audioPlayer else { return }
        player.currentTime = currentTime
        if player.duration > 0 {
            duration = player.duration
        }
        player.play()
        isPlaying = true
        showElapsedTime = true
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            currentTime = min(player.currentTime, duration)
            if !player.isPlaying {
                stopPlayback(resetPosition: true)
            }
        }
    }
    
    private func stopPlayback(resetPosition: Bool) {
        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        if resetPosition {
            currentTime = 0
            showElapsedTime = false
        }
    }
}

struct VoiceMessageBackground: View {
    let baseColor: Color
    let waveColor: Color
    let progress: Double
    private let cornerRadius: CGFloat = 16
    private let barCount = 32
    private let leadingInset: CGFloat = 90
    private let trailingInset: CGFloat = 24
    
    var body: some View {
        GeometryReader { proxy in
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                baseColor.opacity(0.95),
                                baseColor.opacity(0.82)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Canvas { context, size in
                    let waveWidth = max(0, size.width - leadingInset - trailingInset)
                    guard waveWidth > 0 else { return }
                    let step = waveWidth / CGFloat(max(barCount - 1, 1))
                    let centerY = size.height / 2
                    for index in 0..<barCount {
                        let currentWidth = barWidth(for: index)
                        let currentHeight = barHeight(for: index)
                        let xPosition = leadingInset + step * CGFloat(index)
                        let rect = CGRect(
                            x: xPosition - currentWidth / 2,
                            y: centerY - currentHeight / 2,
                            width: currentWidth,
                            height: currentHeight
                        )
                        let path = Path(roundedRect: rect, cornerRadius: currentWidth / 2)
                        context.fill(path, with: .color(barColor(for: index)))
                    }
                }
                .clipShape(shape)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let pattern: [CGFloat] = [20, 14, 24, 12, 26, 15, 22, 13, 24, 16, 20, 14, 28, 17, 22, 15, 24, 14, 22, 15, 24, 13]
        return pattern[index % pattern.count]
    }
    
    private func barWidth(for index: Int) -> CGFloat {
        index % 3 == 0 ? 3 : 2
    }
    
    private func barColor(for index: Int) -> Color {
        let normalized = Double(index) / Double(max(barCount - 1, 1))
        let highlightWidth = 0.22
        let distance = progress - normalized
        let emphasis = max(0.0, min(1.0, (distance + highlightWidth) / highlightWidth))
        let baseRGB: (Double, Double, Double) = (0.70, 0.72, 0.75)
        let targetRGB: (Double, Double, Double) = (1.0, 1.0, 1.0)
        let red = baseRGB.0 + (targetRGB.0 - baseRGB.0) * emphasis
        let green = baseRGB.1 + (targetRGB.1 - baseRGB.1) * emphasis
        let blue = baseRGB.2 + (targetRGB.2 - baseRGB.2) * emphasis
        let opacity = 0.55 + (0.4 * emphasis)
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct MessageBubble: View {
    let message: MessageDisplay
    let currentUserProfilePhotoURL: String?
    let otherUserProfilePhotoURL: String?
    let conversationMessages: [MessageDisplay]
    @Binding var showingConversationPhotoViewer: Bool
    @Binding var selectedPhotoIndex: Int
    @State private var showingSaveAlert = false
    @State private var saveSuccess = false
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                if message.senderName == "You" {
                    // Debug logging for current user photo
                    let _ = print("🖼️ MessageBubble: Current user photo URL: \(currentUserProfilePhotoURL ?? "nil")")
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        switch message.messageType {
                        case .image:
                            Button(action: {
                                let imageMessages = conversationMessages.filter { $0.messageType == .image }
                                if let index = imageMessages.firstIndex(where: { $0.id == message.id }) {
                                    selectedPhotoIndex = index
                                    showingConversationPhotoViewer = true
                                }
                            }) {
                                AsyncImage(url: URL(string: message.content)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(maxWidth: 150, maxHeight: 150)
                                            .cornerRadius(10)
                                    case .failure:
                                        Image(systemName: "photo")
                                            .foregroundColor(.gray)
                                            .frame(width: 150, height: 150)
                                    case .empty:
                                        ProgressView()
                                            .frame(width: 150, height: 150)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        case .voice:
                            VoiceMessagePlayerView(
                                audioURL: URL(string: message.content),
                                displayDuration: message.voiceDuration,
                                accentColor: .white,
                                textColor: .white,
                                baseColor: Color.blue,
                                waveColor: Color.white
                            )
                        default:
                            Text(message.content)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(nil)
                                .padding(8)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                        }
                    }
                    
                    // Current user's profile photo - parallel to message text
                    if let profilePhotoURL = currentUserProfilePhotoURL, !profilePhotoURL.isEmpty {
                        Circle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 36, height: 36)
                            .overlay(
                                CachedAsyncImage(url: URL(string: profilePhotoURL)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Circle()
                                        .fill(Color.blue.opacity(0.2))
                                        .overlay(
                                            Text("messages.you".localized.prefix(1).uppercased())
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.blue)
                                        )
                                }
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .id("current_user_photo_\(profilePhotoURL)") // Stable ID to prevent re-creation
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Text("messages.you".localized.prefix(1).uppercased())
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.blue)
                                    )
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .id("current_user_placeholder") // Stable ID for placeholder
                    }
                } else {
                    // Debug logging for other user photo
                    let _ = print("🖼️ MessageBubble: Other user photo URL: \(otherUserProfilePhotoURL ?? "nil")")
                    
                    // Other user's profile photo - parallel to message text
                    if let profilePhotoURL = otherUserProfilePhotoURL, !profilePhotoURL.isEmpty {
                        Circle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 36, height: 36)
                            .overlay(
                                CachedAsyncImage(url: URL(string: profilePhotoURL)) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Circle()
                                        .fill(Color.blue.opacity(0.2))
                                        .overlay(
                                            Text(String(message.senderName.prefix(1)).uppercased())
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.blue)
                                        )
                                }
                                .frame(width: 30, height: 30)
                                .clipShape(Circle())
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .id("other_user_photo_\(profilePhotoURL)") // Stable ID to prevent re-creation
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Text(String(message.senderName.prefix(1)).uppercased())
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.blue)
                                    )
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .id("other_user_placeholder_\(message.senderName)") // Stable ID for placeholder
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        switch message.messageType {
                        case .image:
                            Button(action: {
                                let imageMessages = conversationMessages.filter { $0.messageType == .image }
                                if let index = imageMessages.firstIndex(where: { $0.id == message.id }) {
                                    selectedPhotoIndex = index
                                    showingConversationPhotoViewer = true
                                }
                            }) {
                                AsyncImage(url: URL(string: message.content)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(maxWidth: 150, maxHeight: 150)
                                            .cornerRadius(10)
                                    case .failure:
                                        Image(systemName: "photo")
                                            .foregroundColor(.gray)
                                            .frame(width: 150, height: 150)
                                    case .empty:
                                        ProgressView()
                                            .frame(width: 150, height: 150)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        case .voice:
                            VoiceMessagePlayerView(
                                audioURL: URL(string: message.content),
                                displayDuration: message.voiceDuration,
                                accentColor: .white,
                                textColor: .white,
                                baseColor: Color.blue,
                                waveColor: Color.white
                            )
                        default:
                            Text(message.content)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(nil)
                                .padding(8)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                        }
                    }
                    Spacer()
                }
            }
            
            // Timestamp below the message
            HStack {
                if message.senderName == "You" {
                    Spacer()
                    Text(message.createdAt.formattedTimestamp())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 40) // Align with message bubble
                } else {
                    Text(message.createdAt.formattedTimestamp())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 40) // Align with message bubble
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ConversationPhotoViewerModal: View {
    let photos: [String]
    @Binding var selectedIndex: Int
    let conversationMessages: [MessageDisplay]
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset = CGSize.zero
    @State private var showingSaveAlert = false
    @State private var saveSuccess = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Black background
                Color.black
                    .ignoresSafeArea()
                
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
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("common.done".localized) {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("common.save".localized) {
                        guard selectedIndex >= 0, selectedIndex < photos.count else {
                            print("❌ Invalid photo index: \(selectedIndex), photos count: \(photos.count)")
                            return
                        }
                        saveImageToPhotoLibrary(imageURL: photos[selectedIndex])
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("messages.image.saved".localized, isPresented: $showingSaveAlert) {
                Button("common.ok".localized) { }
            } message: {
                Text(saveSuccess ? "messages.image.saved.success".localized : "messages.image.saved.failed".localized)
            }
        }
    }
    
    private func saveImageToPhotoLibrary(imageURL: String) {
        guard let url = URL(string: imageURL) else {
            Task { @MainActor in
                saveSuccess = false
                showingSaveAlert = true
            }
            return
        }
        
        Task {
            do {
                // Download image data
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else {
                    await MainActor.run {
                        saveSuccess = false
                        showingSaveAlert = true
                        print("❌ Failed to create UIImage from data")
                    }
                    return
                }
                
                // Check current authorization status
                let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                
                // Request authorization if needed
                let status: PHAuthorizationStatus
                if currentStatus == .notDetermined {
                    status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                } else {
                    status = currentStatus
                }
                
                // Check if we have permission
                guard status == .authorized || status == .limited else {
                    await MainActor.run {
                        saveSuccess = false
                        showingSaveAlert = true
                        print("❌ Photo library permission denied or restricted. Status: \(status.rawValue)")
                    }
                    return
                }
                
                // Save image to photo library
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }, completionHandler: { success, error in
                    DispatchQueue.main.async {
                        if success {
                            self.saveSuccess = true
                            self.showingSaveAlert = true
                            print("✅ Image saved successfully")
                        } else {
                            self.saveSuccess = false
                            self.showingSaveAlert = true
                            if let error = error {
                                print("❌ Error saving image: \(error.localizedDescription)")
                            } else {
                                print("❌ Unknown error saving image")
                            }
                        }
                    }
                })
            } catch {
                await MainActor.run {
                    saveSuccess = false
                    showingSaveAlert = true
                    print("❌ Error downloading image: \(error.localizedDescription)")
                }
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

fileprivate func formattedDuration(_ interval: TimeInterval) -> String {
    guard interval.isFinite && !interval.isNaN else { return "0:00" }
    let total = max(Int(interval.rounded()), 0)
    let minutes = total / 60
    let seconds = total % 60
    return String(format: "%d:%02d", minutes, seconds)
}

#Preview {
    MessagesView(selectedTab: .constant(0))
}
