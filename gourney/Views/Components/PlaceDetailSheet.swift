// Views/Components/PlaceDetailSheet.swift
// ✅ SIMPLIFIED: Single loading overlay, show all at once

import SwiftUI
import CoreLocation

struct PlaceDetailSheet: View {
    // Data source
    let placeId: String
    let displayName: String
    let lat: Double
    let lng: Double
    let formattedAddress: String?
    let phoneNumber: String?
    let website: String?
    let photoUrls: [String]?
    
    // Action configuration
    let primaryButtonTitle: String
    let primaryButtonAction: () -> Void
    let onDismiss: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var locationManager = LocationManager.shared
    
    @State private var isLoading = true
    @State private var visits: [EdgeFunctionVisit] = []
    @State private var visitCount: Int = 0
    @State private var avgRating: Double? = nil
    @State private var placeAddress: String? = nil
    @State private var placePhone: String? = nil
    @State private var placeWebsite: String? = nil
    @State private var cachedPhotoUrls: [String]? = nil
    
    var body: some View {
        ZStack {
            // Content (hidden while loading)
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
                            VStack(alignment: .leading, spacing: 0) {
                                // Name (semibold only)
                                Text(displayName)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .padding(.bottom, 8)
                                
                                // Rating with distance badge
                                RatingWithDistanceView(
                                    rating: avgRating,
                                    distance: calculateDistance()
                                )
                                .padding(.bottom, 4)
                                
                                // Address
                                if let address = placeAddress ?? formattedAddress, !address.isEmpty {
                                    AddressView(address: address)
                                        .padding(.bottom, 16)
                                }
                                
                                // Visit status
                                VisitStatusView(visitCount: visitCount, isLoading: false)
                                    .padding(.bottom, 20)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            
                            // Photos section (after name/rating/address/visit)
                            if let photos = cachedPhotoUrls, !photos.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(Array(photos.enumerated()), id: \.offset) { index, photoUrl in
                                            AsyncImage(url: URL(string: photoUrl)) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 160, height: 213)
                                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                                case .failure(_):
                                                    // Don't show placeholder for failed images
                                                    EmptyView()
                                                case .empty:
                                                    ProgressView()
                                                        .frame(width: 160, height: 213)
                                                @unknown default:
                                                    EmptyView()
                                                }
                                            }
                                            .id("\(photoUrl)-\(index)")  // Force refresh on URL change
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                                .frame(height: 213)
                                .padding(.bottom, 20)
                            } else {
                                // Empty photo placeholder (3:4 ratio)
                                VStack(spacing: 12) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary.opacity(0.3))
                                    Text("Add the first photo here!")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 213)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                            }
                            
                            VStack(alignment: .leading, spacing: 0) {
                                Divider()
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 16)
                                
                                // Directions
                                DirectionsButton(
                                    placeName: displayName,
                                    address: placeAddress ?? formattedAddress ?? ""
                                )
                                .padding(.horizontal, 20)
                                
                                Divider()
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                
                                // Phone
                                if let phone = placePhone ?? phoneNumber, !phone.isEmpty {
                                    PhoneButton(phone: phone)
                                        .padding(.horizontal, 20)
                                    Divider()
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                }
                                
                                // Website
                                if let website = placeWebsite ?? website, !website.isEmpty {
                                    WebsiteButton(website: website)
                                        .padding(.horizontal, 20)
                                    Divider()
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                }
                            }
                            
                            Spacer().frame(height: 100)
                        }
                    }
                    
                    // Bottom buttons
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Button {
                                primaryButtonAction()
                            } label: {
                                Text(primaryButtonTitle)
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
                            
                            Button {
                                sharePlace()
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 48, height: 48)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, max(12, geometry.safeAreaInsets.bottom + 12))
                        .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
                    }
                }
            }
            .opacity(isLoading ? 0 : 1)  // ✅ Hide ALL content while loading
            
            // Loading overlay (on top)
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading place info...")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
                .transition(.opacity)
            }
        }
        .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
        .presentationDetents([.fraction(0.4), .large])
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
        .id(placeId)  // ✅ Force reload when placeId changes
        .onChange(of: placeId) { _ in
            // ✅ Immediately show loading when placeId changes (prevents name flash)
            isLoading = true
            cachedPhotoUrls = nil
            visits = []
            avgRating = nil
            placeAddress = nil
            placePhone = nil
            placeWebsite = nil
        }
        .task(id: placeId) {  // ✅ Reload when placeId changes
            await loadAllData()
        }
        .onDisappear {
            // ✅ Aggressive memory cleanup
            cachedPhotoUrls = nil
            visits = []
            avgRating = nil
            placeAddress = nil
            placePhone = nil
            placeWebsite = nil
            
            // ✅ Clear URL cache aggressively to free memory
            URLCache.shared.removeAllCachedResponses()
            
            // ✅ Force memory cleanup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                URLCache.shared.diskCapacity = 0
                URLCache.shared.memoryCapacity = 0
                URLCache.shared.diskCapacity = 10 * 1024 * 1024 // Reset to 10MB
                URLCache.shared.memoryCapacity = 5 * 1024 * 1024 // Reset to 5MB
            }
            
            print("💾 [PlaceDetail] Memory cleaned on disappear")
        }
    }
    
    // MARK: - Load All Data at Once
    
    private func loadAllData() async {
        await MainActor.run {
            isLoading = true
            // Clear previous data IMMEDIATELY to free memory
            cachedPhotoUrls = nil
            visits = []
            avgRating = nil
            placeAddress = nil
            placePhone = nil
            placeWebsite = nil
        }
        
        print("🔍 [PlaceDetail] Loading all data for: \(placeId), Name: \(displayName)")
        print("💾 [PlaceDetail] Memory cleared before loading")
        
        // Load visits and place data in parallel
        async let visitsTask = fetchVisits()
        async let placeDataTask = fetchPlaceData(placeId: placeId)
        
        let visitsResult = await visitsTask
        let placeDataResult: (address: String?, phone: String?, website: String?, avgRating: Double?)?
        do {
            placeDataResult = try await placeDataTask
        } catch {
            print("❌ [PlaceDetail] Failed to fetch place data: \(error)")
            placeDataResult = nil
        }
        
        await MainActor.run {
            // Set visits
            if let visitsResult = visitsResult {
                visits = visitsResult.visits
                visitCount = visitsResult.visitCount
                // ✅ MEMORY FIX: Limit to max 3 photos to prevent memory bloat (was 5)
                let allPhotos = computeTopVisitPhotos(from: visitsResult.visits)
                // ✅ Filter out empty/invalid URLs
                let validPhotos = allPhotos.filter { !$0.isEmpty && URL(string: $0) != nil }
                cachedPhotoUrls = Array(validPhotos.prefix(3))
                print("💾 [PlaceDetail] Limited photos from \(allPhotos.count) to \(cachedPhotoUrls?.count ?? 0)")
            }
            
            // Set place data
            if let placeData = placeDataResult {
                avgRating = placeData.avgRating
                placeAddress = placeData.address
                placePhone = placeData.phone
                placeWebsite = placeData.website
            }
            
            isLoading = false
            
            print("✅ [PlaceDetail] All data loaded:")
            print("   avgRating: \(avgRating ?? 0.0)")
            print("   placeAddress: \(placeAddress ?? "nil")")
            print("   placePhone: \(placePhone ?? "nil")")
            print("   placeWebsite: \(placeWebsite ?? "nil")")
            print("   visitCount: \(visitCount)")
            print("   photoCount: \(cachedPhotoUrls?.count ?? 0)")
        }
    }
    
    // MARK: - Fetch Visits
    
    private func fetchVisits() async -> (visits: [EdgeFunctionVisit], visitCount: Int)? {
        do {
            let url = "\(Config.supabaseURL)/functions/v1/places-get-visits/\(placeId)?limit=10&friends_only=false"
            guard let requestURL = URL(string: url) else { return nil }
            
            var request = URLRequest(url: requestURL)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("v1", forHTTPHeaderField: "X-API-Version")
            
            if let token = SupabaseClient.shared.getAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            let decoder = JSONDecoder()
            let result = try decoder.decode(PlaceVisitsResponse.self, from: data)
            
            return (result.visits, result.visitCount)
        } catch {
            print("❌ [PlaceDetail] Failed to fetch visits: \(error)")
            return nil
        }
    }
    
    // MARK: - Compute Top Photos
    
    private func computeTopVisitPhotos(from visits: [EdgeFunctionVisit]) -> [String] {
        // ✅ First filter to only visits that HAVE photos
        let visitsWithPhotos = visits.filter { !$0.photoUrls.isEmpty }
        // Then sort by likes and get top 10
        let sortedVisits = visitsWithPhotos.sorted { ($0.likesCount ?? 0) > ($1.likesCount ?? 0) }
        let topVisits = Array(sortedVisits.prefix(10))
        return topVisits.compactMap { $0.photoUrls.first }
    }
    
    // MARK: - Helpers
    
    private func calculateDistance() -> String? {
        guard let userLocation = locationManager.userLocation else { return nil }
        
        let placeLocation = CLLocation(latitude: lat, longitude: lng)
        let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let distance = userCLLocation.distance(from: placeLocation)
        
        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
    
    private func sharePlace() {
        guard let url = URL(string: website ?? placeWebsite ?? "https://gourney.app/place/\(placeId)") else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [
                "\(displayName)\n\(placeAddress ?? formattedAddress ?? "")",
                url
            ],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func fetchPlaceData(placeId: String) async throws -> (address: String?, phone: String?, website: String?, avgRating: Double?)? {
        print("🏢 [PlaceData] Fetching place details for: \(placeId)")
        
        let url = "\(Config.supabaseURL)/functions/v1/places-detail/\(placeId)"
        guard let requestURL = URL(string: url) else { return nil }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("v1", forHTTPHeaderField: "X-API-Version")
        
        if let token = SupabaseClient.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        
        struct PlaceDetailResponse: Codable {
            let place: PlaceObject
            
            struct PlaceObject: Codable {
                let address: String?
                let phone: String?
                let website: String?
                let avgRating: Double?
                let attributes: PlaceAttributes?
                
                enum CodingKeys: String, CodingKey {
                    case address, phone, website
                    case avgRating = "avg_rating"
                    case attributes
                }
            }
        }
        
        struct PlaceAttributes: Codable {
            let formattedAddress: String?
            let phone: String?
            let website: String?
            
            enum CodingKeys: String, CodingKey {
                case formattedAddress = "formatted_address"
                case phone, website
            }
        }
        
        let decoder = JSONDecoder()
        let placeResponse = try decoder.decode(PlaceDetailResponse.self, from: data)
        let placeDetail = placeResponse.place
        
        // Priority: Direct columns > attributes JSONB
        let finalAddress = placeDetail.address ?? placeDetail.attributes?.formattedAddress
        let finalPhone = placeDetail.phone ?? placeDetail.attributes?.phone
        let finalWebsite = placeDetail.website ?? placeDetail.attributes?.website
        
        return (
            address: finalAddress,
            phone: finalPhone,
            website: finalWebsite,
            avgRating: placeDetail.avgRating
        )
    }
}
