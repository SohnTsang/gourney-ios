// Views/Discover/PlacesListView.swift
// ✅ Updated to use shared PlaceRowView component

import SwiftUI
import CoreLocation

struct PlacesListView: View {
    let places: [PlaceListItem]
    let onPlaceTap: (PlaceListItem) -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    @StateObject private var locationManager = LocationManager.shared
    @State private var displayedCount = 20

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if places.isEmpty {
                        emptyState
                    } else {
                        ForEach(displayedPlaces) { item in
                            PlaceRowView(
                                item: PlaceRowItem(from: item),
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
    
    private var displayedPlaces: [PlaceListItem] {
        let userLocation = locationManager.userLocation
        
        let sorted = places.sorted { a, b in
            guard let userLoc = userLocation else { return false }
            let distA = CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude)
                .distance(from: CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude))
            let distB = CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude)
                .distance(from: CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude))
            return distA < distB
        }
        
        return Array(sorted.prefix(displayedCount))
    }

    private var hasMore: Bool {
        displayedCount < places.count
    }

    private var loadMoreView: some View {
        HStack {
            Spacer()
            ProgressView()
                .tint(Color(red: 1.0, green: 0.4, blue: 0.4))
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
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3))
            
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

// MARK: - Place List Item Model (Keep for backward compatibility)

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
        self.rating = place.avgRating
        self.priceLevel = place.priceLevel
        self.category = place.categories?.first
        self.photoUrl = place.photoUrls?.first
        self.isVisited = true
        self.visitCount = place.visitCount
        self.address = place.formattedAddress
        self.place = place
        self.searchResult = nil
    }
    
    init(from placeWithVisits: PlaceWithVisits) {
        self.id = placeWithVisits.place.id
        self.name = placeWithVisits.place.displayName
        self.coordinate = placeWithVisits.place.coordinate
        self.rating = placeWithVisits.place.avgRating
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

// MARK: - Extension to convert PlaceListItem to PlaceRowItem

extension PlaceRowItem {
    init(from placeListItem: PlaceListItem) {
        self.id = placeListItem.id
        self.name = placeListItem.name
        self.rating = placeListItem.rating
        self.visitCount = placeListItem.visitCount
        self.address = placeListItem.address
        self.photoUrl = placeListItem.photoUrl
        self.coordinate = placeListItem.coordinate
    }
}
