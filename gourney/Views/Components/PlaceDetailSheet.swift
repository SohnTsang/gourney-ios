// Views/Discover/Shared/PlaceDetailSheet.swift
// ✅ FINAL: No placeholders - only show actual photos

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
    
    @State private var visits: [EdgeFunctionVisit] = []
    @State private var visitCount: Int = 0
    @State private var isLoadingVisits = false
    @State private var cachedPhotoUrls: [String]? = nil
    @State private var hasPhotosLoaded = false  // ✅ Simple flag
    @State private var refreshTrigger = UUID()
    
    @State private var loadTask: Task<Void, Never>?
    
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
                        // ✅ Always show photo section (it handles empty state internally)
                        photoSection
                        
                        VStack(alignment: .leading, spacing: 0) {
                            // Name
                            Text(displayName)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                                .padding(.bottom, 8)
                            
                            // Rating with distance badge
                            RatingWithDistanceView(
                                rating: nil,
                                distance: calculateDistance()
                            )
                            .padding(.bottom, 4)
                            
                            // Address
                            if let address = formattedAddress, !address.isEmpty {
                                AddressView(address: address)
                                    .padding(.bottom, 16)
                            }
                            
                            // Visit status
                            VisitStatusView(visitCount: visitCount, isLoading: isLoadingVisits)
                                .padding(.bottom, 16)
                            
                            Divider()
                                .padding(.vertical, 16)
                            
                            // Phone
                            if let phone = phoneNumber, !phone.isEmpty {
                                PhoneButton(phone: phone)
                                Divider().padding(.vertical, 12)
                            }
                            
                            // Website
                            if let website = website, !website.isEmpty {
                                WebsiteButton(website: website)
                                Divider().padding(.vertical, 12)
                            }
                            
                            // Directions
                            DirectionsButton(
                                placeName: displayName,
                                address: formattedAddress ?? ""
                            )
                        }
                        .padding(.horizontal, 20)
                        
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
        .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .id(refreshTrigger)
        .task {
            loadTask = Task {
                await loadVisits()
            }
            await loadTask?.value
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }
    
    // MARK: - Photo Section
    
    @ViewBuilder
    private var photoSection: some View {
        let photoSize: CGFloat = 200
        
        if let photos = cachedPhotoUrls, !photos.isEmpty {
            ZStack {
                // Show skeleton until first photo loads
                if !hasPhotosLoaded {
                    LoadingPhotoView(height: photoSize)
                }
                
                // Photos (hidden until loaded)
                PhotoGridView(
                    photos: photos,
                    photoSize: photoSize,
                    onFirstPhotoLoaded: {
                        hasPhotosLoaded = true
                    }
                )
                .opacity(hasPhotosLoaded ? 1 : 0)
            }
            .padding(.top, 30)
            .padding(.bottom, 20)
        } else if isLoadingVisits {
            LoadingPhotoView(height: photoSize)
                .padding(.top, 30)
                .padding(.bottom, 20)
        } else {
            EmptyPhotoView(height: photoSize)
                .padding(.top, 30)
                .padding(.bottom, 20)
        }
    }
    
    // ✅ Pure function - computes photo URLs without side effects
    // Called ONCE when visits are loaded, result is cached
    private func computeTopVisitPhotos(from visits: [EdgeFunctionVisit]) -> [String] {
        print("📷 [computeTopVisitPhotos] Processing \(visits.count) visits")
        
        let sortedVisits = visits.sorted { visit1, visit2 in
            (visit1.likesCount ?? 0) > (visit2.likesCount ?? 0)
        }
        
        let topVisits = Array(sortedVisits.prefix(10))
        
        var photos: [String] = []
        for (index, visit) in topVisits.enumerated() {
            if let firstPhoto = visit.photoUrls.first {
                photos.append(firstPhoto)
                print("   [\(index+1)] ✅ Added photo from visit \(visit.id)")
            }
        }
        
        print("📸 [computeTopVisitPhotos] Returning \(photos.count) photo URLs")
        
        return photos
    }
    
    // ✅ Preload images so they're ready when skeleton disappears
    
    // MARK: - Data Loading
    
    private func loadVisits() async {
        guard !Task.isCancelled else { return }
        
        await MainActor.run {
            isLoadingVisits = true
        }
        
        print("🔍 [PlaceDetail] Opening place - ID: \(placeId), Name: \(displayName)")
        
        let tokenValid = await SupabaseClient.shared.ensureValidToken()
        if !tokenValid {
            print("❌ [PlaceDetail] Token validation failed")
            await MainActor.run {
                visits = []
                visitCount = 0
                isLoadingVisits = false
            }
            return
        }
        
        var attempts = 0
        let maxAttempts = 2
        
        while attempts < maxAttempts {
            attempts += 1
            
            do {
                let url = "\(Config.supabaseURL)/functions/v1/places-get-visits/\(placeId)?limit=10&friends_only=false"
                guard let requestURL = URL(string: url) else {
                    throw APIError.invalidResponse
                }
                
                var request = URLRequest(url: requestURL)
                request.httpMethod = "GET"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
                request.setValue("v1", forHTTPHeaderField: "X-API-Version")
                
                if let token = SupabaseClient.shared.getAuthToken() {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    
                    if let diagnostics = SupabaseClient.shared.diagnoseToken() {
                        diagnostics.printDiagnostics()
                    }
                } else {
                    print("⚠️ [PlaceDetail] No auth token available")
                }
                
                guard !Task.isCancelled else { return }
                
                let (data, urlResponse) = try await URLSession.shared.data(for: request)
                
                guard !Task.isCancelled else { return }
                
                guard let httpResponse = urlResponse as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                
                print("📥 [PlaceDetail] Response: \(httpResponse.statusCode) (attempt \(attempts)/\(maxAttempts))")
                
                if httpResponse.statusCode == 401 {
                    if attempts < maxAttempts {
                        print("⚠️ [PlaceDetail] Got 401, refreshing token and retrying...")
                        
                        if let refreshHandler = SupabaseClient.shared.authRefreshHandler {
                            let refreshed = await refreshHandler()
                            if refreshed {
                                print("✅ [PlaceDetail] Token refreshed, retrying request...")
                                continue
                            } else {
                                print("❌ [PlaceDetail] Token refresh failed")
                                throw APIError.unauthorized
                            }
                        } else {
                            print("❌ [PlaceDetail] No refresh handler available")
                            throw APIError.unauthorized
                        }
                    } else {
                        print("❌ [PlaceDetail] Max retry attempts reached")
                        throw APIError.unauthorized
                    }
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("❌ [PlaceDetail] Error response body: \(errorString)")
                    }
                    throw APIError.serverError
                }
                
                let decoder = JSONDecoder()
                let response = try decoder.decode(PlaceVisitsResponse.self, from: data)
                
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    visits = response.visits
                    visitCount = response.visitCount
                    isLoadingVisits = false
                    
                    // ✅ Compute photo URLs only once and cache them
                    cachedPhotoUrls = computeTopVisitPhotos(from: response.visits)
                }
                
                print("✅ [PlaceDetail] Loaded \(response.visits.count) visits, total count: \(response.visitCount)")
                print("📸 [PlaceDetail] Cached \(cachedPhotoUrls?.count ?? 0) photo URLs")
                
                let visitsWithLikes = response.visits.filter { ($0.likesCount ?? 0) > 0 }
                print("❤️ [PlaceDetail] Visits with likes: \(visitsWithLikes.count)")
                
                return
                
            } catch is CancellationError {
                print("⚠️ [PlaceDetail] Task cancelled")
                await MainActor.run {
                    isLoadingVisits = false
                }
                return
            } catch let error as APIError {
                guard !Task.isCancelled else { return }
                
                print("❌ [PlaceDetail] API Error: \(error)")
                
                if case .unauthorized = error {
                    // Already handled above with retry logic
                } else {
                    await MainActor.run {
                        visits = []
                        visitCount = 0
                        isLoadingVisits = false
                    }
                    return
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                print("❌ [PlaceDetail] Unexpected error: \(error)")
                await MainActor.run {
                    visits = []
                    visitCount = 0
                    isLoadingVisits = false
                }
                return
            }
        }
        
        await MainActor.run {
            visits = []
            visitCount = 0
            isLoadingVisits = false
        }
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
        guard let url = URL(string: website ?? "https://gourney.app/place/\(placeId)") else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [
                "\(displayName)\n\(formattedAddress ?? "")",
                url
            ],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Edge Function Response Models

