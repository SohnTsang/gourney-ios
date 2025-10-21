// Views/Discover/PlacesListView.swift
// Scrollable list view of places with distance sorting

import SwiftUI
import CoreLocation

struct PlacesListView: View {
    let places: [PlaceListItem]
    let onPlaceTap: (PlaceListItem) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var locationManager = LocationManager.shared
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if places.isEmpty {
                    emptyState
                } else {
                    ForEach(places) { item in
                        PlaceListRow(
                            item: item,
                            distance: locationManager.formattedDistance(from: item.coordinate)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onPlaceTap(item)
                        }
                        
                        if item.id != places.last?.id {
                            Divider()
                                .padding(.leading, 90)
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
        .background(colorScheme == .dark ? Color(.systemBackground) : Color(.systemGroupedBackground))
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No places found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("Try searching or adjust your filters")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
}

// MARK: - Place List Row

struct PlaceListRow: View {
    let item: PlaceListItem
    let distance: String?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            placeThumbnail
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Name
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                
                // Metadata row
                HStack(spacing: 8) {
                    // Rating
                    if let rating = item.rating {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Price level
                    if let priceLevel = item.priceLevel {
                        Text(String(repeating: "$", count: priceLevel))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    
                    // Category
                    if let category = item.category {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(category)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                // Distance
                if let distance = distance {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                        Text(distance)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    }
                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
    }
    
    // MARK: - Thumbnail
    
    @ViewBuilder
    private var placeThumbnail: some View {
        if let photoUrl = item.photoUrl, let url = URL(string: photoUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 70, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure, .empty:
                    placeholderThumbnail
                @unknown default:
                    placeholderThumbnail
                }
            }
        } else {
            placeholderThumbnail
        }
    }
    
    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray5))
            .frame(width: 70, height: 70)
            .overlay {
                Image(systemName: "fork.knife")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary.opacity(0.5))
            }
    }
}

// MARK: - Place List Item Model

struct PlaceListItem: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let rating: Double?
    let priceLevel: Int?
    let category: String?
    let photoUrl: String?
    let isVisited: Bool
    
    // Original data
    let place: Place?
    let searchResult: PlaceSearchResult?
    
    // ✅ PERFORMANCE: Precomputed hash for equality checks
    private let cachedHash: Int
    
    init(from place: Place) {
        self.id = place.id
        self.name = place.displayName
        self.coordinate = place.coordinate
        self.rating = place.rating
        self.priceLevel = place.priceLevel
        self.category = place.categories?.first
        self.photoUrl = place.photoUrls?.first
        self.isVisited = true
        self.place = place
        self.searchResult = nil
        self.cachedHash = place.id.hashValue
    }
    
    init(from result: PlaceSearchResult) {
        self.id = result.id.uuidString
        self.name = result.displayName
        self.coordinate = result.coordinate
        self.rating = nil // Search results don't include rating yet
        self.priceLevel = nil
        self.category = result.categories?.first
        self.photoUrl = result.photoUrls?.first
        self.isVisited = result.existsInDb
        self.place = nil
        self.searchResult = result
        self.cachedHash = result.id.hashValue
    }
}

extension PlaceListItem: Hashable {
    static func == (lhs: PlaceListItem, rhs: PlaceListItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(cachedHash)
    }
}

// MARK: - Preview

#Preview {
    let samplePlaces = [
        PlaceListItem(
            from: Place(
                id: "1",
                provider: .google,
                googlePlaceId: "test1",
                applePlaceId: nil,
                nameEn: "Ichiran Ramen",
                nameJa: "一蘭ラーメン",
                nameZh: nil,
                lat: 35.6762,
                lng: 139.6503,
                formattedAddress: "Shibuya, Tokyo",
                categories: ["ramen", "japanese"],
                photoUrls: ["https://example.com/photo1.jpg"],
                openNow: true,
                priceLevel: 2,
                rating: 4.5,
                userRatingsTotal: 1234,
                phoneNumber: nil,
                website: nil,
                openingHours: nil,
                createdAt: nil,
                updatedAt: nil
            )
        )
    ]
    
    PlacesListView(places: samplePlaces) { _ in }
}
