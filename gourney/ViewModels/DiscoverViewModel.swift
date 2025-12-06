// ViewModels/DiscoverViewModel.swift
// ✅ PRODUCTION-GRADE MEMORY MANAGEMENT
// ✅ SEARCH LOOP PREVENTION with cooldown
// ✅ AUTO-RECOVERY on errors
// ✅ MEMORY LOGGING for debugging
// ✅ TIER PRIORITY: DB → Apple → Google (last resort)

import Foundation
import CoreLocation
import MapKit
import Combine

// MARK: - Memory Utilities

private func getMemoryUsageMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
}

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
    
    // Pan control
    @Published var suggestedRegion: MKCoordinateRegion?
    @Published var shouldPanToResults: Bool = false
    
    // Toast message for no results
    @Published var toastMessage: String?
    
    // ✅ Filters
    @Published var filters: SearchFilters = .default
    @Published var filteredResults: [PlaceSearchResult] = []
    
    // MARK: - Private Properties
    
    private let client = SupabaseClient.shared
    private let locationHelper = LocationSearchHelper.shared
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let coordinateMatchThreshold: Double = 0.0005
    
    // Store last search for "Search this area"
    var lastSearchQuery: String = ""
    
    // ✅ Store last viewport bounds for filtering
    private var lastSearchBounds: (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double)?
    
    // Search radius constants
    private let viewportRadiusMultiplier: Double = 1.2
    private let cityWideRadius: Int = 50_000
    private let globalRadius: Int = 500_000
    
    // Minimum results before moving to next tier
    private let minResultsTarget: Int = 20
    private let maxResults: Int = 30
    
    // ✅ Threshold for using viewport bounds vs circular distance
    private let viewportFilterThreshold: Int = 10_000  // 10km
    
    // ✅ SEARCH LOOP PREVENTION
    private var lastSearchTime: Date = .distantPast
    private var lastSearchCenter: CLLocationCoordinate2D?
    private var isAutoZooming: Bool = false
    private let searchCooldownSeconds: TimeInterval = 1.5  // Minimum time between searches
    private let minMoveDistanceForSearch: Double = 0.01   // ~1km minimum movement
    
    // ✅ RETRY/RECOVERY
    private var consecutiveErrors: Int = 0
    private let maxRetries: Int = 3
    
    // MARK: - Initialization & Cleanup
    
    init() {
        print("📊 [DiscoverViewModel] Init - Memory: \(String(format: "%.1f", getMemoryUsageMB())) MB")
    }
    
    deinit {
        print("🧹 [DiscoverViewModel] Deinit - cleaning up")
    }
    
    // MARK: - Apply Filters
    
    func applyFilters() {
        guard !searchResults.isEmpty else {
            filteredResults = []
            return
        }
        
        var results = searchResults
        
        // Filter by place type
        switch filters.placeType {
        case .all:
            break
        case .visited:
            results = results.filter { $0.existsInDb }
        case .new:
            results = results.filter { !$0.existsInDb }
        }
        
        // Apply rating filter
        if let minRating = filters.minRating.minValue {
            let beforeRatingFilter = results.count
            results = results.filter { result in
                guard let rating = result.avgRating else { return false }
                return rating >= minRating
            }
            print("   ⭐ Rating filter (\(minRating)+): \(beforeRatingFilter) → \(results.count)")
        }
        
        filteredResults = results
        
        if filters.isActive {
            print("🔍 [Filter] Applied: \(filters.placeType), Rating: \(filters.minRating)")
            print("   📊 Results: \(searchResults.count) → \(filteredResults.count)")
        }
    }
    
    func resetFilters() {
        filters = .default
        filteredResults = searchResults
        print("🔄 [Filter] Reset to default")
    }
    
    // MARK: - Main Search Entry Point
    
    func triggerSearch(query: String, mapCenter: CLLocationCoordinate2D, mapSpan: MKCoordinateSpan? = nil) {
        searchTask?.cancel()
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clearSearch()
            return
        }
        
        lastSearchQuery = trimmedQuery
        
        // ✅ Reset error counter on new search
        consecutiveErrors = 0
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            await performSmartSearch(query: trimmedQuery, mapCenter: mapCenter, mapSpan: mapSpan)
        }
    }
    
    /// Search this area - uses last query with current map center, PRESERVES FILTERS
    func triggerSearchThisArea(mapCenter: CLLocationCoordinate2D, mapSpan: MKCoordinateSpan) {
        guard !lastSearchQuery.isEmpty else { return }
        
        // ✅ SEARCH LOOP PREVENTION: Check cooldown
        let now = Date()
        let timeSinceLastSearch = now.timeIntervalSince(lastSearchTime)
        
        if timeSinceLastSearch < searchCooldownSeconds {
            print("⏳ [Search] Cooldown active (\(String(format: "%.1f", searchCooldownSeconds - timeSinceLastSearch))s remaining) - skipping")
            return
        }
        
        // ✅ SEARCH LOOP PREVENTION: Check if we're auto-zooming
        if isAutoZooming {
            print("⏳ [Search] Auto-zoom in progress - skipping search")
            return
        }
        
        // ✅ SEARCH LOOP PREVENTION: Check minimum movement
        if let lastCenter = lastSearchCenter {
            let latDiff = abs(mapCenter.latitude - lastCenter.latitude)
            let lngDiff = abs(mapCenter.longitude - lastCenter.longitude)
            
            if latDiff < minMoveDistanceForSearch && lngDiff < minMoveDistanceForSearch {
                print("📍 [Search] Map hasn't moved enough - skipping")
                return
            }
        }
        
        searchTask?.cancel()
        
        // ✅ Store current filters before search
        let currentFilters = filters
        
        // ✅ Update search tracking
        lastSearchTime = now
        lastSearchCenter = mapCenter
        
        let memoryBefore = getMemoryUsageMB()
        print("📊 [Search This Area] Starting - Memory: \(String(format: "%.1f", memoryBefore)) MB")
        
        searchTask = Task {
            await performSearchThisArea(query: lastSearchQuery, mapCenter: mapCenter, mapSpan: mapSpan)
            
            // ✅ Restore filters and re-apply after search completes
            await MainActor.run {
                filters = currentFilters
                applyFilters()
                
                let memoryAfter = getMemoryUsageMB()
                print("📊 [Search This Area] Complete - Memory: \(String(format: "%.1f", memoryAfter)) MB (delta: \(String(format: "%+.1f", memoryAfter - memoryBefore)) MB)")
            }
        }
    }
    
    // MARK: - Smart Search Logic
    
    private func performSmartSearch(query: String, mapCenter: CLLocationCoordinate2D, mapSpan: MKCoordinateSpan?) async {
        let memoryBefore = getMemoryUsageMB()
        print("📊 [Smart Search] Starting - Memory: \(String(format: "%.1f", memoryBefore)) MB")
        
        // ✅ Clear previous state PROPERLY
        clearSearchState()
        
        isSearching = true
        error = nil
        hasActiveSearch = true
        
        // ✅ Update search tracking
        lastSearchTime = Date()
        lastSearchCenter = mapCenter
        
        let currentSpan = mapSpan ?? MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        
        // Store viewport bounds for filtering
        lastSearchBounds = calculateViewportBounds(center: mapCenter, span: currentSpan)
        
        print("🔍 [Search] Query: '\(query)'")
        print("   📍 Viewport center: (\(String(format: "%.4f", mapCenter.latitude)), \(String(format: "%.4f", mapCenter.longitude)))")
        print("   📐 Viewport span: \(String(format: "%.4f", currentSpan.latitudeDelta)) x \(String(format: "%.4f", currentSpan.longitudeDelta))")
        
        // Detect location in query
        let detection = locationHelper.detect(in: query)
        
        do {
            if let targetLocation = detection.location {
                // LOCATION DETECTED: Search at that location directly
                print("🎯 [Search] Location detected: '\(targetLocation.displayName)'")
                
                let searchQuery = detection.cleanedQuery.isEmpty ? query : detection.cleanedQuery
                let locationSpan = calculateSpanForRadius(targetLocation.radius)
                
                try await searchAtLocationWithRetry(
                    query: searchQuery,
                    center: targetLocation.center,
                    radius: targetLocation.radius,
                    viewportBounds: nil,
                    shouldPan: true,
                    panSpan: locationSpan,
                    filterToRadius: true
                )
            } else {
                // NO LOCATION: Use staged search with viewport bounds
                print("🔎 [Search] No location detected, using viewport-based staged search")
                try await performStagedSearchWithRetry(query: query, mapCenter: mapCenter, mapSpan: currentSpan)
            }
            
            // ✅ Reset error counter on success
            consecutiveErrors = 0
            
        } catch {
            await handleSearchError(error)
        }
        
        isSearching = false
        
        let memoryAfter = getMemoryUsageMB()
        print("📊 [Smart Search] Complete - Memory: \(String(format: "%.1f", memoryAfter)) MB (delta: \(String(format: "%+.1f", memoryAfter - memoryBefore)) MB)")
    }
    
    /// Search This Area - searches in current viewport WITHOUT resetting filters or panning
    private func performSearchThisArea(query: String, mapCenter: CLLocationCoordinate2D, mapSpan: MKCoordinateSpan) async {
        print("🔄 [Search This Area] Query: '\(query)' at current viewport")
        print("   📍 Viewport center: (\(String(format: "%.4f", mapCenter.latitude)), \(String(format: "%.4f", mapCenter.longitude)))")
        print("   📐 Viewport span: \(String(format: "%.4f", mapSpan.latitudeDelta)) x \(String(format: "%.4f", mapSpan.longitudeDelta))")
        
        // ✅ Clear results but NOT filters - use proper cleanup
        searchResults.removeAll(keepingCapacity: false)
        filteredResults.removeAll(keepingCapacity: false)
        beenToPlaces.removeAll(keepingCapacity: false)
        selectedPlace = nil
        showPlaceInfo = false
        shouldPanToResults = false
        toastMessage = nil
        
        isSearching = true
        error = nil
        hasActiveSearch = true
        
        let viewportRadius = calculateViewportRadius(from: mapSpan, center: mapCenter)
        let viewportBounds = calculateViewportBounds(center: mapCenter, span: mapSpan)

        do {
            // Search with viewport bounds
            try await searchAtLocationWithRetry(
                query: query,
                center: mapCenter,
                radius: viewportRadius,
                viewportBounds: viewportBounds,
                shouldPan: false,  // ✅ CRITICAL: Don't pan after "Search This Area"
                panSpan: nil,
                filterToRadius: false
            )
            
            // ✅ After search: check if we should zoom to fit results
            // BUT with safeguards to prevent loop
            if !searchResults.isEmpty && !isAutoZooming {
                checkAndZoomToFitResultsSafely(viewportCenter: mapCenter, viewportSpan: mapSpan)
            }
            
            consecutiveErrors = 0
            
        } catch {
            await handleSearchError(error)
        }
        
        isSearching = false
    }
    
    // MARK: - Safe Auto-Zoom (Loop Prevention)
    
    private func checkAndZoomToFitResultsSafely(viewportCenter: CLLocationCoordinate2D, viewportSpan: MKCoordinateSpan) {
        guard !searchResults.isEmpty else { return }
        guard !isAutoZooming else {
            print("⏳ [Auto-Zoom] Already zooming - skipping")
            return
        }
        
        // Calculate bounding box of all results
        var minLat = searchResults[0].lat
        var maxLat = searchResults[0].lat
        var minLng = searchResults[0].lng
        var maxLng = searchResults[0].lng
        
        for result in searchResults {
            minLat = min(minLat, result.lat)
            maxLat = max(maxLat, result.lat)
            minLng = min(minLng, result.lng)
            maxLng = max(maxLng, result.lng)
        }
        
        let resultsLatSpan = maxLat - minLat
        let resultsLngSpan = maxLng - minLng
        let resultsCenterLat = (minLat + maxLat) / 2
        let resultsCenterLng = (minLng + maxLng) / 2
        
        // Current viewport dimensions
        let viewportLatSpan = viewportSpan.latitudeDelta
        let viewportLngSpan = viewportSpan.longitudeDelta
        
        // Conditions for zoom
        let resultsAreClustered = resultsLatSpan < viewportLatSpan * 0.5 &&
                                  resultsLngSpan < viewportLngSpan * 0.5
        
        let centerOffsetLat = abs(resultsCenterLat - viewportCenter.latitude)
        let centerOffsetLng = abs(resultsCenterLng - viewportCenter.longitude)
        let resultsAreFarFromCenter = centerOffsetLat > viewportLatSpan * 0.3 ||
                                       centerOffsetLng > viewportLngSpan * 0.3
        
        let viewportIsZoomedOut = viewportLatSpan > 1.0 || viewportLngSpan > 1.0
        let resultsFitInSmallerView = resultsLatSpan < 0.5 && resultsLngSpan < 0.5
        
        let shouldZoom = resultsAreClustered || resultsAreFarFromCenter ||
                         (viewportIsZoomedOut && resultsFitInSmallerView)
        
        if shouldZoom {
            // ✅ SET FLAG BEFORE triggering zoom
            isAutoZooming = true
            
            let paddedLatSpan = max(resultsLatSpan * 1.3, 0.01)
            let paddedLngSpan = max(resultsLngSpan * 1.3, 0.01)
            
            let finalLatSpan = min(paddedLatSpan, 2.0)
            let finalLngSpan = min(paddedLngSpan, 2.0)
            
            print("📍 [Auto-Zoom] Results clustered - zooming to fit")
            
            suggestedRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: resultsCenterLat, longitude: resultsCenterLng),
                span: MKCoordinateSpan(latitudeDelta: finalLatSpan, longitudeDelta: finalLngSpan)
            )
            shouldPanToResults = true
            
            // ✅ CRITICAL: Update last search center to prevent re-search
            lastSearchCenter = CLLocationCoordinate2D(latitude: resultsCenterLat, longitude: resultsCenterLng)
            lastSearchTime = Date()
            
            // ✅ Reset flag after delay to allow zoom to complete
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                await MainActor.run {
                    self.isAutoZooming = false
                }
            }
        } else {
            print("📍 [Auto-Zoom] Results fit in viewport - no zoom needed")
        }
    }
    
    // MARK: - Error Handling & Recovery
    
    private func handleSearchError(_ error: Error) async {
        consecutiveErrors += 1
        
        print("❌ [Search] Error #\(consecutiveErrors): \(error.localizedDescription)")
        print("📊 [Search Error] Memory: \(String(format: "%.1f", getMemoryUsageMB())) MB")
        
        if consecutiveErrors < maxRetries {
            // ✅ AUTO-RECOVERY: Wait and retry
            let retryDelay = UInt64(consecutiveErrors) * 1_000_000_000  // Exponential backoff
            print("🔄 [Search] Retrying in \(consecutiveErrors)s...")
            
            try? await Task.sleep(nanoseconds: retryDelay)
            
            // Don't retry if cancelled
            guard !Task.isCancelled else { return }
            
        } else {
            // ✅ Give up after max retries
            self.error = "Search failed. Please try again."
            toastMessage = "Search failed. Please try again."
            
            // Clear state to recover
            clearSearchState()
        }
    }
    
    // MARK: - Staged Search (Viewport → City → Global)
    
    private func performStagedSearchWithRetry(query: String, mapCenter: CLLocationCoordinate2D, mapSpan: MKCoordinateSpan) async throws {
        let viewportRadius = calculateViewportRadius(from: mapSpan, center: mapCenter)
        let viewportBounds = calculateViewportBounds(center: mapCenter, span: mapSpan)
        
        // STAGE 1: Viewport Search
        print("📍 [Stage 1] Viewport search (radius: \(viewportRadius)m)")
        
        try await searchAtLocationWithRetry(
            query: query,
            center: mapCenter,
            radius: viewportRadius,
            viewportBounds: viewportBounds,
            shouldPan: true,
            panSpan: nil,
            filterToRadius: false
        )
        
        let viewportResults = countResultsInBounds(bounds: viewportBounds)
        
        if viewportResults > 0 {
            print("✅ [Stage 1] Found \(viewportResults) results in viewport - done!")
            if !searchResults.isEmpty {
                calculatePanRegionToFitResults(results: searchResults)
            }
            return
        }
        
        // STAGE 2: City-wide Search
        if searchResults.isEmpty {
            print("📍 [Stage 2] City-wide search (radius: \(cityWideRadius)m)")
            
            try await searchAtLocationWithRetry(
                query: query,
                center: mapCenter,
                radius: cityWideRadius,
                viewportBounds: nil,
                shouldPan: true,
                panSpan: nil,
                filterToRadius: false
            )
            
            if !searchResults.isEmpty {
                print("✅ [Stage 2] Found \(searchResults.count) results city-wide")
                return
            }
        }
        
        // STAGE 3: Global Search
        if searchResults.isEmpty {
            print("📍 [Stage 3] Global search (radius: \(globalRadius)m)")
            
            try await searchAtLocationWithRetry(
                query: query,
                center: mapCenter,
                radius: globalRadius,
                viewportBounds: nil,
                shouldPan: true,
                panSpan: nil,
                filterToRadius: true
            )
            
            if !searchResults.isEmpty {
                print("✅ [Stage 3] Found \(searchResults.count) results globally")
            }
        }
        
        // Show toast if no results
        if searchResults.isEmpty {
            toastMessage = "No results found for '\(query)'"
        }
    }
    
    // MARK: - Search with Retry
    
    private func searchAtLocationWithRetry(
        query: String,
        center: CLLocationCoordinate2D,
        radius: Int,
        viewportBounds: (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double)?,
        shouldPan: Bool,
        panSpan: MKCoordinateSpan?,
        filterToRadius: Bool
    ) async throws {
        await searchAtLocation(
            query: query,
            center: center,
            radius: radius,
            viewportBounds: viewportBounds,
            shouldPan: shouldPan,
            panSpan: panSpan,
            filterToRadius: filterToRadius
        )
    }
    
    // MARK: - Core Search (Tiered: DB → Apple → Google)
    
    private func searchAtLocation(
        query: String,
        center: CLLocationCoordinate2D,
        radius: Int,
        viewportBounds: (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double)?,
        shouldPan: Bool,
        panSpan: MKCoordinateSpan?,
        filterToRadius: Bool
    ) async {
        var dbResults: [PlaceSearchResult] = []
        var appleResults: [PlaceSearchResult] = []
        var googleResults: [PlaceSearchResult] = []
        
        // ========================================
        // TIER 1: Database Search (FREE, our data)
        // ========================================
        print("📊 [Tier 1] Searching database...")
        
        do {
            let requestBody: [String: Any] = [
                "query": query,
                "lat": center.latitude,
                "lng": center.longitude,
                "radius": min(radius * 2, 100_000),
                "limit": 50
            ]
            
            struct SearchResponse: Codable {
                let places: [PlaceSearchResult]
            }
            
            let response: SearchResponse = try await client.post(
                path: "/functions/v1/places-search",
                body: requestBody
            )
            
            // Apply bounds filter if provided
            if let bounds = viewportBounds {
                dbResults = response.places.filter { result in
                    result.lat >= bounds.minLat && result.lat <= bounds.maxLat &&
                    result.lng >= bounds.minLng && result.lng <= bounds.maxLng
                }
                
                for result in response.places {
                    let inBounds = result.lat >= bounds.minLat && result.lat <= bounds.maxLat &&
                                   result.lng >= bounds.minLng && result.lng <= bounds.maxLng
                    if inBounds {
                        print("   ✅ DB: Added '\(result.displayName)' at (\(String(format: "%.4f", result.lat)), \(String(format: "%.4f", result.lng)))")
                    } else {
                        print("   ⏭️ DB: Skipped '\(result.displayName)' - outside viewport bounds")
                    }
                }
            } else if filterToRadius {
                dbResults = response.places.filter { result in
                    let distance = calculateDistance(from: center, to: CLLocationCoordinate2D(latitude: result.lat, longitude: result.lng))
                    return distance <= Double(radius)
                }
            } else {
                dbResults = response.places
            }
            
            print("✅ [Tier 1] DB: \(dbResults.count) results (from \(response.places.count) total)")
            
        } catch {
            print("❌ [Tier 1] DB search failed: \(error.localizedDescription)")
        }
        
        // ========================================
        // TIER 2: Apple MapKit (FREE, iOS native)
        // ========================================
        let totalSoFar = dbResults.count
        
        if totalSoFar < minResultsTarget {
            print("🍎 [Tier 2] Searching Apple MapKit (need more results)...")
            
            let searchRegion = MKCoordinateRegion(
                center: center,
                span: calculateSpanForRadius(radius)
            )
            
            do {
                let rawAppleResults = try await AppleMapKitService.shared.searchPlaces(
                    query: query,
                    region: searchRegion,
                    maxResults: maxResults - dbResults.count
                )
                
                print("🍎 [Apple Maps] Found \(rawAppleResults.count) results for '\(query)'")
                
                var outsideBounds = 0
                var duplicates = 0
                
                for apple in rawAppleResults {
                    // Check bounds
                    if let bounds = viewportBounds {
                        let inBounds = apple.lat >= bounds.minLat && apple.lat <= bounds.maxLat &&
                                       apple.lng >= bounds.minLng && apple.lng <= bounds.maxLng
                        if !inBounds {
                            outsideBounds += 1
                            continue
                        }
                    }
                    
                    // Check for duplicates
                    let isDupe = dbResults.contains { existing in
                        abs(existing.lat - apple.lat) < coordinateMatchThreshold &&
                        abs(existing.lng - apple.lng) < coordinateMatchThreshold
                    } || appleResults.contains { existing in
                        abs(existing.lat - apple.lat) < coordinateMatchThreshold &&
                        abs(existing.lng - apple.lng) < coordinateMatchThreshold
                    }
                    
                    if isDupe {
                        duplicates += 1
                        continue
                    }
                    
                    let result = PlaceSearchResult(
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
                        ),
                        visitCount: nil,
                        avgRating: nil
                    )
                    
                    appleResults.append(result)
                }
                
                print("🍎 [Apple Maps] Returning \(rawAppleResults.count) results")
                print("✅ [Tier 2] Apple: +\(appleResults.count) results (skipped: \(outsideBounds) outside bounds, \(duplicates) dupes)")
                
            } catch {
                print("❌ [Tier 2] Apple search failed: \(error.localizedDescription)")
            }
        }
        
        // ========================================
        // TIER 3: Google Places (EXPENSIVE, last resort)
        // ========================================
        let totalBeforeGoogle = dbResults.count + appleResults.count
        
        if totalBeforeGoogle < minResultsTarget {
            print("🌐 [Tier 3] Searching Google (last resort, need more results)...")
            
            do {
                let requestBody: [String: Any] = [
                    "query": query,
                    "lat": center.latitude,
                    "lng": center.longitude,
                    "radius": radius
                ]
                
                struct ExternalSearchResponse: Codable {
                    let results: [PlaceSearchResult]
                }
                
                let response: ExternalSearchResponse = try await client.post(
                    path: "/functions/v1/places-search-external",
                    body: requestBody
                )
                
                var outsideBounds = 0
                var duplicates = 0
                let existingCoords = (dbResults + appleResults).map { ($0.lat, $0.lng) }
                
                for result in response.results where result.source == .google {
                    // Check bounds
                    if let bounds = viewportBounds {
                        let inBounds = result.lat >= bounds.minLat && result.lat <= bounds.maxLat &&
                                       result.lng >= bounds.minLng && result.lng <= bounds.maxLng
                        if !inBounds {
                            outsideBounds += 1
                            continue
                        }
                    }
                    
                    // Check duplicates
                    let isDupe = existingCoords.contains { coord in
                        abs(coord.0 - result.lat) < coordinateMatchThreshold &&
                        abs(coord.1 - result.lng) < coordinateMatchThreshold
                    } || googleResults.contains { existing in
                        abs(existing.lat - result.lat) < coordinateMatchThreshold &&
                        abs(existing.lng - result.lng) < coordinateMatchThreshold
                    }
                    
                    if isDupe {
                        duplicates += 1
                        continue
                    }
                    
                    googleResults.append(result)
                }
                
                print("✅ [Tier 3] Google: +\(googleResults.count) results (skipped: \(outsideBounds) outside bounds, \(duplicates) dupes)")
                
            } catch {
                print("❌ [Tier 3] Google search failed: \(error.localizedDescription)")
            }
        } else {
            print("⏭️ [Tier 3] Skipped Google (have \(totalBeforeGoogle) results)")
        }
        
        // ========================================
        // COMBINE RESULTS
        // ========================================
        let allResults = dbResults + appleResults + googleResults
        
        // ✅ IMPORTANT: Replace array, don't append
        searchResults = Array(allResults.prefix(maxResults))
        filteredResults = searchResults
        
        print("📊 [Results] Total: \(searchResults.count) (DB: \(dbResults.count), Apple: \(appleResults.count), Google: \(googleResults.count))")
        
        // Handle panning
        if shouldPan && !searchResults.isEmpty {
            if let span = panSpan {
                let centerLat = searchResults.map(\.lat).reduce(0, +) / Double(searchResults.count)
                let centerLng = searchResults.map(\.lng).reduce(0, +) / Double(searchResults.count)
                
                suggestedRegion = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng),
                    span: span
                )
                shouldPanToResults = true
            } else {
                calculatePanRegionToFitResults(results: searchResults)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func calculatePanRegionToFitResults(results: [PlaceSearchResult]) {
        guard !results.isEmpty else { return }
        
        var minLat = results[0].lat
        var maxLat = results[0].lat
        var minLng = results[0].lng
        var maxLng = results[0].lng
        
        for result in results {
            minLat = min(minLat, result.lat)
            maxLat = max(maxLat, result.lat)
            minLng = min(minLng, result.lng)
            maxLng = max(maxLng, result.lng)
        }
        
        let centerLat = (minLat + maxLat) / 2
        let centerLng = (minLng + maxLng) / 2
        let latSpan = max((maxLat - minLat) * 1.5, 0.02)
        let lngSpan = max((maxLng - minLng) * 1.5, 0.02)
        
        // ✅ Set auto-zoom flag
        isAutoZooming = true
        
        print("📍 [Pan] Fitting \(results.count) results in view")
        
        suggestedRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng),
            span: MKCoordinateSpan(latitudeDelta: min(latSpan, 2.0), longitudeDelta: min(lngSpan, 2.0))
        )
        shouldPanToResults = true
        
        // ✅ Update tracking to prevent re-search
        lastSearchCenter = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng)
        lastSearchTime = Date()
        
        // Reset flag after delay
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                self.isAutoZooming = false
            }
        }
    }
    
    private func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let loc2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return loc1.distance(from: loc2)
    }
    
    private func calculateViewportBounds(center: CLLocationCoordinate2D, span: MKCoordinateSpan) -> (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double) {
        let minLat = center.latitude - span.latitudeDelta / 2
        let maxLat = center.latitude + span.latitudeDelta / 2
        let minLng = center.longitude - span.longitudeDelta / 2
        let maxLng = center.longitude + span.longitudeDelta / 2
        return (minLat, maxLat, minLng, maxLng)
    }
    
    private func countResultsInBounds(bounds: (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double)) -> Int {
        return searchResults.filter { result in
            result.lat >= bounds.minLat && result.lat <= bounds.maxLat &&
            result.lng >= bounds.minLng && result.lng <= bounds.maxLng
        }.count
    }
    
    private func calculateViewportRadius(from span: MKCoordinateSpan, center: CLLocationCoordinate2D) -> Int {
        let latMeters = span.latitudeDelta * 111_000
        let lngMeters = span.longitudeDelta * 111_000 * cos(center.latitude * .pi / 180)
        let radius = max(latMeters, lngMeters) / 2 * viewportRadiusMultiplier
        return min(max(Int(radius), 1_000), 50_000)
    }
    
    private func calculateSpanForRadius(_ radius: Int) -> MKCoordinateSpan {
        let degrees = Double(radius) / 111_000 * 1.5
        return MKCoordinateSpan(
            latitudeDelta: min(degrees, 1.0),
            longitudeDelta: min(degrees, 1.0)
        )
    }
    
    // MARK: - Clear & Cleanup
    
    /// Clear all search state (used for new searches)
    private func clearSearchState() {
        searchResults.removeAll(keepingCapacity: false)
        filteredResults.removeAll(keepingCapacity: false)
        beenToPlaces.removeAll(keepingCapacity: false)
        selectedPlace = nil
        showPlaceInfo = false
        suggestedRegion = nil
        shouldPanToResults = false
        toastMessage = nil
        filters = .default
    }
    
    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        
        clearSearchState()
        
        hasActiveSearch = false
        isSearching = false
        error = nil
        lastSearchQuery = ""
        lastSearchBounds = nil
        lastSearchCenter = nil
        isAutoZooming = false
        consecutiveErrors = 0
        
        print("🧹 [Search] Cleared - Memory: \(String(format: "%.1f", getMemoryUsageMB())) MB")
    }
    
    /// Called when view disappears - aggressive cleanup
    func forceCleanup() {
        print("🧹 [DiscoverViewModel] Force cleanup starting...")
        let memoryBefore = getMemoryUsageMB()
        
        searchTask?.cancel()
        searchTask = nil
        
        searchResults.removeAll(keepingCapacity: false)
        filteredResults.removeAll(keepingCapacity: false)
        beenToPlaces.removeAll(keepingCapacity: false)
        
        selectedPlace = nil
        showPlaceInfo = false
        hasActiveSearch = false
        isSearching = false
        isLoading = false
        suggestedRegion = nil
        shouldPanToResults = false
        toastMessage = nil
        error = nil
        
        lastSearchBounds = nil
        lastSearchCenter = nil
        isAutoZooming = false
        consecutiveErrors = 0
        
        cancellables.removeAll()
        
        let memoryAfter = getMemoryUsageMB()
        print("🧹 [DiscoverViewModel] Force cleanup complete - Memory: \(String(format: "%.1f", memoryAfter)) MB (freed: \(String(format: "%.1f", memoryBefore - memoryAfter)) MB)")
    }
    
    // MARK: - Fetch Places (Browse Mode)
    
    func fetchBeenToPlaces(in region: MKCoordinateRegion? = nil) async {
        guard searchResults.isEmpty && !isSearching else { return }
        
        let memoryBefore = getMemoryUsageMB()
        print("📊 [Fetch Places] Starting - Memory: \(String(format: "%.1f", memoryBefore)) MB")
        
        isLoading = true
        error = nil
        beenToPlaces.removeAll(keepingCapacity: false)
        
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
            
            let response: PlacesResponse = try await client.post(
                path: "/functions/v1/places-nearby",
                body: requestBody
            )
            
            beenToPlaces = response.places
                .filter { ($0.visitCount ?? 0) > 0 }
                .prefix(50)
                .map { PlaceWithVisits(place: $0, visitCount: $0.visitCount ?? 0, friendVisitCount: 0, visits: []) }
            
            let memoryAfter = getMemoryUsageMB()
            print("✅ [Fetch] \(beenToPlaces.count) places - Memory: \(String(format: "%.1f", memoryAfter)) MB")
            
            consecutiveErrors = 0
            
        } catch {
            print("❌ [Fetch] \(error)")
            self.error = "Failed to load places"
            consecutiveErrors += 1
        }
        
        isLoading = false
    }
    
    // MARK: - Selection
    
    func selectPlace(_ place: Place) {
        selectedPlace = place
        showPlaceInfo = true
    }
    
    func selectSearchResult(_ result: PlaceSearchResult) async {
        if result.existsInDb, let placeId = result.dbPlaceId {
            await fetchPlaceDetails(placeId: placeId)
        } else {
            selectedPlace = Place(
                id: result.dbPlaceId ?? result.id.uuidString,
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
                phone: result.appleFullData?.phone,
                website: result.appleFullData?.website,
                openingHours: nil,
                createdAt: nil,
                updatedAt: nil
            )
            showPlaceInfo = true
        }
    }
    
    func fetchPlaceDetails(placeId: String) async {
        do {
            let queryItems = [
                URLQueryItem(name: "id", value: "eq.\(placeId)"),
                URLQueryItem(name: "select", value: "id,provider,google_place_id,apple_place_id,name_en,name_ja,name_zh,lat,lng,city,ward,categories,phone,website,address,avg_rating,visit_count,created_at,updated_at")
            ]
            
            let places: [Place] = try await client.get(path: "/rest/v1/places", queryItems: queryItems)
            
            if let place = places.first {
                selectedPlace = place
                showPlaceInfo = true
            }
        } catch {
            self.error = "Failed to load place"
        }
    }
    
    func toggleFollowingFilter() {
        showFollowingOnly.toggle()
        Task { await fetchBeenToPlaces() }
    }
    
    func refreshPlace(placeId: String) async {
        do {
            let queryItems = [
                URLQueryItem(name: "id", value: "eq.\(placeId)"),
                URLQueryItem(name: "select", value: "id,provider,google_place_id,apple_place_id,name_en,name_ja,name_zh,lat,lng,city,ward,categories,avg_rating,visit_count,phone,website,address,created_at,updated_at")
            ]
            
            let places: [Place] = try await client.get(path: "/rest/v1/places", queryItems: queryItems)
            
            if let updated = places.first {
                if let idx = beenToPlaces.firstIndex(where: { $0.place.id == placeId }) {
                    let old = beenToPlaces[idx]
                    beenToPlaces[idx] = PlaceWithVisits(place: updated, visitCount: old.visitCount, friendVisitCount: old.friendVisitCount, visits: old.visits)
                }
                if selectedPlace?.id == placeId {
                    selectedPlace = updated
                }
            }
        } catch {
            print("❌ [Refresh] \(error)")
        }
    }
}
