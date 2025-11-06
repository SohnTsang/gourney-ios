// Services/GooglePlaceDetailFetcher.swift
// ✅ GOOGLE COMPLIANT - Session-only memory cache (30min TTL)
// Updated: 2025-11-05

import Foundation

// MARK: - Models

struct GooglePlaceDetails: Codable {
    let googlePlaceId: String?
    let name: String
    let nameEn: String?
    let nameJa: String?
    let nameZh: String?
    let address: String
    let city: String?
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
    
    struct OpeningHours: Codable {
        let weekdayText: [String]?
        let openNow: Bool?
        
        enum CodingKeys: String, CodingKey {
            case weekdayText = "weekday_text"
            case openNow = "open_now"
        }
    }
}

struct GooglePlaceDetailResponse: Codable {
    let place: GooglePlaceDetails
    let source: String
    let cached: Bool
}

// MARK: - Cache Entry

private struct CacheEntry {
    let details: GooglePlaceDetails
    let timestamp: Date
    
    var isExpired: Bool {
        // ✅ COMPLIANT: 30-minute session cache (not 2 hours)
        Date().timeIntervalSince(timestamp) > 1800 // 30 min
    }
}

// MARK: - Fetcher

actor GooglePlaceDetailFetcher {
    static let shared = GooglePlaceDetailFetcher()
    
    // ✅ Session-only memory cache (cleared on app termination)
    private var cache: [String: CacheEntry] = [:]
    
    private init() {}
    
    func fetchDetails(googlePlaceId: String) async throws -> GooglePlaceDetails {
        // Check session cache (performance optimization)
        if let entry = cache[googlePlaceId], !entry.isExpired {
            print("⚡ [GoogleCache] HIT (session) - \(googlePlaceId)")
            print("   📋 Cached data:")
            print("      Phone: \(entry.details.phone ?? "nil")")
            print("      Website: \(entry.details.website ?? "nil")")
            print("      Open now: \(entry.details.openingHours?.openNow?.description ?? "nil")")
            print("      Hours: \(entry.details.openingHours?.weekdayText?.count ?? 0) lines")
            return entry.details
        }
        
        // Fetch from edge function (which fetches fresh from Google API)
        print("🌐 [GoogleCache] MISS - Fetching from API")
        
        let url = "\(Config.supabaseURL)/functions/v1/places-detail-fetch"
        guard let requestURL = URL(string: url) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        if let token = SupabaseClient.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let requestBody: [String: Any] = ["google_place_id": googlePlaceId]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        // Log raw JSON for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📦 [GoogleAPI] Raw response:")
            print(jsonString)
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(GooglePlaceDetailResponse.self, from: data)
        
        // ✅ Store in session cache (30min TTL)
        cache[googlePlaceId] = CacheEntry(
            details: result.place,
            timestamp: Date()
        )
        
        print("💾 [GoogleCache] Cached (session) - Expires in 30min")
        print("✅ [GoogleAPI] Decoded:")
        print("   Name: \(result.place.name)")
        print("   Phone: \(result.place.phone ?? "nil")")
        print("   Website: \(result.place.website ?? "nil")")
        print("   Open now: \(result.place.openingHours?.openNow?.description ?? "nil")")
        print("   Hours: \(result.place.openingHours?.weekdayText?.count ?? 0) lines")
        if let hours = result.place.openingHours?.weekdayText {
            print("   📅 First hour: \(hours.first ?? "none")")
        }
        
        return result.place
    }
    
    // MARK: - Cache Management
    
    func clearExpiredCache() {
        let before = cache.count
        cache = cache.filter { !$0.value.isExpired }
        let after = cache.count
        if before != after {
            print("🧹 [GoogleCache] Cleared \(before - after) expired entries")
        }
    }
    
    func clearCache(for googlePlaceId: String) {
        cache.removeValue(forKey: googlePlaceId)
        print("🧹 [GoogleCache] Cleared cache for: \(googlePlaceId)")
    }
    
    func clearAllCache() {
        let count = cache.count
        cache.removeAll()
        print("🧹 [GoogleCache] Cleared all \(count) entries")
    }
    
    // MARK: - Memory Warning Handler
    
    func handleMemoryWarning() {
        clearAllCache()
        print("⚠️ [GoogleCache] Cleared all cache due to memory warning")
    }
}
