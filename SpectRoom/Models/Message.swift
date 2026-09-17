//
//  Message.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import Foundation

struct Message: Identifiable, Codable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let senderFirebaseId: String // Store the actual Firebase UID
    let content: String
    let type: MessageType
    let createdAt: Date
    var isRead: Bool
    var readAt: Date?
    var voiceDuration: TimeInterval?
    /// Preview image URL for video messages (first-frame thumbnail).
    var thumbnailURL: String?
    var videoDuration: TimeInterval?
    
    init(
        conversationId: UUID,
        senderId: UUID,
        senderFirebaseId: String,
        content: String,
        type: MessageType = .text,
        voiceDuration: TimeInterval? = nil,
        thumbnailURL: String? = nil,
        videoDuration: TimeInterval? = nil
    ) {
        self.id = UUID()
        self.conversationId = conversationId
        self.senderId = senderId
        self.senderFirebaseId = senderFirebaseId
        self.content = content
        self.type = type
        self.createdAt = Date()
        self.isRead = false
        self.readAt = nil
        self.voiceDuration = voiceDuration
        self.thumbnailURL = thumbnailURL
        self.videoDuration = videoDuration
    }
    
    // Custom initializer for messages with specific timestamp (from Firebase)
    init(
        conversationId: UUID,
        senderId: UUID,
        senderFirebaseId: String,
        content: String,
        createdAt: Date,
        type: MessageType = .text,
        voiceDuration: TimeInterval? = nil,
        thumbnailURL: String? = nil,
        videoDuration: TimeInterval? = nil
    ) {
        self.id = UUID()
        self.conversationId = conversationId
        self.senderId = senderId
        self.senderFirebaseId = senderFirebaseId
        self.content = content
        self.type = type
        self.createdAt = createdAt
        self.isRead = false
        self.readAt = nil
        self.voiceDuration = voiceDuration
        self.thumbnailURL = thumbnailURL
        self.videoDuration = videoDuration
    }
}

enum MessageType: String, CaseIterable, Codable {
    case text = "text"
    case image = "image"
    case voice = "voice"
    case video = "video"
    case system = "system"
    
    var displayName: String {
        switch self {
        case .text:
            return "Text"
        case .image:
            return "Image"
        case .voice:
            return "Voice Message"
        case .video:
            return "Video"
        case .system:
            return "System Message"
        }
    }
    
    var icon: String {
        switch self {
        case .text:
            return "text.bubble"
        case .image:
            return "photo"
        case .voice:
            return "mic.fill"
        case .video:
            return "video.fill"
        case .system:
            return "info.circle"
        }
    }
}

struct Conversation: Identifiable, Codable {
    let id: UUID
    let participantIds: [UUID]
    let lastMessage: Message?
    let createdAt: Date
    var isActive: Bool
    var unreadCount: Int
    
    init(participantIds: [UUID]) {
        self.id = UUID()
        self.participantIds = participantIds
        self.lastMessage = nil
        self.createdAt = Date()
        self.isActive = true
        self.unreadCount = 0
    }
}

// Helper struct for displaying conversation in UI
struct ConversationDisplay: Identifiable {
    let id: UUID
    let otherUser: SpectRoomUser
    let lastMessage: String
    let timestamp: String
    let isOnline: Bool
    let unreadCount: Int
    
    init(conversation: Conversation, otherUser: SpectRoomUser, lastMessage: Message?) {
        self.id = conversation.id
        self.otherUser = otherUser
        self.lastMessage = lastMessage?.content ?? "No messages yet"
        self.timestamp = lastMessage?.createdAt.timeAgoDisplay() ?? ""
        self.isOnline = otherUser.isOnline
        self.unreadCount = conversation.unreadCount
    }
}

// Helper struct for displaying messages in UI with sender/recipient names
struct MessageDisplay: Identifiable {
    let id: String
    let content: String
    let messageType: MessageType
    let senderName: String
    let recipientName: String
    let senderId: String // Firebase user ID
    let recipientId: String // Firebase user ID
    let createdAt: Date
    let isRead: Bool
    let senderProfilePhotoURL: String? // Profile photo URL of the sender
    let recipientProfilePhotoURL: String? // Profile photo URL of the recipient
    let voiceDuration: TimeInterval?
    let thumbnailURL: String?
    let videoDuration: TimeInterval?
    /// Soft-delete: hidden only for the current viewer (document still kept for admin).
    let deletedForViewer: Bool
    /// Soft-delete: hidden for both participants (document content still kept for admin).
    let deletedForEveryone: Bool
    /// Quick reactions: Firebase userId → emoji.
    let reactions: [String: String]

    static let deleteForEveryoneWindow: TimeInterval = 60 * 60
    static let quickReactionEmojis = ["❤️", "😂", "👍", "🙏", "🔥"]

