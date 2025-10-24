// ViewModels/DiscoverViewModel.swift
// ✅ COMPLETE FIX: Proper search with DB + Apple results

import Foundation
import CoreLocation
import MapKit
import Combine

@MainActor
class DiscoverViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var beenToPlaces: [PlaceWithVisits] = []
    @Published var searchResults: [PlaceSearchResult] = []
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
    private var searchTask: Task<Void, Never>?

    // MARK: - Search Places - ✅ COMPLETE FIX
    
    func searchPlaces(query: String, mapCenter: CLLocationCoordinate2D) async {
        guard !query.isEmpty else {
            await aggressiveCleanup()
            return
        }
        
        // ✅ 1. Clear old search results IMMEDIATELY
        searchResults.removeAll(keepingCapacity: false)
        beenToPlaces.removeAll(keepingCapacity: false)
        selectedPlace = nil
        showPlaceInfo = false
        
        lastSearchQuery = query
        lastSearchCenter = mapCenter
        
        isSearching = true
        error = nil
        hasActiveSearch = true
        
        print("🔎 [Search] NEW SEARCH: '\(query)'")
        
        var dbPlaceIds = Set<String>()
        
        // TIER 1: Database Search (max 20 instead of 45)
        do {
            let requestBody: [String: Any] = [
                "query": query,
                "lat": mapCenter.latitude,
                "lng": mapCenter.longitude,
                "radius": 2000,
                "limit": 20  // ✅ Reduced from 45
            ]
            
            let response: SearchPlacesResponse = try await client.post(
                path: "/functions/v1/places-search-external",
                body: requestBody
            )
            
            let dbResults = response.results.filter { $0.existsInDb }
            
            beenToPlaces = dbResults.compactMap { result in
                guard let placeId = result.dbPlaceId else { return nil }
                dbPlaceIds.insert(placeId)
                
                let place = Place(
                    id: placeId,
                    provider: result.source == .apple ? .apple : .google,
                    googlePlaceId: result.googlePlaceId,
                    applePlaceId: result.applePlaceId,
                    nameEn: result.nameEn,
                    nameJa: result.nameJa,
                    nameZh: result.nameZh,
                    lat: result.lat,
                    lng: result.lng,
                    formattedAddress: result.formattedAddress,
                    categories: result.categories,
                    photoUrls: result.photoUrls,
                    openNow: nil,
                    priceLevel: nil,
                    rating: nil,
                    userRatingsTotal: nil,
                    phoneNumber: nil,
                    website: nil,
                    openingHours: nil,
                    createdAt: nil,
                    updatedAt: nil
                )
                
                return PlaceWithVisits(
                    place: place,
                    visitCount: 0,
                    friendVisitCount: 0,
                    visits: []
                )
            }
            
        } catch {
            print("⚠️ [Tier 1] Failed: \(error)")
        }
        
        // ✅ TIER 2: Apple MapKit (ALWAYS)
        print("🎯 [Tier 2] Searching Apple Maps for: '\(query)'")
        
        let mapSpan = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        let region = MKCoordinateRegion(center: mapCenter, span: mapSpan)
        
        do {
            let appleResults = try await AppleMapKitService.shared.searchPlaces(
                query: query,
                region: region,
                maxResults: 10
            )
            
            print("🎯 [Tier 2] Apple returned \(appleResults.count) raw results")
            
            // Filter: in bounds + not in DB
            let filteredApple = appleResults.filter { apple in
                let latDiff = abs(apple.lat - mapCenter.latitude)
                let lngDiff = abs(apple.lng - mapCenter.longitude)
                let inBounds = latDiff < 0.01 && lngDiff < 0.01
                
                let notInDB = !beenToPlaces.contains { pv in
                    abs(pv.place.lat - apple.lat) < 0.0001 &&
                    abs(pv.place.lng - apple.lng) < 0.0001
                }
                
                return inBounds && notInDB
            }
            
            print("🎯 [Tier 2] After filtering: \(filteredApple.count) new places")
            
            searchResults = filteredApple.prefix(5).map { apple in
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
            
            print("✅ [Tier 2] Added \(searchResults.count) Apple results")
            
        } catch {
            print("⚠️ [Tier 2] Failed: \(error)")
        }
        
        print("✅ [Search] Complete!")
        print("   📍 DB (red): \(beenToPlaces.count)")
        print("   🔍 Apple (orange): \(searchResults.count)")
        print("   📊 Total: \(beenToPlaces.count + searchResults.count)")
        
        
        isSearching = false
        MemoryDebugHelper.shared.logMemory(tag: "✅ After Search")

    }
    
    func triggerSearch(query: String, mapCenter: CLLocationCoordinate2D) {
        searchTask?.cancel()
        prepareForNewSearch()

        searchTask = Task {  // ✅ Remove [weak self]
            await searchPlaces(query: query, mapCenter: mapCenter)
        }
    }
    
    // MARK: - Clear Search
    
    func clearSearch() {
        print("🧹 [Search] Clearing...")
        
        Task {
            await aggressiveCleanup()
            await fetchBeenToPlaces()
            
            // ✅ Force memory release
            MemoryDebugHelper.shared.logMemory(tag: "🧹 After Cleanup")
        }
    }

    
    private func prepareForNewSearch() {
        print("🧹 [Prepare] Cleaning before new search...")
        print("   Current searchResults: \(searchResults.count)")
        print("   Current beenToPlaces: \(beenToPlaces.count)")
        
        searchResults.removeAll(keepingCapacity: false)
        beenToPlaces.removeAll(keepingCapacity: false)
        error = nil
        hasActiveSearch = false
        
        print("   ✅ Cleared for new search")
    }
    
    private func aggressiveCleanup() async {
        // ✅ Clear everything and drop capacity
        searchResults.removeAll(keepingCapacity: false)
        beenToPlaces.removeAll(keepingCapacity: false)
        selectedPlace = nil
        showPlaceInfo = false
        hasActiveSearch = false
        error = nil
        lastSearchQuery = ""
        lastSearchCenter = nil
        
        // ✅ Recreate empty arrays (forces deallocation)
        searchResults = []
        beenToPlaces = []
        
        print("✅ [Cleanup] Memory released")
    }

    
    // MARK: - Fetch "Been To" Places
    
    func fetchBeenToPlaces(in region: MKCoordinateRegion? = nil) async {
        guard searchResults.isEmpty && !isSearching else {
            return
        }
        
        print("🗺️ [Fetch] Fetching places...")
        print("   Region: \(region != nil ? "specified" : "default")")
        
        isLoading = true
        error = nil
        
        // ✅ Clear old data before fetching new
        let oldCount = beenToPlaces.count
        beenToPlaces.removeAll(keepingCapacity: false)
        print("   🧹 Cleared \(oldCount) old places")
        
        do {
            var queryItems = [
                URLQueryItem(name: "select", value: "id,provider,google_place_id,apple_place_id,name_en,name_ja,name_zh,lat,lng,city,ward,categories,created_at,updated_at"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "50")  // Keep at 50 for map
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
            print("ℹ️ [Discover] Cancelled")
        } catch {
            print("❌ [Discover] Error: \(error)")
            self.error = "Failed to load places"
        }
        
        print("   ✅ Fetched \(beenToPlaces.count) places")
        isLoading = false
        
        MemoryDebugHelper.shared.logMemory(tag: "🗺️ After Fetch")
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
    
    // MARK: - Force Cleanup
    
    func forceCleanup() {
        searchTask?.cancel()
        prepareForNewSearch()
    }
}

