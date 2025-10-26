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

struct SearchPlaceOverlay: View {
    @Binding var isPresented: Bool
    let onPlaceSelected: (PlaceSearchResult) -> Void
    
    @StateObject private var viewModel = SearchPlaceViewModel()
    @StateObject private var locationManager = LocationManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool
    @State private var selectedResult: PlaceSearchResult?
    @State private var showPlaceInfo = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea(.all)
                .onTapGesture {
                    if !showPlaceInfo {
                        isPresented = false
                    }
                }
            
            VStack(spacing: 0) {
                searchBar
                
                if viewModel.isLoading && viewModel.displayedResults.isEmpty {
                    loadingView
                } else if !viewModel.displayedResults.isEmpty {
                    suggestionsList
                } else if !viewModel.searchQuery.isEmpty && !viewModel.isLoading {
                    emptyStateView
                }
                
                Spacer()
            }
            .background(colorScheme == .dark ? Color.black : .white)
            .cornerRadius(20)
            .padding(.horizontal, 20)
            .padding(.vertical, 100)
            .shadow(color: .black.opacity(0.2), radius: 20)
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                
                TextField("Search for a place", text: $viewModel.searchQuery)
                    .font(.system(size: 16))
                    .focused($isFocused)
                    .onChange(of: viewModel.searchQuery) { _, newValue in
                        Task {
                            await viewModel.performSearch(
                                lat: locationManager.userLocation?.latitude ?? 35.6762,
                                lng: locationManager.userLocation?.longitude ?? 139.6503
                            )
                        }
                    }
                
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        viewModel.clearResults()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
            .cornerRadius(12)
        }
        .padding(16)
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
                
                for appleResult in appleResults {
                    // ✅ Check if this Apple place already exists in DB
                    if dbPlaceIds.contains(appleResult.applePlaceId) {
                        print("⏭️  [DEDUP] Skipping Apple result (exists in DB): \(appleResult.name)")
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

// Add this to SearchPlaceOverlay.swift - Replace SearchPlaceConfirmSheet

struct SearchPlaceConfirmSheet: View {
    let result: PlaceSearchResult
    let onConfirm: (PlaceSearchResult) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var locationManager = LocationManager.shared
    @State private var visits: [Visit] = []
    @State private var isLoadingVisits = false
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Drag indicator
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        photoSection
                        
                        VStack(alignment: .leading, spacing: 0) {
                            // Name
                            Text(result.displayName)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                                .padding(.bottom, 8)
                            
                            // Rating
                            ratingSection
                                .padding(.bottom, 4)
                            
                            // Categories
                            if let categories = result.categories, !categories.isEmpty {
                                Text(categories.prefix(3).joined(separator: " · "))
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .padding(.bottom, 16)
                            }
                            
                            // Visit status - ✅ NOW SHOWS REAL VISITS
                            VisitStatusView(visitCount: visits.count, isLoading: isLoadingVisits)
                                .padding(.bottom, 16)
                            
                            Divider()
                                .padding(.vertical, 16)
                            
                            // Address
                            if let address = result.formattedAddress, !address.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 10) {
                                        Circle()
                                            .strokeBorder(Color(red: 1.0, green: 0.4, blue: 0.4), lineWidth: 2)
                                            .frame(width: 32, height: 32)
                                            .overlay {
                                                Image(systemName: "mappin")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                                            }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Address")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.secondary)
                                            Text(address)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.primary)
                                        }
                                        
                                        Spacer()
                                    }
                                    
                                    // Distance
                                    if let distance = calculateDistance() {
                                        Text(distance)
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 42)
                                    }
                                }
                            }
                            
                            // Phone
                            if let phone = result.appleFullData?.phone, !phone.isEmpty {
                                Divider().padding(.vertical, 12)
                                PhoneButton(phone: phone)
                            }
                            
                            // Website
                            if let website = result.appleFullData?.website, !website.isEmpty {
                                Divider().padding(.vertical, 12)
                                WebsiteButton(website: website)
                            }
                            
                            // Directions
                            Divider().padding(.vertical, 12)
                            DirectionsButton(
                                placeName: result.displayName,
                                address: result.formattedAddress ?? ""
                            )
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer().frame(height: 100)
                    }
                }
                
                VStack(spacing: 0) {
                    Button {
                        onConfirm(result)
                    } label: {
                        Text("Confirm Location")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, max(12, geometry.safeAreaInsets.bottom + 12))
                    .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
                }
            }
        }
        .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
        .task {
            // ✅ Load visits if place exists in DB
            if result.existsInDb, let placeId = result.dbPlaceId {
                await loadVisits(placeId: placeId)
            }
        }
    }
    
    // MARK: - Components
    
    @ViewBuilder
    private var ratingSection: some View {
        HStack(spacing: 4) {
            Text(ratingText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            
            HStack(spacing: 2) {
                ForEach(0..<5) { index in
                    Image(systemName: "star")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    private var ratingText: String {
        return "0"
    }
    
    @ViewBuilder
    private var photoSection: some View {
        let photoSize: CGFloat = 200
        
        if !visits.isEmpty {
            let allPhotos = visits.flatMap { $0.photoUrls }
            if !allPhotos.isEmpty {
                PhotoGridView(photos: Array(allPhotos.prefix(10)), photoSize: photoSize)
                    .padding(.top, 30)
                    .padding(.bottom, 20)
            } else if let photoUrls = result.photoUrls, !photoUrls.isEmpty {
                PhotoGridView(photos: Array(photoUrls.prefix(10)), photoSize: photoSize)
                    .padding(.top, 30)
                    .padding(.bottom, 20)
            } else {
                EmptyPhotoView(height: photoSize)
            }
        } else if let photoUrls = result.photoUrls, !photoUrls.isEmpty {
            PhotoGridView(photos: Array(photoUrls.prefix(10)), photoSize: photoSize)
                .padding(.top, 30)
                .padding(.bottom, 20)
        } else {
            EmptyPhotoView(height: photoSize)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadVisits(placeId: String) async {
        isLoadingVisits = true
        
        do {
            let response: [Visit] = try await SupabaseClient.shared.get(
                path: "/rest/v1/visits",
                queryItems: [
                    URLQueryItem(name: "place_id", value: "eq.\(placeId)"),
                    URLQueryItem(name: "select", value: "id,user_id,rating,comment,photo_urls,visited_at,created_at,updated_at,user:users!inner(id,handle,display_name,avatar_url)"),
                    URLQueryItem(name: "order", value: "created_at.desc"),
                    URLQueryItem(name: "limit", value: "10")
                ],
                requiresAuth: false
            )
            
            await MainActor.run {
                visits = response
                isLoadingVisits = false
            }
            
            print("✅ [SearchConfirm] Loaded \(response.count) visits")
            
        } catch {
            print("❌ [SearchConfirm] Failed to load visits: \(error)")
            await MainActor.run {
                visits = []
                isLoadingVisits = false
            }
        }
    }
    
    // MARK: - Helpers
    
    private func calculateDistance() -> String? {
        guard let userLocation = locationManager.userLocation else { return nil }
        
        let placeLocation = CLLocation(latitude: result.lat, longitude: result.lng)
        let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let distance = userCLLocation.distance(from: placeLocation)
        
        if distance < 1000 {
            return String(format: "%.0f m away", distance)
        } else {
            return String(format: "%.1f km away", distance / 1000)
        }
    }
}
