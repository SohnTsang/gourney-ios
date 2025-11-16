// Models/RestaurantList.swift
// Updated with likes_count for social features

import Foundation

struct RestaurantList: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let visibility: String
    let itemCount: Int?
    let coverPhotoUrl: String?
    let createdAt: String
    
    // TODO: Add when backend implements list_likes table
    var likesCount: Int? { return 0 }
    
    // Computed property if you need Date
    var createdDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: createdAt) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: createdAt)
    }
}

struct ListItem: Codable, Identifiable {
    let id: String
    let listId: String
    let placeId: String
    let notes: String?
    let addedAt: String
    var place: Place?
}

// MARK: - Empty Response
struct EmptyResponse: Codable {}

// MARK: - Lists Response Models
struct ListsGetResponse: Codable {
    let lists: [RestaurantList]
}

struct CreateListResponse: Codable {
    let list: RestaurantList
}

struct ListDetailResponse: Codable {
    let list: RestaurantList
    let items: [ListItem]
}
