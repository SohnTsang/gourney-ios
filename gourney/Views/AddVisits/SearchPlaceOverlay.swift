//
//  SearchPlaceOverlay.swift
//  gourney
//
//  ✅ CLEAN VERSION - No duplicates
//  ✅ DB (50) + Apple (50) sorted by distance
//  ✅ Pagination 20/page
//  ✅ Original rating design (0 ★★★★★)
//  ✅ Reduced overlay height
//

import SwiftUI
import MapKit
import Combine

// ✅ Response model for check-place-ids edge function
struct CheckPlaceIdsResponse: Codable {
    let existingAppleIds: [String]?
    let existingGoogleIds: [String]?
}

struct SearchPlaceOverlay: View {
    @Binding var isPresented: Bool
    let onPlaceSelected: (PlaceSearchResult) -> Void
    
    @StateObject private var viewModel = SearchPlaceViewModel()
    @StateObject private var locationManager = LocationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool
    @State private var selectedResult: PlaceSearchResult?
    @State private var showPlaceInfo = false
    @State private var showFilterSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar (Top)
            searchBar
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
                .shadow(color: .black.opacity(0.05), radius: 2, y: 2)
            
            // Results
            if viewModel.isLoading && viewModel.displayedResults.isEmpty {
                loadingView
            } else if !viewModel.displayedResults.isEmpty {
                suggestionsList
            } else if !viewModel.searchQuery.isEmpty && !viewModel.isLoading {
                emptyStateView
            } else {
                // Placeholder when search is empty
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Search for places")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            // Bottom safe area padding for tab bar
            Spacer()
                .frame(height: 90)
        }
        .background(colorScheme == .dark ? Color(.systemBackground) : Color(.systemGroupedBackground))
        .ignoresSafeArea(.all, edges: [.bottom])
        .sheet(isPresented: $showPlaceInfo) {
            if let result = selectedResult {
                SearchPlaceConfirmSheet(
                    result: result,
                    onConfirm: { confirmedResult in
                        onPlaceSelected(confirmedResult)
                        isPresented = false
                    }
                )
                .presentationDetents([.large])
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            VStack(spacing: 20) {
                Text("Filters")
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top, 20)
                
                Text("Filter options coming soon")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            isFocused = true
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Button {
                isPresented = false
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField("Search for a place", text: $viewModel.searchQuery)
                    .font(.system(size: 17))
                    .focused($isFocused)
                    .autocorrectionDisabled()
                    .onSubmit {
                        performSearch()
                    }
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        viewModel.clearResults()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        performSearch()
                    } label: {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
            .cornerRadius(20)
        }
    }
    
    private func performSearch() {
        guard !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        isFocused = false // Dismiss keyboard
        
        Task {
            await viewModel.performSearch(
                lat: locationManager.userLocation?.latitude ?? 35.6762,
                lng: locationManager.userLocation?.longitude ?? 139.6503
            )
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Searching...")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
        .frame(maxHeight: .infinity)
    }
    
    private var suggestionsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.displayedResults.enumerated()), id: \.element.id) { index, result in
                    SearchResultRow(result: result)
                        .onTapGesture {
                            selectedResult = result
                            showPlaceInfo = true
                        }
                        .onAppear {
                            if index == viewModel.displayedResults.count - 1 {
                                viewModel.loadMoreIfNeeded()
                            }
                        }
                    
                    if result.id != viewModel.displayedResults.last?.id {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
                
                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 16)
                        Spacer()
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No places found")
                .font(.system(size: 17, weight: .semibold))
            Text("Try a different search")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
        .frame(maxHeight: .infinity)
    }
}

struct SearchResultRow: View {
    let result: PlaceSearchResult
    @StateObject private var locationManager = LocationManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.existsInDb ? "mappin.circle.fill" : "mappin.circle")
                .font(.system(size: 24))
                .foregroundColor(result.existsInDb ? .blue : Color(red: 1.0, green: 0.45, blue: 0.45))
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(result.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                if let address = result.formattedAddress {
                    Text(address)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if let distance = locationManager.formattedDistance(from: result.coordinate) {
                Text(distance)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.clear)
    }
}

