//
//  User.swift
//  gourney
//
//  Created by 曾家浩 on 2025/10/16.
//

// Models/User.swift - Uses automatic snake_case conversion from SupabaseClient

import Foundation

struct User: Codable, Identifiable {
    let id: String
    let handle: String
    let displayName: String
    let email: String?
    let avatarUrl: String?
    let bio: String?
    let homeCity: String?
    let language: String?
    let locale: String?
    let timezone: String?
    let scriptPreference: String?
    let role: String?
    let createdAt: String?
    let updatedAt: String?
    let deletedAt: String?
    let visitCount: Int?
    let followerCount: Int?
    let followingCount: Int?
    let points: Int?
}

// MARK: - User Profile Response
struct UserProfileResponse: Codable {
    let user: User
    let isFollowing: Bool?
    let isBlocked: Bool?
}
