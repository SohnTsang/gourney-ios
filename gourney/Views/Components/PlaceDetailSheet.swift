// Views/Discover/Shared/PlaceDetailSheet.swift
// ✅ SHARED component used by both PlaceInfoCard and SearchPlaceConfirmSheet
// ✅ Uses Edge Function for consistent data fetching
// ✅ Single source of truth - update once, applies everywhere

import SwiftUI
import CoreLocation

struct PlaceDetailSheet: View {
    // Data source - either a Place or PlaceSearchResult
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
    @State private var refreshTrigger = UUID()
    
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
                            Text(displayName)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                                .padding(.bottom, 8)
                            
                            // Rating with distance badge
                            RatingWithDistanceView(
                                rating: nil,  // Edge Function doesn't return rating yet
                                distance: calculateDistance()
                            )
                            .padding(.bottom, 4)
                            
                            // Address (small font, under rating)
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
            await loadVisits()
        }
    }
    
    // MARK: - Photo Section
    
    @ViewBuilder
    private var photoSection: some View {
        let photoSize: CGFloat = 200
        
        // Show photos from photoUrls (Google/Apple preview photos)
        if let photoUrls = photoUrls, !photoUrls.isEmpty {
            PhotoGridView(photos: Array(photoUrls.prefix(10)), photoSize: photoSize)
                .padding(.top, 30)
                .padding(.bottom, 20)
        } else {
            EmptyPhotoView(height: photoSize)
        }
    }
    
    // MARK: - Data Loading (Edge Function)
    
    private func loadVisits() async {
        isLoadingVisits = true
        
        print("🔍 [PlaceDetail] Opening place - ID: \(placeId), Name: \(displayName)")
        print("🔍 [PlaceDetail] Auth status - isAuthenticated: \(AuthManager.shared.isAuthenticated)")
        
        do {
            // ✅ Use Edge Function with manual URLSession (no snake_case auto-conversion)
            let url = "\(Config.supabaseURL)/functions/v1/places-get-visits/\(placeId)?limit=10&friends_only=false"
            guard let requestURL = URL(string: url) else {
                throw APIError.invalidResponse
            }
            
            var request = URLRequest(url: requestURL)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("v1", forHTTPHeaderField: "X-API-Version")  // ✅ REQUIRED by Edge Function
            
            // Add auth token
            if let token = SupabaseClient.shared.getAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            print("📥 [PlaceDetail] Response: \(httpResponse.statusCode)")
            
            // Handle errors
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                // Log the actual error response
                if let errorString = String(data: data, encoding: .utf8) {
                    print("❌ [PlaceDetail] Error response body: \(errorString)")
                }
                throw APIError.serverError
            }
            
            // ✅ Manual decoding WITHOUT snake_case conversion
            let decoder = JSONDecoder()
            // DON'T set keyDecodingStrategy - let our custom CodingKeys handle it
            
            let response = try decoder.decode(PlaceVisitsResponse.self, from: data)
            
            await MainActor.run {
                visits = response.visits
                visitCount = response.visitCount
                isLoadingVisits = false
            }
            
            print("✅ [PlaceDetail] Loaded \(response.visits.count) visits, total count: \(response.visitCount)")
            
        } catch let error as APIError {
            print("❌ [PlaceDetail] API Error: \(error)")
            print("❌ [PlaceDetail] Error description: \(error.errorDescription ?? "unknown")")
            
            if case .unauthorized = error {
                print("⚠️ [PlaceDetail] User not authenticated - triggering auth refresh")
                Task { @MainActor in
                    await AuthManager.shared.checkAuthStatus()
                }
            }
            
            await MainActor.run {
                visits = []
                visitCount = 0
                isLoadingVisits = false
            }
        } catch {
            print("❌ [PlaceDetail] Unexpected error: \(error)")
            await MainActor.run {
                visits = []
                visitCount = 0
                isLoadingVisits = false
            }
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

// MARK: - Edge Function Response Models (Shared)

// MARK: - Edge Function Response Models (Updated with photo_urls)

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
    let photoUrls: [String]  // ✅ ADDED - now includes photos!
    let visitedAt: String
    let userHandle: String
    let userDisplayName: String?  // ✅ ADDED for better UX
    let userAvatarUrl: String?    // ✅ ADDED for better UX
    
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
    }
    
    // ✅ Custom decoder to handle exact field names from Edge Function
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
    }
}
