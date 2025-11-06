// Models/Place.swift
// ✅ FIXED: Use correct DB field names

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
    let avgRating: Double?        // ✅ FIXED: was 'rating'
    let visitCount: Int?           // ✅ ADDED
    let userRatingsTotal: Int?
    let phone: String?             // ✅ FIXED: was 'phoneNumber'
    let website: String?
    let openingHours: [String]?
    let createdAt: String?
    let updatedAt: String?
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    
    // ✅ For backwards compatibility
    var rating: Double? { avgRating }
    var phoneNumber: String? { phone }
    
    var displayName: String {
        let locale = Locale.current.identifier
        
        if locale.hasPrefix("ja") {
            if let ja = nameJa, !ja.isEmpty { return ja }
            if let en = nameEn, !en.isEmpty { return en }
            if let zh = nameZh, !zh.isEmpty { return zh }
        }
        else if locale.hasPrefix("zh") {
            if let zh = nameZh, !zh.isEmpty { return zh }
            if let en = nameEn, !en.isEmpty { return en }
            if let ja = nameJa, !ja.isEmpty { return ja }
        }
        else {
            if let en = nameEn, !en.isEmpty { return en }
            if let ja = nameJa, !ja.isEmpty { return ja }
            if let zh = nameZh, !zh.isEmpty { return zh }
        }
        
        return "Unknown Place"
    }
    
    var primaryPhoto: String? {
        photoUrls?.first
    }
}

// Manual Codable implementation
extension Place: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        provider = try container.decode(PlaceProvider.self, forKey: .provider)
        lat = try container.decode(Double.self, forKey: .lat)
        lng = try container.decode(Double.self, forKey: .lng)
        
        googlePlaceId = try? container.decodeIfPresent(String.self, forKey: .googlePlaceId)
        applePlaceId = try? container.decodeIfPresent(String.self, forKey: .applePlaceId)
        nameEn = try? container.decodeIfPresent(String.self, forKey: .nameEn)
        nameJa = try? container.decodeIfPresent(String.self, forKey: .nameJa)
        nameZh = try? container.decodeIfPresent(String.self, forKey: .nameZh)
        formattedAddress = try? container.decodeIfPresent(String.self, forKey: .formattedAddress)
        categories = try? container.decodeIfPresent([String].self, forKey: .categories)
        photoUrls = try? container.decodeIfPresent([String].self, forKey: .photoUrls)
        openNow = try? container.decodeIfPresent(Bool.self, forKey: .openNow)
        priceLevel = try? container.decodeIfPresent(Int.self, forKey: .priceLevel)
        avgRating = try? container.decodeIfPresent(Double.self, forKey: .avgRating)
        visitCount = try? container.decodeIfPresent(Int.self, forKey: .visitCount)
        userRatingsTotal = try? container.decodeIfPresent(Int.self, forKey: .userRatingsTotal)
        phone = try? container.decodeIfPresent(String.self, forKey: .phone)
        website = try? container.decodeIfPresent(String.self, forKey: .website)
        openingHours = try? container.decodeIfPresent([String].self, forKey: .openingHours)
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try? container.decodeIfPresent(String.self, forKey: .updatedAt)
                
        // DEBUG LOGS
        print("🔍 [Place Decode] Name: \(nameEn ?? "unknown")")
        print("   avgRating decoded: \(avgRating?.description ?? "nil")")
        print("   visitCount decoded: \(visitCount?.description ?? "nil")")
        print("   formattedAddress decoded: \(formattedAddress ?? "nil")")

        
        
    }
    
    enum CodingKeys: String, CodingKey {
        case id, provider
        case googlePlaceId
        case applePlaceId
        case nameEn, nameJa, nameZh
        case lat, lng
        case formattedAddress = "address"       // ✅ Backend sends "address"
        case categories, photoUrls
        case openNow, priceLevel
        case avgRating         // ✅ snake_case
        case visitCount      // ✅ Add mapping
        case userRatingsTotal
        case phone                              // ✅ Already correct
        case website, openingHours
        case createdAt = "created_at"           // ✅ snake_case
        case updatedAt = "updated_at"           // ✅ snake_case
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
        if locale.hasPrefix("ja"), let ja = nameJa, !ja.isEmpty { return ja }
        if locale.hasPrefix("zh"), let zh = nameZh, !zh.isEmpty { return zh }
        if let en = nameEn, !en.isEmpty { return en }
        if let ja = nameJa, !ja.isEmpty { return ja }
        if let zh = nameZh, !zh.isEmpty { return zh }
        return "Unknown"
    }
    
    static func == (lhs: PlaceSearchResult, rhs: PlaceSearchResult) -> Bool {
        lhs.id == rhs.id
    }
    
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
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(googlePlaceId, forKey: .googlePlaceId)
        try container.encodeIfPresent(applePlaceId, forKey: .applePlaceId)
        try container.encodeIfPresent(nameEn, forKey: .nameEn)
        try container.encodeIfPresent(nameJa, forKey: .nameJa)
        try container.encodeIfPresent(nameZh, forKey: .nameZh)
        try container.encode(lat, forKey: .lat)
        try container.encode(lng, forKey: .lng)
        try container.encodeIfPresent(formattedAddress, forKey: .formattedAddress)
        try container.encodeIfPresent(categories, forKey: .categories)
        try container.encodeIfPresent(photoUrls, forKey: .photoUrls)
        try container.encode(existsInDb, forKey: .existsInDb)
        try container.encodeIfPresent(dbPlaceId, forKey: .dbPlaceId)
        try container.encodeIfPresent(appleFullData, forKey: .appleFullData)
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

