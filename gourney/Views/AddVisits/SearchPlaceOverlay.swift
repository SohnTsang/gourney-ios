//
//  SearchPlaceOverlay.swift
//  gourney
//
//  Production-grade design matching PlaceInfoCard
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
            // Full screen overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea(.all)
                .onTapGesture {
                    if !showPlaceInfo {
                        isPresented = false
                    }
                }
            
            VStack(spacing: 0) {
                searchBar
                
                if viewModel.isLoading {
                    loadingView
                } else if !viewModel.searchResults.isEmpty {
                    // ✅ Suggestions list fills to overlay bottom
                    suggestionsList
                } else if !viewModel.searchQuery.isEmpty && !viewModel.isLoading {
                    emptyStateView
                }
                
                Spacer()
            }
            .background(colorScheme == .dark ? Color.black : .white)
            .cornerRadius(20)
            .padding(.horizontal, 16)
            .padding(.top, 60)
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
                    .presentationDragIndicator(.visible)
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
                        viewModel.searchResults = []
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
                ForEach(viewModel.searchResults) { result in
                    SearchResultRow(result: result)
                        .onTapGesture {
                            selectedResult = result
                            showPlaceInfo = true
                        }
                    
                    if result.id != viewModel.searchResults.last?.id {
                        Divider()
                            .padding(.leading, 56)
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
                
                if let categories = result.categories, !categories.isEmpty {
                    Text(categories.prefix(2).joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
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
    @Published var searchQuery = ""
    @Published var searchResults: [PlaceSearchResult] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let client = SupabaseClient.shared
    private var searchTask: Task<Void, Never>?
    
    func performSearch(lat: Double, lng: Double) async {
        searchTask?.cancel()
        
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run { isLoading = true }
            
            print("🔍 [SEARCH] Starting search for: '\(searchQuery)'")
            print("📍 [SEARCH] Location: lat=\(lat), lng=\(lng)")
            print("⚙️ [SEARCH] Limit: 50 (expecting ~45 DB + 5 external)")
            
            do {
                let startTime = Date()
                
                // ✅ Backend returns DB results first (sorted by distance), then Google/Apple (limit 5 external)
                let response: SearchPlacesResponse = try await client.post(
                    path: "/functions/v1/places-search-external",
                    body: [
                        "query": searchQuery,
                        "lat": lat,
                        "lng": lng,
                        "limit": 50  // ✅ 45 DB results + 5 external = 50 total
                    ]
                )
                
                let duration = Date().timeIntervalSince(startTime)
                
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    searchResults = response.results
                    isLoading = false
                    
                    print("✅ [SEARCH] Success! Retrieved \(response.results.count) results in \(String(format: "%.2f", duration))s")
                    print("📊 [SEARCH] Result breakdown:")
                    
                    let dbResults = response.results.filter { $0.existsInDb }
                    let externalResults = response.results.filter { !$0.existsInDb }
                    
                    print("   - DB results: \(dbResults.count)")
                    print("   - External API results: \(externalResults.count)")
                    
                    if externalResults.count > 5 {
                        print("⚠️ [SEARCH] WARNING: Got \(externalResults.count) external results (expected max 5)")
                        print("⚠️ [SEARCH] This may indicate excessive API usage!")
                    }
                    
                    print("📍 [SEARCH] First 5 results (with distance):")
                    for (index, result) in response.results.prefix(5).enumerated() {
                        let source = result.existsInDb ? "DB" : result.source.rawValue.uppercased()
                        print("   \(index + 1). [\(source)] \(result.displayName) - \(result.formattedAddress ?? "No address")")
                    }
                    
                    if response.results.count > 50 {
                        print("⚠️ [SEARCH] WARNING: Received \(response.results.count) results (limit was 50)")
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                print("❌ [SEARCH] Error: \(error.localizedDescription)")
                
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// ✅ SEARCH PLACE CONFIRM SHEET - EXACT PlaceInfoCard design with "Confirm Location" button
struct SearchPlaceConfirmSheet: View {
    let result: PlaceSearchResult
    let onConfirm: (PlaceSearchResult) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var locationManager = LocationManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // ✅ DRAG INDICATOR (like PlaceInfoCard)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // ✅ TOP SPACING (more padding before photos)
                        Spacer()
                            .frame(height: 20)
                        
                        // ✅ PHOTOS (API photos for new places, visit photos for existing)
                        photoSection
                        
                        // ✅ PLACE DETAILS (exact PlaceInfoCard layout)
                        VStack(alignment: .leading, spacing: 12) {
                            // Name
                            Text(result.displayName)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            
                            // Provider attribution
                            if result.source == .apple {
                                HStack(spacing: 4) {
                                    Image(systemName: "applelogo")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Text("Powered by Apple")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, -8)
                            } else if result.source == .google {
                                HStack(spacing: 4) {
                                    Image(systemName: "g.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Text("Powered by Google")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, -8)
                            }
                            
                            // ✅ RATING ROW (with stars - EXACT PlaceInfoCard design)
                            HStack(spacing: 12) {
                                // Rating with stars (0 if no rating)
                                HStack(spacing: 4) {
                                    Text("0")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    
                                    HStack(spacing: 2) {
                                        ForEach(0..<5) { _ in
                                            Image(systemName: "star")
                                                .font(.system(size: 10))
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                // ✅ DISTANCE (no background - minimalist design)
                                if let distance = locationManager.formattedDistance(from: result.coordinate) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "location.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                                        Text(distance)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                                    }
                                }
                            }
                            
                            // ✅ EXPANDED MODE DETAILS (always show in search)
                            expandedDetailsSection
                            
                            // Address (always show)
                            if let address = result.formattedAddress {
                                HStack(spacing: 4) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Text(address)
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            // ✅ CONFIRM LOCATION BUTTON (replaces "Add Visit" button)
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
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer()
                            .frame(height: max(20, geometry.safeAreaInsets.bottom + 20))
                    }
                }
            }
        }
        .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
    }
    
    // ✅ PHOTO SECTION (EXACT PlaceInfoCard design)
    @ViewBuilder
    private var photoSection: some View {
        let photoSize: CGFloat = 160
        
        if let photoUrls = result.photoUrls, !photoUrls.isEmpty {
            PhotoGridView(photos: Array(photoUrls.prefix(10)), photoSize: photoSize)
                .padding(.bottom, 20)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No photos yet")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
    
    // ✅ EXPANDED DETAILS SECTION (Instagram-level exquisite design)
    @ViewBuilder
    private var expandedDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .padding(.vertical, 8)
            
            // Status badge
            HStack(spacing: 8) {
                Image(systemName: result.existsInDb ? "checkmark.circle.fill" : "star.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(result.existsInDb ? .blue : Color(red: 1.0, green: 0.4, blue: 0.4))
                Text(result.existsInDb ? "In your network" : "New place - be the first!")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
            }
            
            // ✅ PRICE LEVEL ($ symbols)
            if let appleData = result.appleFullData {
                // Check if GooglePlaceData has price in the future
                // For now showing placeholder
                HStack(spacing: 6) {
                    Image(systemName: "yensign.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    Text("$$")  // TODO: Get from API when available
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
            
            // ✅ PHONE NUMBER
            if let appleData = result.appleFullData, let phone = appleData.phone {
                Button(action: {
                    if let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(red: 0.2, green: 0.78, blue: 0.35))
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Call")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(phone)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            
            // ✅ WEBSITE
            if let appleData = result.appleFullData, let website = appleData.website {
                Button(action: {
                    if let url = URL(string: website) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(red: 0.0, green: 0.48, blue: 1.0))
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: "safari.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Website")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(website.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            
            // ✅ OPENING HOURS (if available - Google only for now)
            // TODO: Add when GooglePlaceData includes opening_hours in response
            
            // Categories
            if let categories = result.categories, !categories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Categories")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(categories.prefix(5), id: \.self) { category in
                            Text(category)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.15))
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
    }
}

// PhotoGridView, PlaceholderPhotoView, and FlowLayout are already defined in PlaceInfoCard.swift