@MainActor
class SearchPlaceViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var displayedResults: [PlaceSearchResult] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    
    private var allResults: [PlaceSearchResult] = []
    private var currentPage = 0
    private let pageSize = 20
    
    private var searchTask: Task<Void, Never>?
    private let client = SupabaseClient.shared
    private let appleService = AppleMapKitService.shared
    
    func clearResults() {
        allResults = []
        displayedResults = []
        currentPage = 0
    }
    
    func loadMoreIfNeeded() {
        guard !isLoadingMore else { return }
        
        let startIndex = displayedResults.count
        let endIndex = min(startIndex + pageSize, allResults.count)
        
        guard startIndex < allResults.count else { return }
        
        isLoadingMore = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.displayedResults.append(contentsOf: self.allResults[startIndex..<endIndex])
            self.currentPage += 1
            self.isLoadingMore = false
            
            print("📄 [PAGINATION] Page \(self.currentPage): \(self.displayedResults.count)/\(self.allResults.count)")
        }
    }
    
    func performSearch(lat: Double, lng: Double) async {
        searchTask?.cancel()
        
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearResults()
            return
        }
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            guard !Task.isCancelled else { return }
            
            isLoading = true
            
            print("🔍 [SEARCH] Starting: '\(searchQuery)'")
            
            let startTime = Date()
            var combinedResults: [PlaceSearchResult] = []
            var dbPlaceIds = Set<String>()
            
            // STEP 1: Database (up to 50)
            do {
                let requestBody: [String: Any] = [
                    "query": searchQuery,
                    "lat": lat,
                    "lng": lng,
                    "radius": 10000,
                    "limit": 50
                ]
                
                let response: SearchPlacesResponse = try await client.post(
                    path: "/functions/v1/places-search-external",
                    body: requestBody
                )
                
                print("💾 [DB] \(response.results.count) results")
                
                for result in response.results where result.existsInDb {
                    // Add DB place ID
                    if let dbId = result.dbPlaceId {
                        dbPlaceIds.insert(dbId)
                    }
                    // Add Apple place ID (to skip Apple API results for same place)
                    if let appleId = result.applePlaceId {
                        dbPlaceIds.insert(appleId)
                    }
                    // ✅ CRITICAL FIX: Also add Google place ID if present
                    if let googleId = result.googlePlaceId {
                        dbPlaceIds.insert(googleId)
                    }
                }
                
                combinedResults.append(contentsOf: response.results)
                
            } catch {
                print("❌ [DB] Error: \(error)")
            }
            
            guard !Task.isCancelled else { return }
            
            // STEP 2: Apple Maps (up to 50)
            do {
                let region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                    latitudinalMeters: 10000,
                    longitudinalMeters: 10000
                )
                
                let appleResults = try await appleService.searchPlaces(
                    query: searchQuery,
                    region: region,
                    maxResults: 50
                )
                
                print("🍎 [APPLE] \(appleResults.count) results")
                
                // ✅ NEW: Batch check all Apple IDs against DB
                let appleIds = appleResults.map { $0.applePlaceId }
                let dbCheckBody: [String: Any] = [
                    "apple_place_ids": appleIds
                ]
                
                var existingAppleIds = Set<String>()
                var dbPlacesMap: [String: PlaceSearchResult] = [:]
                
                do {
                    let checkResponse: CheckPlaceIdsResponse = try await client.post(
                        path: "/functions/v1/check-place-ids",
                        body: dbCheckBody
                    )
                    print("🔍 [DEDUP] checkResponse: \(checkResponse)")
                    print("🔍 [DEDUP] existingAppleIds: \(String(describing: checkResponse.existingAppleIds))")
                    
                    if let ids = checkResponse.existingAppleIds {
                        existingAppleIds = Set(ids)
                        print("🔍 [DEDUP] Found \(ids.count) existing Apple IDs in DB")
                        print("🔍 [DEDUP] IDs array: \(ids)")
                        print("🔍 [DEDUP] isEmpty check: \(!ids.isEmpty)")

                        // ✅ Fetch full place data for these IDs
                        if !ids.isEmpty {
                            print("🔄 [DEDUP] Fetching \(ids.count) places from DB...")
                            let fetchBody: [String: Any] = [
                                "apple_place_ids": ids
                            ]
                            
                            do {
                                let fetchResponse: SearchPlacesResponse = try await client.post(
                                    path: "/functions/v1/fetch-places-by-ids",
                                    body: fetchBody
                                )
                                
                                print("📦 [DEDUP] Fetch response: \(fetchResponse.results.count) places")
                                
                                for place in fetchResponse.results {
                                    if let appleId = place.applePlaceId {
                                        dbPlacesMap[appleId] = place
                                        print("   - \(place.displayName) (ID: \(appleId))")
                                    }
                                }
                                print("✅ [DEDUP] Fetched \(dbPlacesMap.count) DB places")
                            } catch {
                                print("❌ [DEDUP] Failed to fetch DB places: \(error)")
                            }
                        } else {
                            print("⏭️ [DEDUP] No existing Apple IDs to fetch")
                        }
                    }
                } catch {
                    print("⚠️ [DEDUP] Failed to check Apple IDs: \(error)")
                }
                
                for appleResult in appleResults {
                    // ✅ If exists in DB, add DB version instead
                    if let dbPlace = dbPlacesMap[appleResult.applePlaceId] {
                        if !combinedResults.contains(where: { $0.dbPlaceId == dbPlace.dbPlaceId }) {
                            combinedResults.append(dbPlace)
                            print("✅ [DEDUP] Added DB version: \(dbPlace.displayName)")
                        }
                        continue
                    }
                    
                    // Check by Apple ID from previous DB results
                    if dbPlaceIds.contains(appleResult.applePlaceId) {
                        print("⏭️ [DEDUP] Skipping Apple result (exists in DB): \(appleResult.name)")
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
                    
                    if isDuplicate {
                        print("⏭️ [DEDUP] Skipping Apple result (same location + name): \(appleResult.name)")
                        continue
                    }
                    
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
                print("❌ [APPLE] Error: \(error)")
            }
            
            guard !Task.isCancelled else { return }
            
            // STEP 3: Sort by distance
            let userLoc = CLLocation(latitude: lat, longitude: lng)
            let sortedResults = combinedResults.sorted { r1, r2 in
                let loc1 = CLLocation(latitude: r1.lat, longitude: r1.lng)
                let loc2 = CLLocation(latitude: r2.lat, longitude: r2.lng)
                return userLoc.distance(from: loc1) < userLoc.distance(from: loc2)
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            print("✅ [SEARCH] \(sortedResults.count) total in \(String(format: "%.2f", elapsed))s")
            
            allResults = sortedResults
            currentPage = 0
            displayedResults = Array(allResults.prefix(pageSize))
            
            print("📄 [PAGINATION] Page 1: \(displayedResults.count)/\(allResults.count)")
            
            isLoading = false
        }
    }
}

// MARK: - ✅ FIXED: Now uses EXACT same components as PlaceInfoCard

struct SearchPlaceConfirmSheet: View {
    let result: PlaceSearchResult
    let onConfirm: (PlaceSearchResult) -> Void
    
    var body: some View {
        PlaceDetailSheet(
            placeId: result.dbPlaceId ?? "",
            displayName: result.displayName,
            lat: result.lat,
            lng: result.lng,
            formattedAddress: result.formattedAddress,
            phoneNumber: result.appleFullData?.phone,
            website: result.appleFullData?.website,
            photoUrls: result.photoUrls,
            googlePlaceId: result.googlePlaceId,  // ✅ Pass Google Place ID
            primaryButtonTitle: "Confirm Location",
            primaryButtonAction: {
                onConfirm(result)
            },
            onDismiss: nil
        )
    }
}
