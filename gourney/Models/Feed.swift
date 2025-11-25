// Models/FeedModels.swift
// Feed-specific models for the For You feed
// Note: SupabaseClient uses .convertFromSnakeCase so no CodingKeys needed

import Foundation

// MARK: - Feed Response

struct FeedResponse: Codable {
    let items: [FeedItem]
    let hasMore: Bool
    let nextOffset: Int?
}

// MARK: - Feed Item

struct FeedItem: Codable, Identifiable, Equatable {
    let id: String
    let rating: Int?
    let comment: String?
    let photoUrls: [String]?  // Optional to handle null/missing
    let visibility: String
    let createdAt: String
    let visitedAt: String?
    let likeCount: Int
    let commentCount: Int
    var isLiked: Bool
    let isFollowing: Bool
    let user: FeedUser
    let place: FeedPlace
    
    /// Safe accessor for photo URLs (never nil)
    var photos: [String] {
        photoUrls ?? []
    }
    
    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Feed User

struct FeedUser: Codable, Equatable {
    let id: String
    let handle: String
    let displayName: String?
    let avatarUrl: String?
    
    var displayNameOrHandle: String {
        if let name = displayName, !name.isEmpty {
            return name
        }
        return handle
    }
    
    static func == (lhs: FeedUser, rhs: FeedUser) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Feed Place

struct FeedPlace: Codable, Equatable {
    let id: String
    let nameEn: String?
    let nameJa: String?
    let nameZh: String?
    let city: String?
    let ward: String?
    let country: String?
    let categories: [String]?
    
    var displayName: String {
        let locale = Locale.current.language.languageCode?.identifier ?? "en"
        
        switch locale {
        case "ja":
            if let ja = nameJa, !ja.isEmpty { return ja }
            if let en = nameEn, !en.isEmpty { return en }
            return "Unknown Place"
        case "zh":
            if let zh = nameZh, !zh.isEmpty { return zh }
            if let en = nameEn, !en.isEmpty { return en }
            return "Unknown Place"
        default:
            if let en = nameEn, !en.isEmpty { return en }
            if let ja = nameJa, !ja.isEmpty { return ja }
            return "Unknown Place"
        }
    }
    
    var locationString: String {
        let parts = [ward, city, country].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: ", ")
    }
    
    static func == (lhs: FeedPlace, rhs: FeedPlace) -> Bool {
        lhs.id == rhs.id
    }
}
