// Views/Discover/PlaceInfoCard.swift
// ✅ FIXED: Uses RatingWithDistanceView instead of RatingView

import SwiftUI
import MapKit

struct PlaceInfoCard: View {
    let place: Place
    var onDismiss: (() -> Void)?
    var onRefreshNeeded: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var locationManager = LocationManager.shared
    @State private var visits: [Visit] = []
    @State private var isLoadingVisits = false
    @State private var showAddVisit = false
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
                            Text(place.displayName)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                                .padding(.bottom, 8)
                            
                            // Rating with distance badge
                            RatingWithDistanceView(
                                rating: place.rating,
                                distance: calculateDistance()
                            )
                            .padding(.bottom, 4)
                            
                            // Address (small font, under rating)
                            if let address = place.formattedAddress, !address.isEmpty {
                                AddressView(address: address)
                                    .padding(.bottom, 16)
                            }
                            
                            // Visit status
                            VisitStatusView(visitCount: visits.count, isLoading: isLoadingVisits)
                                .padding(.bottom, 16)
                            
                            Divider()
                                .padding(.vertical, 16)
                            
                            // Phone
                            if let phone = place.phoneNumber, !phone.isEmpty {
                                PhoneButton(phone: phone)
                                Divider().padding(.vertical, 12)
                            }
                            
                            // Website
                            if let website = place.website, !website.isEmpty {
                                WebsiteButton(website: website)
                                Divider().padding(.vertical, 12)
                            }
                            
                            // Directions
                            DirectionsButton(
                                placeName: place.displayName,
                                address: place.formattedAddress ?? ""
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
                            showAddVisit = true
                        } label: {
                            Text("Add Visit")
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
        .sheet(isPresented: $showAddVisit) {
            AddVisitView(prefilledPlace: PlaceSearchResult(from: place))
        }
        .onChange(of: showAddVisit) { oldValue, newValue in
            // ✅ Refresh when sheet closes
            if oldValue == true && newValue == false {
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)  // Wait 0.5s for backend
                    await loadVisits()
                    onRefreshNeeded?()
                    refreshTrigger = UUID()
                }
            }
        }
    }
    
    // MARK: - Photo Section
    
    @ViewBuilder
    private var photoSection: some View {
        let photoSize: CGFloat = 200
        
        if !visits.isEmpty {
            let allPhotos = visits.flatMap { $0.photoUrls }
            if !allPhotos.isEmpty {
                PhotoGridView(photos: Array(allPhotos.prefix(10)), photoSize: photoSize)
                    .padding(.top, 30)
                    .padding(.bottom, 20)
            } else if let photoUrls = place.photoUrls, !photoUrls.isEmpty {
                PhotoGridView(photos: Array(photoUrls.prefix(10)), photoSize: photoSize)
                    .padding(.top, 30)
                    .padding(.bottom, 20)
            } else {
                EmptyPhotoView(height: photoSize)
            }
        } else if let photoUrls = place.photoUrls, !photoUrls.isEmpty {
            PhotoGridView(photos: Array(photoUrls.prefix(10)), photoSize: photoSize)
                .padding(.top, 30)
                .padding(.bottom, 20)
        } else {
            EmptyPhotoView(height: photoSize)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadVisits() async {
        isLoadingVisits = true
        
        do {
            // ✅ Fetch real visits from backend
            let response: [Visit] = try await SupabaseClient.shared.get(
                path: "/rest/v1/visits",
                queryItems: [
                    URLQueryItem(name: "place_id", value: "eq.\(place.id)"),
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
            
            print("✅ [PlaceInfo] Loaded \(response.count) visits for place: \(place.displayName)")
            
        } catch {
            print("❌ [PlaceInfo] Failed to load visits: \(error)")
            await MainActor.run {
                visits = []
                isLoadingVisits = false
            }
        }
    }
    
    // MARK: - Helpers
    
    private func calculateDistance() -> String? {
        guard let userLocation = locationManager.userLocation else { return nil }
        
        let placeLocation = CLLocation(latitude: place.lat, longitude: place.lng)
        let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let distance = userCLLocation.distance(from: placeLocation)
        
        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
    
    private func sharePlace() {
        guard let url = URL(string: place.website ?? "https://gourney.app/place/\(place.id)") else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [
                "\(place.displayName)\n\(place.formattedAddress ?? "")",
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

// MARK: - PlaceSearchResult Extension

extension PlaceSearchResult {
    init(from place: Place) {
        self.init(
            source: place.provider == .apple ? .apple : .google,
            googlePlaceId: place.googlePlaceId,
            applePlaceId: place.applePlaceId,
            nameEn: place.nameEn,
            nameJa: place.nameJa,
            nameZh: place.nameZh,
            lat: place.lat,
            lng: place.lng,
            formattedAddress: place.formattedAddress,
            categories: place.categories,
            photoUrls: place.photoUrls,
            existsInDb: true,
            dbPlaceId: place.id,
            appleFullData: nil
        )
    }
}
