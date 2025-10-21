// Models/Place.swift
// DEBUG VERSION - Manual decoder with logging

import Foundation
import CoreLocation

struct Place: Identifiable {
    let id: String
    let provider: PlaceProvider
    let googlePlaceId: String?
    let applePlaceId: String?
    let nameEn: String?
    let nameJa: String?
    let nameZh: String?
    let lat: Double
    let lng: Double
    let formattedAddress: String?
    let categories: [String]?
    let photoUrls: [String]?
    let openNow: Bool?
    let priceLevel: Int?
    let rating: Double?
    let userRatingsTotal: Int?
    let phoneNumber: String?
    let website: String?
    let openingHours: [String]?
    let createdAt: String?
    let updatedAt: String?
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    
    var displayName: String {
        let locale = Locale.current.identifier
        
        if locale.hasPrefix("ja") {
            if let ja = nameJa { return ja }
            if let en = nameEn { return en }
            if let zh = nameZh { return zh }
        }
        else if locale.hasPrefix("zh") {
            if let zh = nameZh { return zh }
            if let en = nameEn { return en }
            if let ja = nameJa { return ja }
        }
        else {
            if let en = nameEn { return en }
            if let ja = nameJa { return ja }
            if let zh = nameZh { return zh }
        }
        
        return "Unknown Place"
    }
    
    var primaryPhoto: String? {
        photoUrls?.first
    }
}

// Manual Codable implementation with DEBUG logging
extension Place: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode required fields
        id = try container.decode(String.self, forKey: .id)
        provider = try container.decode(PlaceProvider.self, forKey: .provider)
        lat = try container.decode(Double.self, forKey: .lat)
        lng = try container.decode(Double.self, forKey: .lng)
        
        // Decode optional fields WITH LOGGING
        googlePlaceId = try? container.decodeIfPresent(String.self, forKey: .googlePlaceId)
        applePlaceId = try? container.decodeIfPresent(String.self, forKey: .applePlaceId)
        
        // NAME FIELDS - with debug logging
        if let name = try? container.decodeIfPresent(String.self, forKey: .nameEn) {
            nameEn = name
        } else {
            nameEn = nil
        }
        
        nameJa = try? container.decodeIfPresent(String.self, forKey: .nameJa)
        nameZh = try? container.decodeIfPresent(String.self, forKey: .nameZh)
        formattedAddress = try? container.decodeIfPresent(String.self, forKey: .formattedAddress)
        categories = try? container.decodeIfPresent([String].self, forKey: .categories)
        photoUrls = try? container.decodeIfPresent([String].self, forKey: .photoUrls)
        openNow = try? container.decodeIfPresent(Bool.self, forKey: .openNow)
        priceLevel = try? container.decodeIfPresent(Int.self, forKey: .priceLevel)
        rating = try? container.decodeIfPresent(Double.self, forKey: .rating)
        userRatingsTotal = try? container.decodeIfPresent(Int.self, forKey: .userRatingsTotal)
        phoneNumber = try? container.decodeIfPresent(String.self, forKey: .phoneNumber)
        website = try? container.decodeIfPresent(String.self, forKey: .website)
        openingHours = try? container.decodeIfPresent([String].self, forKey: .openingHours)
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case provider
        case googlePlaceId
        case applePlaceId
        case nameEn
        case nameJa
        case nameZh
        case lat
        case lng
        case formattedAddress
        case categories
        case photoUrls
        case openNow
        case priceLevel
        case rating
        case userRatingsTotal
        case phoneNumber
        case website
        case openingHours
        case createdAt
        case updatedAt
    }
}


enum PlaceProvider: String, Codable {
    case google, apple, manual, ugc
}

struct PlaceWithVisits: Codable, Identifiable, Equatable {
    static func == (lhs: PlaceWithVisits, rhs: PlaceWithVisits) -> Bool {
        lhs.id == rhs.id
    }
    let place: Place
    let visitCount: Int
    let friendVisitCount: Int
    let visits: [Visit]
    var id: String { place.id }
}

