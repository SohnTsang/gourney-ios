//
//  List.swift
//  gourney
//
//  Created by 曾家浩 on 2025/10/16.
//

// Models/List.swift
// Week 7 Day 1: List model matching backend schema

import Foundation

struct RestaurantList: Codable, Identifiable {
    let id: String
    let userId: String
    let title: String
    let description: String?
    let visibility: String
    let itemCount: Int?
    let coverPhotoUrl: String?
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case description
        case visibility
        case itemCount = "item_count"
        case coverPhotoUrl = "cover_photo_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ListItem: Codable, Identifiable {
    let id: String
    let listId: String
    let placeId: String
    let notes: String?
    let addedAt: Date
    
    var place: Place?
    
    enum CodingKeys: String, CodingKey {
        case id
        case listId = "list_id"
        case placeId = "place_id"
        case notes
        case addedAt = "added_at"
        case place
    }
}
