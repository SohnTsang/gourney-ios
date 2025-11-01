// Models/EdgeFunctionModels.swift
// Shared models for edge function responses

import Foundation

// MARK: - Visit Response Models

struct EdgeFunctionVisit: Codable, Identifiable {
    let id: String
    let userId: String
    let rating: Int?
    let comment: String?
    let photoUrls: [String]
    let visitedAt: String
    let userHandle: String
    let userDisplayName: String?
    let userAvatarUrl: String?
    let likesCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case rating
        case comment
        case photoUrls = "photo_urls"
        case visitedAt = "visited_at"
        case userHandle = "user_handle"
        case userDisplayName = "user_display_name"
        case userAvatarUrl = "user_avatar_url"
        case likesCount = "likes_count"
    }
}

struct EdgeFunctionVisitsResponse: Codable {
    let visits: [EdgeFunctionVisit]
}

struct PlaceVisitsResponse: Codable {
    let place: PlaceInfo
    let visits: [EdgeFunctionVisit]
    let nextCursor: String?
    let visitCount: Int
    
    enum CodingKeys: String, CodingKey {
        case place
        case visits
        case nextCursor = "next_cursor"
        case visitCount = "visit_count"
    }
}

struct PlaceInfo: Codable {
    let id: String
}
