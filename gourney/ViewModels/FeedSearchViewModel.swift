// ViewModels/FeedSearchViewModel.swift
// ViewModel for FeedSearchOverlay
// Handles user search, place search, and recent searches storage
// ✅ Fixed: No auto-search, correct API params, optimized memory

import Foundation
import MapKit
import CoreLocation
import Combine

@MainActor
final class FeedSearchViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var searchQuery = ""
    @Published var selectedTab: FeedSearchTab = .users
    
    // User search
    @Published var userResults: [UserSearchResult] = []
    @Published var isLoadingUsers = false
    @Published var userSearchError: String?
    
    // Place search
    @Published var placeResults: [PlaceSearchResult] = []
    @Published var isLoadingPlaces = false
    @Published var placeSearchError: String?
    
    // Recent searches
    @Published var recentSearches: [RecentSearchData] = []
    
    // MARK: - Private Properties
    
    private var searchTask: Task<Void, Never>?
    private let appleService = AppleMapKitService.shared
    
    private let recentSearchesKey = "FeedRecentSearches"
    private let maxRecentSearches = 10
    
    // MARK: - Initialization
    
    init() {
        loadRecentSearches()
    }
    
    // MARK: - Search (Manual trigger only)
    
    func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        
        // Cancel any existing search
        searchTask?.cancel()
        
        searchTask = Task { [weak self] in
            guard let self = self else { return }
            
            switch self.selectedTab {
            case .users:
                await self.searchUsers(query: query)
            case .places:
                await self.searchPlaces(query: query)
            }
        }
    }
    
    func clearResults() {
        userResults = []
        placeResults = []
        userSearchError = nil
        placeSearchError = nil
    }
    
    func clearQuery() {
        searchQuery = ""
        clearResults()
    }
    
    // MARK: - User Search
    
    private func searchUsers(query: String) async {
        isLoadingUsers = true
        userSearchError = nil
        userResults = []
        
        do {
            let response: UserSearchResponse = try await SupabaseClient.shared.get(
                path: "/functions/v1/user-search",
                queryItems: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "limit", value: "20")
                ],
                requiresAuth: true
            )
            
            guard !Task.isCancelled else { return }
            
            userResults = response.users
            print("🔍 [UserSearch] Found \(response.users.count) users for '\(query)'")
            
        } catch {
            guard !Task.isCancelled else { return }
            print("❌ [UserSearch] Error: \(error)")
            userSearchError = "Failed to search users"
        }
        
        isLoadingUsers = false
    }
    
    // MARK: - Place Search (Same logic as SearchPlaceOverlay)
    
    private func searchPlaces(query: String) async {
        isLoadingPlaces = true
        placeSearchError = nil
        placeResults = []
        
        let userLocation = LocationManager.shared.userLocation
        let lat = userLocation?.latitude ?? 35.6762
        let lng = userLocation?.longitude ?? 139.6503
        
        var combinedResults: [PlaceSearchResult] = []
        var dbPlaceIds = Set<String>()
        
        print("🔍 [PlaceSearch] Starting search for '\(query)'")
        
        // STEP 1: Search database first
        do {
            let client = SupabaseClient.shared
            
            // ✅ FIXED: Use correct field names (lat/lng not latitude/longitude)
            let body: [String: Any] = [
                "query": query,
                "lat": lat,
                "lng": lng,
                "radius": 10000,
                "limit": 50
            ]
            
            let response: SearchPlacesResponse = try await client.post(
                path: "/functions/v1/places-search-external",
                body: body,
                requiresAuth: true
            )
            
            guard !Task.isCancelled else { return }
            
            for result in response.results {
                combinedResults.append(result)
                if let appleId = result.applePlaceId {
                    dbPlaceIds.insert(appleId)
                }
                if let dbId = result.dbPlaceId {
                    dbPlaceIds.insert(dbId)
                }
                if let googleId = result.googlePlaceId {
                    dbPlaceIds.insert(googleId)
                }
            }
            
            print("🗄️ [DB] \(response.results.count) results")
            
        } catch {
            guard !Task.isCancelled else { return }
            print("⚠️ [DB] Search failed: \(error)")
        }
        
        guard !Task.isCancelled else { return }
        
        // STEP 2: Search Apple Maps
        do {
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                latitudinalMeters: 10000,
                longitudinalMeters: 10000
            )
            
            let appleResults = try await appleService.searchPlaces(
                query: query,
                region: region,
                maxResults: 30
            )
            
            guard !Task.isCancelled else { return }
            
            print("🍎 [Apple] \(appleResults.count) results")
            
            // Deduplicate and add Apple results
            for appleResult in appleResults {
                // Skip if already in DB results
                if dbPlaceIds.contains(appleResult.applePlaceId) {
                    continue
                }
                
                // Check by location + name
                let isDuplicate = combinedResults.contains { dbResult in
                    let distance = CLLocation(latitude: dbResult.lat, longitude: dbResult.lng)
                        .distance(from: CLLocation(latitude: appleResult.lat, longitude: appleResult.lng))
                    
                    guard distance < 50 else { return false }
                    
                    let normalizedApple = appleResult.name.lowercased()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: " ", with: "")
                    
                    let normalizedDb = dbResult.displayName.lowercased()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: " ", with: "")
                    
                    return normalizedApple == normalizedDb
                }
                
                if isDuplicate { continue }
                
                let searchResult = PlaceSearchResult(
                    source: .apple,
                    googlePlaceId: nil,
                    applePlaceId: appleResult.applePlaceId,
                    nameEn: appleResult.name,
                    nameJa: appleResult.nameJa,
                    nameZh: appleResult.nameZh,
                    lat: appleResult.lat,
                    lng: appleResult.lng,
                    formattedAddress: appleResult.displayAddress,
                    categories: appleResult.categories,
                    photoUrls: nil,
                    existsInDb: false,
                    dbPlaceId: nil,
                    appleFullData: ApplePlaceData(
                        applePlaceId: appleResult.applePlaceId,
                        name: appleResult.name,
                        nameJa: appleResult.nameJa,
                        nameZh: appleResult.nameZh,
                        address: appleResult.displayAddress,
                        city: appleResult.city,
                        ward: appleResult.ward,
                        lat: appleResult.lat,
                        lng: appleResult.lng,
                        phone: appleResult.phone,
                        website: appleResult.website,
                        categories: appleResult.categories
                    )
                )
                
                combinedResults.append(searchResult)
            }
            
        } catch {
            guard !Task.isCancelled else { return }
            print("⚠️ [Apple] Search failed: \(error)")
        }
        
        guard !Task.isCancelled else { return }
        
        // Sort by distance
        let userLoc = CLLocation(latitude: lat, longitude: lng)
        let sortedResults = combinedResults.sorted { r1, r2 in
            let loc1 = CLLocation(latitude: r1.lat, longitude: r1.lng)
            let loc2 = CLLocation(latitude: r2.lat, longitude: r2.lng)
            return userLoc.distance(from: loc1) < userLoc.distance(from: loc2)
        }
        
        placeResults = sortedResults
        print("✅ [PlaceSearch] \(sortedResults.count) total results")
        
        isLoadingPlaces = false
    }
    
    // MARK: - Recent Searches
    
    private func loadRecentSearches() {
        guard let data = UserDefaults.standard.data(forKey: recentSearchesKey),
              let items = try? JSONDecoder().decode([RecentSearchData].self, from: data) else {
            recentSearches = []
            return
        }
        recentSearches = items
    }
    
    private func saveRecentSearches() {
        guard let data = try? JSONEncoder().encode(recentSearches) else { return }
        UserDefaults.standard.set(data, forKey: recentSearchesKey)
    }
    
    func addToRecentSearches(query: String) {
        // Remove existing with same query
        recentSearches.removeAll { $0.query.lowercased() == query.lowercased() && $0.type == .query }
        
        // Add new at beginning
        let item = RecentSearchData(query: query, type: .query)
        recentSearches.insert(item, at: 0)
        
        // Trim to max
        if recentSearches.count > maxRecentSearches {
            recentSearches = Array(recentSearches.prefix(maxRecentSearches))
        }
        
        saveRecentSearches()
    }
    
    func addToRecentSearches(user: UserSearchResult) {
        // Remove existing with same user ID
        recentSearches.removeAll { $0.userId == user.id }
        
        // Add new at beginning
        let item = RecentSearchData(user: user)
        recentSearches.insert(item, at: 0)
        
        // Trim to max
        if recentSearches.count > maxRecentSearches {
            recentSearches = Array(recentSearches.prefix(maxRecentSearches))
        }
        
        saveRecentSearches()
    }
    
    func addToRecentSearches(place: PlaceSearchResult) {
        // Remove existing with same place
        let placeIdentifier = place.dbPlaceId ?? place.applePlaceId ?? place.googlePlaceId
        recentSearches.removeAll { $0.placeId == placeIdentifier }
        
        // Add new at beginning
        let item = RecentSearchData(place: place)
        recentSearches.insert(item, at: 0)
        
        // Trim to max
        if recentSearches.count > maxRecentSearches {
            recentSearches = Array(recentSearches.prefix(maxRecentSearches))
        }
        
        saveRecentSearches()
    }
    
    func removeRecentSearch(_ item: RecentSearchData) {
        recentSearches.removeAll { $0.id == item.id }
        saveRecentSearches()
    }
    
    func clearAllRecentSearches() {
        recentSearches = []
        saveRecentSearches()
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        searchTask?.cancel()
        searchTask = nil
    }
    
    deinit {
        searchTask?.cancel()
    }
}

// MARK: - Search Tab Enum

enum FeedSearchTab: String, CaseIterable, Identifiable {
    case users = "Users"
    case places = "Places"
    
    var id: String { rawValue }
}
