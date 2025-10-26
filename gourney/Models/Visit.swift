//
//  Visit.swift
//  gourney
//
//  Created by 曾家浩 on 2025/10/16.
//

// Models/Visit.swift
// Week 7 Day 1: Visit model matching backend schema

import Foundation

struct Visit: Codable, Identifiable {
    let id: String
    let userId: String
    let placeId: String
    let rating: Int?
    let comment: String?
    let photoUrls: [String]
    let visibility: String
    let visitedAt: Date
    let createdAt: Date
    let updatedAt: Date
    
    // Populated from joins
    var place: Place?
    var user: User?
    var likeCount: Int?
    var commentCount: Int?
    var isLiked: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case placeId = "place_id"
        case rating
        case comment
        case photoUrls = "photo_urls"
        case visibility
        case visitedAt = "visited_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case place
        case user
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case isLiked = "is_liked"
    }
}

// MARK: - OpeningHours (ADDED - This was missing!)

struct OpeningHours: Codable {
    let openNow: Bool?
    let weekdayText: [String]?
    
    enum CodingKeys: String, CodingKey {
        case openNow = "open_now"
        case weekdayText = "weekday_text"
    }
}

// MARK: - Create Visit Request

struct CreateVisitRequest: Codable {
    let placeId: String?
    let applePlaceData: ApplePlaceData?      // ✅ ADD THIS LINE
    let googlePlaceData: GooglePlaceData?
    let manualPlace: ManualPlaceData?
    let rating: Int?
    let comment: String?
    let photoUrls: [String]?
    let visibility: String
    let visitedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case placeId = "place_id"
        case applePlaceData = "apple_place_data"  // ✅ ADD THIS LINE
        case googlePlaceData = "google_place_data"
        case manualPlace = "manual_place"
        case rating
        case comment
        case photoUrls = "photo_urls"
        case visibility
        case visitedAt = "visited_at"
    }
}

// MARK: - GooglePlaceData

struct GooglePlaceData: Codable {
    let googlePlaceId: String
    let name: String
    let nameEn: String?
    let nameJa: String?
    let nameZh: String?
    let address: String
    let city: String
    let ward: String?
    let lat: Double
    let lng: Double
    let categories: [String]?
    let priceLevel: Int?
    let phone: String?
    let website: String?
    let openingHours: OpeningHours?
    let rating: Double?
    let userRatingsTotal: Int?
    let photos: [String]?
    
    enum CodingKeys: String, CodingKey {
        case googlePlaceId = "google_place_id"
        case name
        case nameEn = "name_en"
        case nameJa = "name_ja"
        case nameZh = "name_zh"
        case address
        case city
        case ward
        case lat
        case lng
        case categories
        case priceLevel = "price_level"
        case phone
        case website
        case openingHours = "opening_hours"
        case rating
        case userRatingsTotal = "user_ratings_total"
        case photos
    }
}

// MARK: - ApplePlaceData

struct ApplePlaceData: Codable {
    let applePlaceId: String
    let name: String
    let nameJa: String?
    let nameZh: String?
    let address: String
    let city: String
    let ward: String?
    let lat: Double
    let lng: Double
    let phone: String?
    let website: String?
    let categories: [String]?
    
    enum CodingKeys: String, CodingKey {
        case applePlaceId = "apple_place_id"
        case name
        case nameJa = "name_ja"
        case nameZh = "name_zh"
        case address
        case city
        case ward
        case lat
        case lng
        case phone
        case website
        case categories
    }
}

// MARK: - ManualPlaceData

struct ManualPlaceData: Codable {
    let name: String
    let nameEn: String?
    let nameJa: String?
    let nameZh: String?
    let lat: Double
    let lng: Double
    let city: String?
    let ward: String?
    let categories: [String]?
    
    enum CodingKeys: String, CodingKey {
        case name
        case nameEn = "name_en"
        case nameJa = "name_ja"
        case nameZh = "name_zh"
        case lat
        case lng
        case city
        case ward
        case categories
    }
}

// MARK: - Create Visit Response

struct CreateVisitResponse: Codable {
    let message: String
    let visitId: String
    let placeId: String
    let createdNewPlace: Bool
    let pointsEarned: Int
    let moderationNote: String?
}


