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

struct ProfileCard: Codable {
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
    let sensoryPreferences: [String]
    let shareSensoryPreferences: Bool
    let energyLevel: Int
    let matchPercentage: Int
    
    init(
        userId: String,
        name: String,
        age: Int,
        bio: String,
        interests: [String],
        distance: String,
        imageURL: String?,
        gender: String,
        interestedIn: [String],
        lookingFor: [String],
        photos: [String],
        lifestyle: String,
        shareLifestyle: Bool,
        bodyType: String,
        shareBodyType: Bool,
        preferredAgeMin: Int,
        preferredAgeMax: Int,
        isOnline: Bool,
        lastSeen: Date,
        idealFirstDate: [String],
        shareIdealFirstDate: Bool,
        sensoryPreferences: [String] = [],
        shareSensoryPreferences: Bool = false,
        energyLevel: Int,
        matchPercentage: Int = 0
    ) {
        self.userId = userId
        self.name = name
        self.age = age
        self.bio = bio
        self.interests = interests
        self.distance = distance
        self.imageURL = imageURL
        self.gender = gender
        self.interestedIn = interestedIn
        self.lookingFor = lookingFor
        self.photos = photos
        self.lifestyle = lifestyle
        self.shareLifestyle = shareLifestyle
        self.bodyType = bodyType
        self.shareBodyType = shareBodyType
        self.preferredAgeMin = preferredAgeMin
        self.preferredAgeMax = preferredAgeMax
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.idealFirstDate = idealFirstDate
        self.shareIdealFirstDate = shareIdealFirstDate
        self.sensoryPreferences = sensoryPreferences
        self.shareSensoryPreferences = shareSensoryPreferences
        self.energyLevel = energyLevel
        self.matchPercentage = matchPercentage
    }
    
    static func calculateMatchPercentage(
        interests: [String],
        age: Int,
        gender: String,
        currentUser: SpectRoomUser
    ) -> Int {
        var matchScore = 0
        var totalFactors = 0
        
        let currentUserInterests = Set(currentUser.interests)
        let profileInterests = Set(interests)
        let commonInterests = currentUserInterests.intersection(profileInterests)
        let interestsMatch = commonInterests.count > 0
            ? Double(commonInterests.count) / Double(max(currentUserInterests.count, profileInterests.count))
            : 0.0
        matchScore += Int(interestsMatch * 40)
        totalFactors += 40
        
        let ageDifference = abs(currentUser.age - age)
        let ageMatch = max(0, 1.0 - Double(ageDifference) / 20.0)
        matchScore += Int(ageMatch * 30)
        totalFactors += 30
        
        let genderMatch = Set(currentUser.interestedIn).contains(gender) ? 1.0 : 0.0
        matchScore += Int(genderMatch * 30)
        totalFactors += 30
        
        let percentage = totalFactors > 0 ? Int((Double(matchScore) / Double(totalFactors)) * 100) : 0
        return min(max(percentage, 15), 95)
    }
}

