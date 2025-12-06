// Models/FeedModels.swift
// Feed-specific models for the For You feed
// Note: SupabaseClient uses .convertFromSnakeCase so no CodingKeys needed
// ✅ Added isSaved for bookmark functionality

import Foundation

// MARK: - Feed Response

struct FeedResponse: Codable {
    let items: [FeedItem]
    let hasMore: Bool
    let nextCursor: String?
}

// MARK: - Feed Item

struct FeedItem: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var rating: Int?
    var comment: String?
    var photoUrls: [String]?
    var visibility: String
    let createdAt: String
    let visitedAt: String?
    var likeCount: Int
    var commentCount: Int
    var isLiked: Bool
    var isSaved: Bool  // ✅ NEW: Bookmark status
    let isFollowing: Bool
    let user: FeedUser
    let place: FeedPlace
    
    var photos: [String] {
        photoUrls ?? []
    }
    
    // Custom init to provide default for isSaved (backward compatibility)
    init(id: String, rating: Int?, comment: String?, photoUrls: [String]?, visibility: String, createdAt: String, visitedAt: String?, likeCount: Int, commentCount: Int, isLiked: Bool, isSaved: Bool = false, isFollowing: Bool, user: FeedUser, place: FeedPlace) {
        self.id = id
        self.rating = rating
        self.comment = comment
        self.photoUrls = photoUrls
        self.visibility = visibility
        self.createdAt = createdAt
        self.visitedAt = visitedAt
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.isLiked = isLiked
        self.isSaved = isSaved
        self.isFollowing = isFollowing
        self.user = user
        self.place = place
    }
    
    // Decoder with default value for isSaved
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        rating = try container.decodeIfPresent(Int.self, forKey: .rating)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        photoUrls = try container.decodeIfPresent([String].self, forKey: .photoUrls)
        visibility = try container.decode(String.self, forKey: .visibility)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        visitedAt = try container.decodeIfPresent(String.self, forKey: .visitedAt)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        isLiked = try container.decode(Bool.self, forKey: .isLiked)
        isSaved = try container.decodeIfPresent(Bool.self, forKey: .isSaved) ?? false  // Default to false
        isFollowing = try container.decode(Bool.self, forKey: .isFollowing)
        user = try container.decode(FeedUser.self, forKey: .user)
        place = try container.decode(FeedPlace.self, forKey: .place)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, rating, comment, photoUrls, visibility, createdAt, visitedAt
        case likeCount, commentCount, isLiked, isSaved, isFollowing, user, place
    }
    
    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Feed User

struct FeedUser: Codable, Equatable, Hashable {
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
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Feed Place

struct FeedPlace: Codable, Equatable, Hashable {
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
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Save Toggle Response

struct VisitSaveToggleResponse: Codable {
    let success: Bool
    let isSaved: Bool
    let visitId: String
}
