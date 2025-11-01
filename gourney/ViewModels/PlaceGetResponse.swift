// Models/PlaceGetResponse.swift
// ✅ CORRECT: Matches DB schema exactly

import Foundation

// MARK: - Root Response Wrapper

struct PlaceGetResponseWrapper: Codable {
    let place: PlaceGetResponse
}

// MARK: - Place Response Model

struct PlaceGetResponse: Codable {
    let id: String
    let provider: String
    let providerPlaceId: String?
    let nameJa: String?
    let nameEn: String?
    let nameZh: String?
    let postalCode: String?
    let prefectureCode: String?
    let prefectureName: String?
    let ward: String?
    let city: String?
    let lat: Double
    let lng: Double
    let priceLevel: Int?
    let categories: [String]?
    
    // ✅ Separate columns
    let phone: String?
    let website: String?
    let address: String?
    let country: String?
    let countryCode: String?
    
    // ✅ JSONB attributes field (fallback)
    let attributes: PlaceAttributes?
    
    // ✅ Computed stats
    let avgRating: Double?
    let visitCount: Int?
    
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case providerPlaceId = "provider_place_id"
        case nameJa = "name_ja"
        case nameEn = "name_en"
        case nameZh = "name_zh"
        case postalCode = "postal_code"
        case prefectureCode = "prefecture_code"
        case prefectureName = "prefecture_name"
        case ward
        case city
        case lat
        case lng
        case priceLevel = "price_level"
        case categories
        case phone
        case website
        case address
        case country
        case countryCode = "country_code"
        case attributes
        case avgRating = "avg_rating"
        case visitCount = "visit_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Attributes (JSONB field)

struct PlaceAttributes: Codable {
    let phone: String?
    let website: String?
    let formattedAddress: String?
    let openingHours: String?
    
    enum CodingKeys: String, CodingKey {
        case phone
        case website
        case formattedAddress = "formatted_address"
        case openingHours = "opening_hours"
    }
}