struct PlaceVisitsResponse: Codable {
    let place: PlaceInfo
    let visits: [EdgeFunctionVisit]
    let nextCursor: String?
    let visitCount: Int
    
    enum CodingKeys: String, CodingKey {
        case place
        case visits
        case nextCursor = "next_cursor"
        case visitCount = "visit_count"
    }
}

struct PlaceInfo: Codable {
    let id: String
}

struct EdgeFunctionVisit: Codable, Identifiable {
    let id: String
    let userId: String
    let rating: Int?
    let comment: String?
    let photoUrls: [String]
    let visitedAt: String
    let userHandle: String
    let userDisplayName: String?
    let userAvatarUrl: String?
    let likesCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case rating
        case comment
        case photoUrls = "photo_urls"
        case visitedAt = "visited_at"
        case userHandle = "user_handle"
        case userDisplayName = "user_display_name"
        case userAvatarUrl = "user_avatar_url"
        case likesCount = "likes_count"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        rating = try container.decodeIfPresent(Int.self, forKey: .rating)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        photoUrls = try container.decode([String].self, forKey: .photoUrls)
        visitedAt = try container.decode(String.self, forKey: .visitedAt)
        userHandle = try container.decode(String.self, forKey: .userHandle)
        userDisplayName = try container.decodeIfPresent(String.self, forKey: .userDisplayName)
        userAvatarUrl = try container.decodeIfPresent(String.self, forKey: .userAvatarUrl)
        likesCount = try container.decodeIfPresent(Int.self, forKey: .likesCount)
    }
}
