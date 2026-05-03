//
//  Match.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import Foundation

struct Match: Identifiable, Codable {
    let id: UUID
    let user1Id: UUID
    let user2Id: UUID
    let matchedAt: Date
    var isActive: Bool
    var lastMessageAt: Date?
    var conversationId: UUID?
    
    init(user1Id: UUID, user2Id: UUID) {
        self.id = UUID()
        self.user1Id = user1Id
        self.user2Id = user2Id
        self.matchedAt = Date()
        self.isActive = true
        self.lastMessageAt = nil
        self.conversationId = UUID()
    }
}

struct Like: Identifiable, Codable {
    let id: UUID
    let fromUserId: UUID
    let toUserId: UUID
    let createdAt: Date
    var isSuperLike: Bool
    
    init(fromUserId: UUID, toUserId: UUID, isSuperLike: Bool = false) {
        self.id = UUID()
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.createdAt = Date()
        self.isSuperLike = isSuperLike
    }
}

struct SwipeAction: Identifiable, Codable {
    let id: UUID
    let fromUserId: UUID
    let toUserId: UUID
    let action: SwipeType
    let createdAt: Date
    
    init(fromUserId: UUID, toUserId: UUID, action: SwipeType) {
        self.id = UUID()
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.action = action
        self.createdAt = Date()
    }
}

enum SwipeType: String, CaseIterable, Codable {
    case like = "like"
    case pass = "pass"
    case superLike = "super_like"
    
    var displayName: String {
        switch self {
        case .like:
            return "Like"
        case .pass:
            return "Pass"
        case .superLike:
            return "Super Like"
        }
    }
    
    var icon: String {
        switch self {
        case .like:
            return "heart.fill"
        case .pass:
            return "xmark"
        case .superLike:
            return "star.fill"
        }
    }
    
    var color: String {
        switch self {
        case .like:
            return "red"
        case .pass:
            return "gray"
        case .superLike:
            return "blue"
        }
    }
}

struct MatchDisplay: Identifiable {
    let id: String
    let otherUser: ProfileCard
    let matchedAt: Date
    let lastMessageAt: Date?
    
    init(id: String, otherUser: ProfileCard, matchedAt: Date, lastMessageAt: Date? = nil) {
        self.id = id
        self.otherUser = otherUser
        self.matchedAt = matchedAt
        self.lastMessageAt = lastMessageAt
    }
}

struct ProfileCard {
    let userId: String // Firebase UID
    let name: String
    let age: Int
    let bio: String
    let interests: [String]
    let distance: String
    let imageURL: String?
    let gender: String
    let interestedIn: [String]
    let lookingFor: [String]
    let photos: [String]
    let lifestyle: String
    let shareLifestyle: Bool
    let bodyType: String
    let shareBodyType: Bool
    let preferredAgeMin: Int
    let preferredAgeMax: Int
    let isOnline: Bool
    let lastSeen: Date
    let idealFirstDate: [String]
    let shareIdealFirstDate: Bool
    let energyLevel: Int
}

