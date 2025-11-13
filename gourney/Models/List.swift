// Models/RestaurantList.swift
// ✅ FIXED: No CodingKeys needed - SupabaseClient auto-converts snake_case

import Foundation

struct RestaurantList: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let visibility: String
    let itemCount: Int?
    let coverPhotoUrl: String?
    let createdAt: String
    
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
