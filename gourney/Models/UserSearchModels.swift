// Models/UserSearchModels.swift
// Models for user-search Edge Function responses
// Follows automatic snake_case conversion from SupabaseClient

import Foundation

// MARK: - User Search Response

struct UserSearchResponse: Codable {
    let users: [UserSearchResult]
    let totalCount: Int
    let limit: Int
    let offset: Int
}

// MARK: - User Search Result

struct UserSearchResult: Codable, Identifiable, Equatable {
    let id: String
    let handle: String
    let displayName: String?
    let avatarUrl: String?
    let bio: String?
    let visitCount: Int?
    let followerCount: Int?
    let isFollowing: Bool?
    
    var displayNameOrHandle: String {
        if let name = displayName, !name.isEmpty {
            return name
        }
        return handle
    }
    
    static func == (lhs: UserSearchResult, rhs: UserSearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Recent Search Data Model
// Shared model for storing recent searches across different search contexts
// Different from RecentSearchItem View in SharedComponents.swift

struct RecentSearchData: Codable, Identifiable, Equatable {
    let id: UUID
    let query: String
    let type: RecentSearchType
    let timestamp: Date
    
    // For user-specific recent searches
    let userId: String?
    let userHandle: String?
    let userDisplayName: String?
    let userAvatarUrl: String?
    
    // For place-specific recent searches
    let placeId: String?
    let placeName: String?
    let placeAddress: String?
    
    init(query: String, type: RecentSearchType) {
        self.id = UUID()
        self.query = query
        self.type = type
        self.timestamp = Date()
        self.userId = nil
        self.userHandle = nil
        self.userDisplayName = nil
        self.userAvatarUrl = nil
        self.placeId = nil
        self.placeName = nil
        self.placeAddress = nil
    }
    
    init(user: UserSearchResult) {
        self.id = UUID()
        self.query = user.handle
        self.type = .user
        self.timestamp = Date()
        self.userId = user.id
        self.userHandle = user.handle
        self.userDisplayName = user.displayName
        self.userAvatarUrl = user.avatarUrl
        self.placeId = nil
        self.placeName = nil
        self.placeAddress = nil
    }
    
    init(place: PlaceSearchResult) {
        self.id = UUID()
        self.query = place.displayName
        self.type = .place
        self.timestamp = Date()
        self.userId = nil
        self.userHandle = nil
        self.userDisplayName = nil
        self.userAvatarUrl = nil
        self.placeId = place.dbPlaceId ?? place.applePlaceId ?? place.googlePlaceId
        self.placeName = place.displayName
        self.placeAddress = place.formattedAddress
    }
    
    static func == (lhs: RecentSearchData, rhs: RecentSearchData) -> Bool {
        lhs.id == rhs.id
    }
}

enum RecentSearchType: String, Codable {
    case query
    case user
    case place
}
