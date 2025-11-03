// Views/Discover/PlacesListView.swift
// ✅ List view for places with distance sorting

import SwiftUI
import CoreLocation

struct PlacesListView: View {
    let places: [PlaceListItem]
    let onPlaceTap: (PlaceListItem) -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    @StateObject private var locationManager = LocationManager.shared
    @State private var displayedCount = 20  // ✅ ADD THIS

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if places.isEmpty {
                        emptyState
                    } else {
                        ForEach(displayedPlaces) { item in
                            PlaceListRow(
                                item: item,
                                distance: locationManager.formattedDistance(from: item.coordinate)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onPlaceTap(item)
                            }
                            
                            if item.id != displayedPlaces.last?.id {
                                Divider()
                                    .padding(.leading, 90)
                            }
                        }
                        
                        if hasMore {
                            loadMoreView
                                .onAppear {
                                    loadMore()
                                }
                        }
                    }
                }
                .padding(.bottom, 0)
            }
            .frame(height: geometry.size.height)
            .background(colorScheme == .dark ? Color(.systemBackground) : Color(.systemGroupedBackground))
        }
    }
    
    // ✅ ADD THESE
    private var displayedPlaces: [PlaceListItem] {
        Array(places.prefix(displayedCount))
    }

    private var hasMore: Bool {
        displayedCount < places.count
    }

    private var loadMoreView: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding(.vertical, 20)
            Spacer()
        }
    }

    private func loadMore() {
        guard hasMore else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                displayedCount += 20
            }
        }
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
                
                // Rating + stars + visit count on same line
                HStack(spacing: 4) {
                    // Rating
                    if let rating = item.rating {
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 2) {
                            ForEach(0..<5) { index in
                                Image(systemName: index < Int(rating.rounded()) ? "star.fill" : "star")
                                    .font(.system(size: 10))
                                    .foregroundColor(index < Int(rating.rounded()) ? .yellow : .gray)
                            }
                        }
                    } else {
                        Text("0")
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
                    
                    // Visit count
                    if let visitCount = item.visitCount {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text("\(visitCount) \(visitCount == 1 ? "visit" : "visits")")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                .onAppear {
                    print("🔍 [PlaceListRow] Item: \(item.name)")
                    print("   Rating: \(item.rating?.description ?? "nil")")
                    print("   Visit Count: \(item.visitCount?.description ?? "nil")")
                    print("   Address: \(item.address ?? "nil")")
                }
                
                // Address below rating
                if let address = item.address, !address.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(address)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("🚨 No address data")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
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
                        .onDisappear {
                            // Force image to be released when scrolled away
                            URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
                        }
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

struct PlaceListItem: Identifiable, Hashable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let rating: Double?
    let priceLevel: Int?
    let category: String?
    let photoUrl: String?
    let isVisited: Bool
    let visitCount: Int?
    let address: String?
    
    // Original data
    let place: Place?
    let searchResult: PlaceSearchResult?
    
    init(from place: Place) {
        self.id = place.id
        self.name = place.displayName
        self.coordinate = place.coordinate
        self.rating = place.rating
        self.priceLevel = place.priceLevel
        self.category = place.categories?.first
        self.photoUrl = place.photoUrls?.first
        self.isVisited = true
        self.visitCount = place.visitCount  // ✅ FIX: Was nil
        self.address = place.formattedAddress
        self.place = place
        self.searchResult = nil
    }
    
    init(from placeWithVisits: PlaceWithVisits) {
        self.id = placeWithVisits.place.id
        self.name = placeWithVisits.place.displayName
        self.coordinate = placeWithVisits.place.coordinate
        self.rating = placeWithVisits.place.rating
        self.priceLevel = placeWithVisits.place.priceLevel
        self.category = placeWithVisits.place.categories?.first
        self.photoUrl = placeWithVisits.place.photoUrls?.first
        self.isVisited = true
        self.visitCount = placeWithVisits.visitCount
        self.address = placeWithVisits.place.formattedAddress
        self.place = placeWithVisits.place
        self.searchResult = nil
    }
    
    init(from result: PlaceSearchResult) {
        self.id = result.id.uuidString
        self.name = result.displayName
        self.coordinate = result.coordinate
        self.rating = nil
        self.priceLevel = nil
        self.category = result.categories?.first
        self.photoUrl = result.photoUrls?.first
        self.isVisited = result.existsInDb
        self.visitCount = nil
        self.address = result.formattedAddress
        self.place = nil
        self.searchResult = result
    }
    
    static func == (lhs: PlaceListItem, rhs: PlaceListItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
