// ViewModels/DiscoverViewModel.swift
// ✅ UPDATED: Only show places with visits (visitCount > 0)
// ✅ Tier 2 Apple MapKit search commented out

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

    // MARK: - Search Places
    
    func searchPlaces(query: String, mapCenter: CLLocationCoordinate2D) async {
        guard !query.isEmpty else {
            await aggressiveCleanup()
            return
        }
        
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
        
        // TIER 1: Database Search (Only places with visits)
        do {
            let requestBody: [String: Any] = [
                "query": query,
                "lat": mapCenter.latitude,
                "lng": mapCenter.longitude,
                "radius": 2000,
                "limit": 20
            ]
            
            let response: SearchPlacesResponse = try await client.post(
                path: "/functions/v1/places-search-external",
                body: requestBody
            )
            
            // ✅ Only show places that exist in DB (have visits)
            let dbResults = response.results.filter { $0.existsInDb }
            
            beenToPlaces = dbResults.compactMap { result -> PlaceWithVisits? in
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
                    avgRating: nil,
                    visitCount: nil,
                    userRatingsTotal: nil,
                    phone: nil,
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
        
        // ============================================================
        // TIER 2: Apple MapKit Search - COMMENTED OUT
        // Only show places with visits from database
        // ============================================================
        /*
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
        */
        // ============================================================
        
        print("✅ [Search] Complete!")
        print("   🔴 DB (red): \(beenToPlaces.count)")
        print("   🟠 Apple (orange): \(searchResults.count)")
        print("   📊 Total: \(beenToPlaces.count + searchResults.count)")
        
        isSearching = false
        MemoryDebugHelper.shared.logMemory(tag: "✅ After Search")
    }
    
    func triggerSearch(query: String, mapCenter: CLLocationCoordinate2D) {
        searchTask?.cancel()
        prepareForNewSearch()
        searchTask = Task {
            await searchPlaces(query: query, mapCenter: mapCenter)
        }
    }
    
    func clearSearch() {
        print("🧹 [Search] Clearing...")
        Task {
            await aggressiveCleanup()
            await fetchBeenToPlaces()  // ✅ No 'in:' needed here since region is optional
            MemoryDebugHelper.shared.logMemory(tag: "🧹 After Cleanup")
        }
    }
    
    private func prepareForNewSearch() {
        searchResults.removeAll(keepingCapacity: false)
        beenToPlaces.removeAll(keepingCapacity: false)
        selectedPlace = nil
        showPlaceInfo = false
        hasActiveSearch = false
    }
    
    private func aggressiveCleanup() async {
        searchResults.removeAll(keepingCapacity: false)
        beenToPlaces.removeAll(keepingCapacity: false)
        selectedPlace = nil
        showPlaceInfo = false
        hasActiveSearch = false
        lastSearchQuery = ""
        lastSearchCenter = nil
        isSearching = false
        error = nil
    }
    
    func fetchBeenToPlaces(in region: MKCoordinateRegion? = nil) async {
        guard searchResults.isEmpty && !isSearching else { return }
        
        print("🗺️ [Fetch] Fetching places...")
        
        isLoading = true
        error = nil
        
        let oldCount = beenToPlaces.count
        beenToPlaces.removeAll(keepingCapacity: false)
        print("   🧹 Cleared \(oldCount) old places")
        
        do {
            let mapRegion = region ?? MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
                span: MKCoordinateSpan(latitudeDelta: 0.16, longitudeDelta: 0.1)
            )
            
            let requestBody: [String: Any] = [
                "lat": mapRegion.center.latitude,
                "lng": mapRegion.center.longitude,
                "latDelta": mapRegion.span.latitudeDelta,
                "lngDelta": mapRegion.span.longitudeDelta,
                "limit": 50
            ]
            
            struct PlacesResponse: Codable {
                let places: [Place]
            }
            
            let placesResponse: PlacesResponse = try await client.post(
                path: "/functions/v1/places-nearby",
                body: requestBody
            )
            
            print("✅ [Discover] Decoded \(placesResponse.places.count) places")
            
            var enrichedPlaces = placesResponse.places
            for (index, place) in enrichedPlaces.enumerated() {
                if place.nameEn == nil && place.nameJa == nil && place.nameZh == nil,
                   let googlePlaceId = place.googlePlaceId {
                    print("🔍 [Enrich] Fetching details for Google place: \(googlePlaceId)")
                    do {
                        let details = try await GooglePlaceDetailFetcher.shared.fetchDetails(googlePlaceId: googlePlaceId)
                        
                        enrichedPlaces[index] = Place(
                            id: place.id,
                            provider: place.provider,
                            googlePlaceId: place.googlePlaceId,
                            applePlaceId: place.applePlaceId,
                            nameEn: details.nameEn ?? details.name,
                            nameJa: details.nameJa,
                            nameZh: details.nameZh,
                            lat: place.lat,
                            lng: place.lng,
                            formattedAddress: details.address,
                            categories: details.categories ?? place.categories,
                            photoUrls: details.photos ?? place.photoUrls,
                            openNow: details.openingHours?.openNow,
                            priceLevel: details.priceLevel ?? place.priceLevel,
                            avgRating: place.avgRating ?? details.rating,
                            visitCount: place.visitCount,
                            userRatingsTotal: details.userRatingsTotal,
                            phone: details.phone ?? place.phone,
                            website: details.website ?? place.website,
                            openingHours: details.openingHours?.weekdayText,
                            createdAt: place.createdAt,
                            updatedAt: place.updatedAt
                        )
                        print("✅ [Enrich] Updated: \(details.name)")
                    } catch {
                        print("⚠️ [Enrich] Failed for \(googlePlaceId): \(error)")
                    }
                }
            }
            
            beenToPlaces = enrichedPlaces
                .filter { ($0.visitCount ?? 0) > 0 }
                .map { place in
                    PlaceWithVisits(
                        place: place,
                        visitCount: place.visitCount ?? 0,
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
                URLQueryItem(name: "select", value: "id,provider,google_place_id,apple_place_id,name_en,name_ja,name_zh,lat,lng,city,ward,categories,phone,website,address,avg_rating,visit_count,created_at,updated_at")
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
            await fetchBeenToPlaces()  // ✅ No 'in:' needed here
        }
    }
    
    func forceCleanup() {
        searchTask?.cancel()
        prepareForNewSearch()
    }
    
    // MARK: - Refresh Single Place
    
    func refreshPlace(placeId: String) async {
        print("🔄 [Refresh] Updating place: \(placeId)")
        
        do {
            let queryItems = [
                URLQueryItem(name: "id", value: "eq.\(placeId)"),
                URLQueryItem(name: "select", value: "id,provider,google_place_id,apple_place_id,name_en,name_ja,name_zh,lat,lng,city,ward,categories,avg_rating,visit_count,phone,website,address,created_at,updated_at")
            ]
            
            let places: [Place] = try await client.get(
                path: "/rest/v1/places",
                queryItems: queryItems
            )
            
            guard let updatedPlace = places.first else {
                print("⚠️ [Refresh] Place not found: \(placeId)")
                return
            }
            
            if let index = beenToPlaces.firstIndex(where: { $0.place.id == placeId }) {
                let oldItem = beenToPlaces[index]
                beenToPlaces[index] = PlaceWithVisits(
                    place: updatedPlace,
                    visitCount: oldItem.visitCount,
                    friendVisitCount: oldItem.friendVisitCount,
                    visits: oldItem.visits
                )
                print("✅ [Refresh] Updated in beenToPlaces")
            }
            
            if selectedPlace?.id == placeId {
                selectedPlace = updatedPlace
                print("✅ [Refresh] Updated selectedPlace")
            }
            
            print("✅ [Refresh] Place \(placeId) refreshed successfully")
            
        } catch {
            print("❌ [Refresh] Failed: \(error)")
        }
    }
}