// ✅ Keep CompletePlace - it's correct!
struct CompletePlace {
    let id: String
    let provider: String
    let providerPlaceId: String?
    let nameEn: String?
    let nameJa: String?
    let nameZh: String?
    let formattedAddress: String?
    let phone: String?
    let website: String?
    let postalCode: String?
    let city: String?
    let ward: String?
    let country: String?
    let countryCode: String?
    let lat: Double
    let lng: Double
    let categories: [String]?
    let rating: Double?
    let visitCount: Int?
    
    init(from response: PlaceGetResponse) {
        self.id = response.id
        self.provider = response.provider
        self.providerPlaceId = response.providerPlaceId
        self.nameEn = response.nameEn
        self.nameJa = response.nameJa
        self.nameZh = response.nameZh
        
        if let formatted = response.attributes?.formattedAddress, !formatted.isEmpty {
            self.formattedAddress = formatted
        } else if let addr = response.address, !addr.isEmpty {
            self.formattedAddress = addr
        } else {
            let parts = [response.ward, response.city, response.prefectureName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            self.formattedAddress = parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
        
        if let ph = response.phone, !ph.isEmpty {
            self.phone = ph
        } else {
            self.phone = response.attributes?.phone
        }
        
        if let web = response.website, !web.isEmpty {
            self.website = web
        } else {
            self.website = response.attributes?.website
        }
        
        self.postalCode = response.postalCode
        self.city = response.city
        self.ward = response.ward
        self.country = response.country
        self.countryCode = response.countryCode
        self.lat = response.lat
        self.lng = response.lng
        self.categories = response.categories
        self.rating = response.avgRating
        self.visitCount = response.visitCount
    }
    
    var displayName: String {
        let locale = Locale.current.identifier
        
        if locale.hasPrefix("ja") {
            if let ja = nameJa, !ja.isEmpty { return ja }
            if let en = nameEn, !en.isEmpty { return en }
            if let zh = nameZh, !zh.isEmpty { return zh }
        }
        else if locale.hasPrefix("zh") {
            if let zh = nameZh, !zh.isEmpty { return zh }
            if let en = nameEn, !en.isEmpty { return en }
            if let ja = nameJa, !ja.isEmpty { return ja }
        }
        else {
            if let en = nameEn, !en.isEmpty { return en }
            if let ja = nameJa, !ja.isEmpty { return ja }
            if let zh = nameZh, !zh.isEmpty { return zh }
        }
        
        return "Unknown Place"
    }
}
