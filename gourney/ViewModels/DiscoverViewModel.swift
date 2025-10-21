// ViewModels/DiscoverViewModel.swift
// ✅ AGGRESSIVE MEMORY CLEANUP VERSION

import Foundation
import CoreLocation
import MapKit
import Combine

@MainActor
class DiscoverViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var beenToPlaces: [PlaceWithVisits] = []
    @Published var searchResults: [PlaceSearchResult] = []
    private var lastSearchQuery: String?
    private var lastSearchCenter: CLLocationCoordinate2D?
    private var searchTask: Task<Void, Never>?

    @Published var isLoading = false
    @Published var isSearching = false
    @Published var error: String?
    @Published var showFollowingOnly = false
    @Published var selectedPlace: Place?
    @Published var showPlaceInfo = false
    @Published var hasActiveSearch = false
    
    // MARK: - Private Properties
    private let client = SupabaseClient.shared
    private var lastSearchQuery: String = ""
    private var lastSearchCenter: CLLocationCoordinate2D?
    
    // MARK: - Search Places (HYBRID) - ✅ WITH AGGRESSIVE CLEANUP
    
    func searchPlaces(query: String, mapCenter: CLLocationCoordinate2D) async {
        guard !query.isEmpty else {
            // ✅ AGGRESSIVE CLEANUP on empty query
            await aggressiveCleanup()
            return
        }
        
        // Always run a fresh search on explicit user action
        searchTask?.cancel()
        searchTask = Task { await self.aggressiveCleanup() }

        // reset “last” AFTER the cleanup so we truly perform the new search
        lastSearchQuery = query
        lastSearchCenter = mapCenter

        
        
        // ✅ FORCE CLEANUP before new search
        print("🧹 [Search] Force cleanup BEFORE new search")
        MemoryDebugHelper.shared.logMemory(tag: "🧹 Before Search Cleanup")
        
        // Clear old results IMMEDIATELY
        searchResults = []
        beenToPlaces = []
        selectedPlace = nil
        showPlaceInfo = false
        
        // Force memory release
        searchResults.reserveCapacity(0)
        beenToPlaces.reserveCapacity(0)
        
        MemoryDebugHelper.shared.logMemory(tag: "🧹 After Search Cleanup")
        
        lastSearchQuery = query
        lastSearchCenter = mapCenter
        
        isSearching = true
        error = nil
        
        print("🔎 [Search] NEW SEARCH: '\(query)' at (\(mapCenter.latitude), \(mapCenter.longitude))")
        
        var allResults: [PlaceSearchResult] = []
        
        // TIER 1: Database Search
        do {
            guard !mapCenter.latitude.isNaN && !mapCenter.longitude.isNaN else {
                isSearching = false
                return
            }

            let requestBody: [String: Any] = [
                "query": query,
                "lat": mapCenter.latitude,
                "lng": mapCenter.longitude,
                "radius": 5000,
                "limit": 5
            ]
            
            let response: SearchPlacesResponse = try await client.post(
                path: "/functions/v1/places-search-external",
                body: requestBody
            )
            
            allResults.append(contentsOf: response.results)
            print("✅ [Tier 1] Found \(response.results.count) database results")
            
        } catch {
            print("⚠️ [Tier 1] Database search failed: \(error)")
        }
        
        // TIER 2: Apple MapKit (if < 5)
        if allResults.count < 5 {
            let region = MKCoordinateRegion(
                center: mapCenter,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            
            do {
                let appleResults = try await AppleMapKitService.shared.searchPlaces(
                    query: query,
                    region: region
                )
                                
                let needed = min(5 - allResults.count, appleResults.count)
                
                let appleSearchResults = appleResults.prefix(needed).map { apple in
                    PlaceSearchResult(
                        source: .apple,
                        googlePlaceId: nil,
                        applePlaceId: apple.applePlaceId,
                        nameEn: apple.name,
                        nameJa: apple.nameJa,
                        nameZh: apple.nameZh,
                        lat: apple.lat,
                        lng: apple.lng,
                        formattedAddress: apple.address,
                        categories: apple.categories,
                        photoUrls: nil,
                        existsInDb: false,
                        dbPlaceId: nil,
                        appleFullData: ApplePlaceData(
                            applePlaceId: apple.applePlaceId,
                            name: apple.name,
                            nameJa: apple.nameJa,
                            nameZh: apple.nameZh,
                            address: apple.address,
                            city: apple.city,
                            ward: apple.ward,
                            lat: apple.lat,
                            lng: apple.lng,
                            phone: apple.phone,
                            website: apple.website,
                            categories: apple.categories
                        )
                    )
                }
                
                allResults.append(contentsOf: appleSearchResults)
                
            } catch {
                print("⚠️ [Tier 2] Apple search failed: \(error)")
            }
        }
        
        searchResults = Array(allResults.prefix(5))
        hasActiveSearch = true
        
        print("✅ [Discover] Total results: \(searchResults.count)")
        MemoryDebugHelper.shared.logMemory(tag: "✅ After New Search")
        
        isSearching = false
    }
    
    func triggerSearch(query: String, mapCenter: CLLocationCoordinate2D) {
        Task {
            await searchPlaces(query: query, mapCenter: mapCenter)
        }
    }
    
    // MARK: - Clear Search - ✅ WITH AGGRESSIVE CLEANUP
    
    func clearSearch() {
        print("🧹 [Search] Clearing search...")
        MemoryDebugHelper.shared.logMemory(tag: "🧹 Before Clear")
        
        Task {
            await aggressiveCleanup()
            MemoryDebugHelper.shared.logMemory(tag: "✅ After Clear")
            
            await fetchBeenToPlaces()
        }
    }
    
    // MARK: - ✅ NEW: Aggressive Cleanup
    
    private func aggressiveCleanup() async {
        // 1. Clear all data
        searchResults.removeAll(keepingCapacity: false)
        beenToPlaces.removeAll(keepingCapacity: false)
        selectedPlace = nil
        showPlaceInfo = false
        hasActiveSearch = false
        error = nil
        lastSearchQuery = ""
        lastSearchCenter = nil
        
        // 2. Force deallocation by setting to empty arrays
        searchResults = []
        beenToPlaces = []
        
        // 3. Release capacity
        searchResults.reserveCapacity(0)
        beenToPlaces.reserveCapacity(0)
        
        print("✅ [Cleanup] Aggressive cleanup complete")
    }
    
    // MARK: - Fetch "Been To" Places
    
    func fetchBeenToPlaces(in region: MKCoordinateRegion? = nil) async {
        guard searchResults.isEmpty && !isSearching else {
            return
        }
        
        isLoading = true
        error = nil
        
        // ✅ Clear before fetching
        beenToPlaces.removeAll(keepingCapacity: false)
        
        do {
            var queryItems = [
                URLQueryItem(name: "select", value: "id,provider,google_place_id,apple_place_id,name_en,name_ja,name_zh,lat,lng,city,ward,categories,created_at,updated_at"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "50")
            ]
            
            if let region = region {
                let latDelta = region.span.latitudeDelta / 2
                let lngDelta = region.span.longitudeDelta / 2
                
                let minLat = region.center.latitude - latDelta
                let maxLat = region.center.latitude + latDelta
                let minLng = region.center.longitude - lngDelta
                let maxLng = region.center.longitude + lngDelta
                
                queryItems.append(URLQueryItem(name: "lat", value: "gte.\(minLat)"))
                queryItems.append(URLQueryItem(name: "lat", value: "lte.\(maxLat)"))
                queryItems.append(URLQueryItem(name: "lng", value: "gte.\(minLng)"))
                queryItems.append(URLQueryItem(name: "lng", value: "lte.\(maxLng)"))
            }
            
            if showFollowingOnly {
                beenToPlaces = []
                isLoading = false
                return
            }
            
            let places: [Place] = try await client.get(
                path: "/rest/v1/places",
                queryItems: queryItems
            )
            
            beenToPlaces = places.map { place in
                PlaceWithVisits(
                    place: place,
                    visitCount: 0,
                    friendVisitCount: 0,
                    visits: []
                )
            }
            
        } catch let urlError as URLError where urlError.code == .cancelled {
            print("ℹ️ [Discover] Request cancelled")
        } catch {
            print("❌ [Discover] Error: \(error)")
            self.error = "Failed to load places"
        }
        
        isLoading = false
    }
    
    // MARK: - Select Place
    
    func selectPlace(_ place: Place) {
        selectedPlace = place
        showPlaceInfo = true
    }
    
    func selectSearchResult(_ result: PlaceSearchResult) async {
        if result.existsInDb, let placeId = result.dbPlaceId {
            await fetchPlaceDetails(placeId: placeId)
        }
    }
    
    func fetchPlaceDetails(placeId: String) async {
        do {
            let queryItems = [
                URLQueryItem(name: "id", value: "eq.\(placeId)"),
                URLQueryItem(name: "select", value: "id,provider,google_place_id,apple_place_id,name_en,name_ja,name_zh,lat,lng,city,ward,categories,created_at,updated_at")
            ]
            
            let places: [Place] = try await client.get(
                path: "/rest/v1/places",
                queryItems: queryItems
            )
            
            if let place = places.first {
                selectedPlace = place
                showPlaceInfo = true
            }
        } catch {
            self.error = "Failed to load place details"
        }
    }
    
    func toggleFollowingFilter() {
        showFollowingOnly.toggle()
        Task {
            await fetchBeenToPlaces()
        }
    }
    
    // MARK: - Force Cleanup - ✅ UPDATED
    
    func forceCleanup() {
        print("🧹 [ViewModel] Force cleanup started...")
        
        Task {
            await aggressiveCleanup()
        }
        
        print("✅ [ViewModel] Force cleanup complete")
    }
    private func stableIdForResult(_ r: PlaceSearchResult) -> String {
        if let id = r.dbPlaceId { return "db:\(id)" }
        if let a  = r.applePlaceId { return "apple:\(a)" }
        if let g  = r.googlePlaceId { return "google:\(g)" }
        return "tmp:\(r.lat),\(r.lng)"
    }

    
}



// Build a temporary Place from a search result (used by the view)
extension PlaceSearchResult {
    func asEphemeralPlace() -> Place {
        Place(
            id: self.dbPlaceId ?? (self.applePlaceId ?? (self.googlePlaceId ?? UUID().uuidString)),
            provider: self.source == .apple ? .apple : (self.source == .google ? .google : .database),
            googlePlaceId: self.googlePlaceId,
            applePlaceId: self.applePlaceId,
            nameEn: self.nameEn, nameJa: self.nameJa, nameZh: self.nameZh,
            lat: self.lat, lng: self.lng,
            formattedAddress: self.formattedAddress,
            categories: self.categories,
            photoUrls: self.photoUrls,
            openNow: nil, priceLevel: nil, rating: nil, userRatingsTotal: nil,
            phoneNumber: nil, website: nil, openingHours: nil,
            createdAt: nil, updatedAt: nil
        )
    }
}