    var isDeleted: Bool {
        deletedForViewer || deletedForEveryone
    }

    var displayContent: String {
        isDeleted ? "messages.deleted.placeholder".localized : content
    }

    /// Aggregated reaction chips for the bubble footer.
    var reactionSummary: [(emoji: String, count: Int)] {
        let grouped = Dictionary(grouping: reactions.values, by: { $0 })
        return grouped
            .map { (emoji: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.emoji < rhs.emoji
            }
    }

    /// Messages can be deleted for everyone within the time window of send.
    func canDeleteForEveryone(now: Date = Date()) -> Bool {
        now.timeIntervalSince(createdAt) <= Self.deleteForEveryoneWindow
    }
    
    init(
        message: Message,
        senderName: String,
        recipientName: String,
        senderId: String,
        recipientId: String,
        senderProfilePhotoURL: String? = nil,
        recipientProfilePhotoURL: String? = nil,
        firestoreId: String? = nil,
        deletedForViewer: Bool = false,
        deletedForEveryone: Bool = false,
        reactions: [String: String] = [:]
    ) {
        self.id = firestoreId ?? message.id.uuidString
        self.content = message.content
        self.messageType = message.type
        self.senderName = senderName
        self.recipientName = recipientName
        self.senderId = senderId
        self.recipientId = recipientId
        self.createdAt = message.createdAt
        self.isRead = message.isRead
        self.senderProfilePhotoURL = senderProfilePhotoURL
        self.recipientProfilePhotoURL = recipientProfilePhotoURL
        self.voiceDuration = message.voiceDuration
        self.thumbnailURL = message.thumbnailURL
        self.videoDuration = message.videoDuration
        self.deletedForViewer = deletedForViewer
        self.deletedForEveryone = deletedForEveryone
        self.reactions = reactions
    }
    
    init(
        id: String,
        content: String,
        messageType: MessageType,
        senderName: String,
        recipientName: String,
        senderId: String,
        recipientId: String,
        createdAt: Date,
        isRead: Bool,
        senderProfilePhotoURL: String?,
        recipientProfilePhotoURL: String?,
        voiceDuration: TimeInterval?,
        thumbnailURL: String? = nil,
        videoDuration: TimeInterval? = nil,
        deletedForViewer: Bool = false,
        deletedForEveryone: Bool = false,
        reactions: [String: String] = [:]
    ) {
        self.id = id
        self.content = content
        self.messageType = messageType
        self.senderName = senderName
        self.recipientName = recipientName
        self.senderId = senderId
        self.recipientId = recipientId
        self.createdAt = createdAt
        self.isRead = isRead
        self.senderProfilePhotoURL = senderProfilePhotoURL
        self.recipientProfilePhotoURL = recipientProfilePhotoURL
        self.voiceDuration = voiceDuration
        self.thumbnailURL = thumbnailURL
        self.videoDuration = videoDuration
        self.deletedForViewer = deletedForViewer
        self.deletedForEveryone = deletedForEveryone
        self.reactions = reactions
    }
    
    /// Stable identity for deduplicating optimistic vs server-fetched copies of the same message.
    var deduplicationKey: String {
        if content.hasPrefix("pending://") {
            return "\(senderId)_\(recipientId)_\(messageType.rawValue)_\(content)"
        }
        return id
    }

    /// Local optimistic bubble that matches a server message of the same send
    /// (same parties/content/type, close timestamps, different ids).
    func isOptimisticDuplicate(of server: MessageDisplay, within seconds: TimeInterval = 90) -> Bool {
        guard id != server.id else { return false }
        guard !content.hasPrefix("pending://"), !server.content.hasPrefix("pending://") else { return false }
        guard senderId == server.senderId,
              recipientId == server.recipientId,
              messageType == server.messageType,
              content == server.content else { return false }
        return abs(createdAt.timeIntervalSince(server.createdAt)) < seconds
    }

    func replacingId(_ newId: String) -> MessageDisplay {
        copying(id: newId)
    }
    
    func replacingPartnerIdentity(name: String, photoURL: String?, currentUserId: String) -> MessageDisplay {
        let isOutgoing = senderId == currentUserId || senderName == "You"
        return copying(
            senderName: isOutgoing ? senderName : name,
            recipientName: isOutgoing ? name : recipientName,
            senderProfilePhotoURL: isOutgoing ? senderProfilePhotoURL : (photoURL ?? senderProfilePhotoURL),
            recipientProfilePhotoURL: isOutgoing ? (photoURL ?? recipientProfilePhotoURL) : recipientProfilePhotoURL
        )
    }

    func markingDeleted(forEveryone: Bool) -> MessageDisplay {
        copying(
            deletedForViewer: true,
            deletedForEveryone: forEveryone || deletedForEveryone
        )
    }

    func withReactions(_ reactions: [String: String]) -> MessageDisplay {
        copying(reactions: reactions)
    }

    func togglingReaction(_ emoji: String, forUserId userId: String) -> MessageDisplay {
        var next = reactions
        if next[userId] == emoji {
            next.removeValue(forKey: userId)
        } else {
            next[userId] = emoji
        }
        return withReactions(next)
    }

    private func copying(
        id: String? = nil,
        content: String? = nil,
        messageType: MessageType? = nil,
        senderName: String? = nil,
        recipientName: String? = nil,
        senderId: String? = nil,
        recipientId: String? = nil,
        createdAt: Date? = nil,
        isRead: Bool? = nil,
        senderProfilePhotoURL: String?? = nil,
        recipientProfilePhotoURL: String?? = nil,
        voiceDuration: TimeInterval?? = nil,
        thumbnailURL: String?? = nil,
        videoDuration: TimeInterval?? = nil,
        deletedForViewer: Bool? = nil,
        deletedForEveryone: Bool? = nil,
        reactions: [String: String]? = nil
    ) -> MessageDisplay {
        MessageDisplay(
            id: id ?? self.id,
            content: content ?? self.content,
            messageType: messageType ?? self.messageType,
            senderName: senderName ?? self.senderName,
            recipientName: recipientName ?? self.recipientName,
            senderId: senderId ?? self.senderId,
            recipientId: recipientId ?? self.recipientId,
            createdAt: createdAt ?? self.createdAt,
            isRead: isRead ?? self.isRead,
            senderProfilePhotoURL: senderProfilePhotoURL ?? self.senderProfilePhotoURL,
            recipientProfilePhotoURL: recipientProfilePhotoURL ?? self.recipientProfilePhotoURL,
            voiceDuration: voiceDuration ?? self.voiceDuration,
            thumbnailURL: thumbnailURL ?? self.thumbnailURL,
            videoDuration: videoDuration ?? self.videoDuration,
            deletedForViewer: deletedForViewer ?? self.deletedForViewer,
            deletedForEveryone: deletedForEveryone ?? self.deletedForEveryone,
            reactions: reactions ?? self.reactions
        )
    }
}

extension Array where Element == MessageDisplay {
    func deduplicatedConversationMessages() -> [MessageDisplay] {
        var seen = Set<String>()
        return sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            // Same-second messages: keep a stable order.
            return lhs.deduplicationKey < rhs.deduplicationKey
        }.filter { message in
            seen.insert(message.deduplicationKey).inserted
        }
    }