enum PlaceSource: String, Codable {
    case google, apple, database
}

struct PlaceSearchResult: Codable, Identifiable, Equatable {
    var id: UUID
    let source: PlaceSource
    let googlePlaceId: String?
    let applePlaceId: String?
    let nameEn: String?
    let nameJa: String?
    let nameZh: String?
    let lat: Double
    let lng: Double
    let formattedAddress: String?
    let categories: [String]?
    let photoUrls: [String]?
    let existsInDb: Bool
    let dbPlaceId: String?
    let appleFullData: ApplePlaceData?
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    
    var displayName: String {
        let locale = Locale.current.identifier
        if locale.hasPrefix("ja"), let ja = nameJa { return ja }
        if locale.hasPrefix("zh"), let zh = nameZh { return zh }
        return nameEn ?? nameJa ?? nameZh ?? "Unknown"
    }
    
    static func == (lhs: PlaceSearchResult, rhs: PlaceSearchResult) -> Bool {
        lhs.id == rhs.id
    }
    
    // Custom initializer for manual creation (Apple MapKit)
    init(
        source: PlaceSource,
        googlePlaceId: String?,
        applePlaceId: String?,
        nameEn: String?,
        nameJa: String?,
        nameZh: String?,
        lat: Double,
        lng: Double,
        formattedAddress: String?,
        categories: [String]?,
        photoUrls: [String]?,
        existsInDb: Bool,
        dbPlaceId: String?,
        appleFullData: ApplePlaceData?
    ) {
        self.id = UUID()
        self.source = source
        self.googlePlaceId = googlePlaceId
        self.applePlaceId = applePlaceId
        self.nameEn = nameEn
        self.nameJa = nameJa
        self.nameZh = nameZh
        self.lat = lat
        self.lng = lng
        self.formattedAddress = formattedAddress
        self.categories = categories
        self.photoUrls = photoUrls
        self.existsInDb = existsInDb
        self.dbPlaceId = dbPlaceId
        self.appleFullData = appleFullData
    }
    
    // Custom decoder
    enum CodingKeys: String, CodingKey {
        case source, googlePlaceId, applePlaceId, nameEn, nameJa, nameZh
        case lat, lng, formattedAddress, categories, photoUrls
        case existsInDb, dbPlaceId, appleFullData
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.source = try container.decode(PlaceSource.self, forKey: .source)
        self.googlePlaceId = try? container.decodeIfPresent(String.self, forKey: .googlePlaceId)
        self.applePlaceId = try? container.decodeIfPresent(String.self, forKey: .applePlaceId)
        self.nameEn = try? container.decodeIfPresent(String.self, forKey: .nameEn)
        self.nameJa = try? container.decodeIfPresent(String.self, forKey: .nameJa)
        self.nameZh = try? container.decodeIfPresent(String.self, forKey: .nameZh)
        self.lat = try container.decode(Double.self, forKey: .lat)
        self.lng = try container.decode(Double.self, forKey: .lng)
        self.formattedAddress = try? container.decodeIfPresent(String.self, forKey: .formattedAddress)
        self.categories = try? container.decodeIfPresent([String].self, forKey: .categories)
        self.photoUrls = try? container.decodeIfPresent([String].self, forKey: .photoUrls)
        self.existsInDb = try container.decode(Bool.self, forKey: .existsInDb)
        self.dbPlaceId = try? container.decodeIfPresent(String.self, forKey: .dbPlaceId)
        self.appleFullData = try? container.decodeIfPresent(ApplePlaceData.self, forKey: .appleFullData)
    }
}

struct SearchPlacesRequest: Encodable {
    let query: String
    let latitude: Double
    let longitude: Double
    let radius: Int
    let limit: Int
}

struct SearchPlacesResponse: Codable {
    let results: [PlaceSearchResult]
    let count: Int
}
