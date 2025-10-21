// Views/Discover/PlaceInfoCard.swift
// Enhanced with distance display and optimized performance

import SwiftUI

struct PlaceInfoCard: View {
    let place: Place
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var locationManager = LocationManager.shared
    @State private var visitPhotos: [String] = []
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
                        // Photos section
                        photoSection
                        
                        // Place details
                        VStack(alignment: .leading, spacing: 12) {
                            // Name
                            Text(place.displayName)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            
                            // Provider attribution
                            if place.provider == .apple {
                                HStack(spacing: 4) {
                                    Image(systemName: "applelogo")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Text("Powered by Apple")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, -8)
                            }
                            
                            // ✅ METADATA ROW: Rating, Category, Distance
                            HStack(spacing: 12) {
                                // Rating
                                if let rating = place.rating {
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.yellow)
                                        Text(String(format: "%.1f", rating))
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.gray)
                                    }
                                }
                                
                                // Category
                                if let categories = place.categories, !categories.isEmpty {
                                    Text(categories.first ?? "")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.gray)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.1))
                                        .cornerRadius(12)
                                }
                                
                                Spacer()
                                
                                // ✅ DISTANCE BADGE
                                if let distance = locationManager.formattedDistance(from: place.coordinate) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "location.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                                        Text(distance)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.1))
                                    .cornerRadius(12)
                                }
                            }
                            
                            // Address
                            if let address = place.formattedAddress {
                                HStack(spacing: 4) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Text(address)
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(.gray)
                                        .lineLimit(2)
                                }
                            }
                            
                            // Open/Closed status
                            if let openNow = place.openNow {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(openNow ? Color.green : Color.red)
                                        .frame(width: 6, height: 6)
                                    Text(openNow ? "Open" : "Closed")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(openNow ? .green : .red)
                                }
                            }
                            
                            // Action buttons
                            HStack(spacing: 12) {
                                Button(action: {
                                    print("🎯 Add Visit tapped for: \(place.displayName)")
                                }) {
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
                                
                                Button(action: {
                                    print("ℹ️ View Details tapped for: \(place.displayName)")
                                }) {
                                    Text("Details")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(12)
                                }
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
        .presentationDetents([.fraction(0.4), .large])
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
        .onDisappear {
            // Free any photo URLs and drop capacity so images can be reclaimed
            visitPhotos.removeAll(keepingCapacity: false)
            isLoadingVisits = false  // (optional) ensure spinner state is reset
        }
        .task {
            await loadVisitPhotos()
        }
    }
    
    // MARK: - Photo Section
    
    @ViewBuilder
    private var photoSection: some View {
        if isLoadingVisits {
            HStack {
                ProgressView()
                Text("Loading...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if visitPhotos.isEmpty {
            if let photoUrls = place.photoUrls, !photoUrls.isEmpty {
                PhotoGridView(photos: Array(photoUrls.prefix(10)))
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
        } else {
            PhotoGridView(photos: Array(visitPhotos.prefix(10)))
                .padding(.bottom, 20)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadVisitPhotos() async {
        isLoadingVisits = true
        
        // ✅ PERFORMANCE: Simulate network delay
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // TODO: Fetch actual visit photos from backend
        visitPhotos = []
        
        isLoadingVisits = false
    }
}

// MARK: - Photo Grid

struct PhotoGridView: View {
    let photos: [String]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(photos, id: \.self) { photoUrl in
                    AsyncImage(url: URL(string: photoUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        case .failure:
                            PlaceholderPhotoView()
                        case .empty:
                            PlaceholderPhotoView()
                                .overlay {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                        @unknown default:
                            PlaceholderPhotoView()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

struct PlaceholderPhotoView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray6))
            .frame(width: 120, height: 120)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
            }
    }
}

// MARK: - Preview

#Preview {
    Text("Map View")
        .sheet(isPresented: .constant(true)) {
            PlaceInfoCard(
                place: Place(
                    id: UUID().uuidString,
                    provider: .apple,
                    googlePlaceId: nil,
                    applePlaceId: "test",
                    nameEn: "Test Restaurant",
                    nameJa: nil,
                    nameZh: nil,
                    lat: 35.6762,
                    lng: 139.6503,
                    formattedAddress: "Tokyo, Japan",
                    categories: ["restaurant"],
                    photoUrls: nil,
                    openNow: true,
                    priceLevel: 2,
                    rating: 4.5,
                    userRatingsTotal: 100,
                    phoneNumber: nil,
                    website: nil,
                    openingHours: nil,
                    createdAt: nil,
                    updatedAt: nil
                )
            )
        }
}