    /// Merge server-fetched messages, replacing local optimistic copies instead of appending duplicates.
    func mergingConversationMessages(_ serverMessages: [MessageDisplay]) -> [MessageDisplay] {
        var result = self
        for serverMsg in serverMessages {
            if let exactIndex = result.firstIndex(where: { $0.deduplicationKey == serverMsg.deduplicationKey }) {
                result[exactIndex] = serverMsg
                continue
            }
            if let optimisticIndex = result.firstIndex(where: { $0.isOptimisticDuplicate(of: serverMsg) }) {
                result[optimisticIndex] = serverMsg
                continue
            }
            result.append(serverMsg)
        }
        return result.deduplicatedConversationMessages()
    }
}

struct ConversationMessagesPage {
    let messages: [MessageDisplay]
    let hasMoreOlder: Bool
}

/// Real-time update applied to the other participant's copy of a message.
struct MessageSoftDeleteEvent: Equatable {
    let messageId: String
    /// Conversation partner relative to the current user.
    let partnerId: String
    let deletedForEveryone: Bool
    let deletedForViewer: Bool
    /// `nil` means reactions were not part of this update.
    let reactions: [String: String]?
}

extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        if let selectedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage"),
           !selectedLanguage.isEmpty {
            formatter.locale = Locale(identifier: selectedLanguage)
        }
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    func formattedTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy HH:mm"
        return formatter.string(from: self)
    }
    
    func formattedBubbleTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }
    
    /// Conversation list timestamp: "14:20" / "Yesterday" / "13/07/2026".
    func formattedConversationListTime() -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return formattedBubbleTime()
        }
        if calendar.isDateInYesterday(self) {
            return "messages.date.yesterday".localized
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: self)
    }
    
    /// WhatsApp-style chat day label: Today / Yesterday / "Thu, 21 May".
    func formattedChatDayTitle() -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return "messages.date.today".localized
        }
        if calendar.isDateInYesterday(self) {
            return "messages.date.yesterday".localized
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM"
        if let selectedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage"),
           !selectedLanguage.isEmpty {
            formatter.locale = Locale(identifier: selectedLanguage)
        }
        return formatter.string(from: self)
    }
}
