// Views/Shared/PlaceRowView.swift
// Reusable restaurant row component with Gourney design system

import SwiftUI
import CoreLocation

struct PlaceRowView: View {
    let item: PlaceRowItem
    let distance: String?
    let showRemoveButton: Bool
    let onRemove: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        item: PlaceRowItem,
        distance: String? = nil,
        showRemoveButton: Bool = false,
        onRemove: (() -> Void)? = nil
    ) {
        self.item = item
        self.distance = distance
        self.showRemoveButton = showRemoveButton
        self.onRemove = onRemove
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            placeThumbnail
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Name
                Text(item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Rating + Stars + Visit Count
                HStack(spacing: 4) {
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
                            ForEach(0..<5) { _ in
                                Image(systemName: "star")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    // Visit count
                    if let visitCount = item.visitCount, visitCount > 0 {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text("\(visitCount) \(visitCount == 1 ? "visit" : "visits")")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Address
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
            
            // Right side - Remove button or chevron
            if showRemoveButton {
                Button(action: { onRemove?() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary.opacity(0.5))
            }
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

// MARK: - Place Row Item Model

struct PlaceRowItem: Identifiable {
    let id: String
    let name: String
    let rating: Double?
    let visitCount: Int?
    let address: String?
    let photoUrl: String?
    let coordinate: CLLocationCoordinate2D?
    
    // Initializers for different source types
    init(from place: Place) {
        self.id = place.id
        self.name = place.displayName
        self.rating = place.avgRating
        self.visitCount = place.visitCount
        self.address = place.formattedAddress
        self.photoUrl = place.photoUrls?.first
        self.coordinate = place.coordinate
    }
    
    init(from listItem: ListItem) {
        if let place = listItem.place {
            self.id = listItem.id
            self.name = place.displayName
            self.rating = place.avgRating
            self.visitCount = place.visitCount
            self.address = place.formattedAddress
            self.photoUrl = place.photoUrls?.first
            self.coordinate = place.coordinate
        } else {
            self.id = listItem.id
            self.name = "Unknown Place"
            self.rating = nil
            self.visitCount = nil
            self.address = nil
            self.photoUrl = nil
            self.coordinate = nil
        }
    }
    
    init(from placeWithVisits: PlaceWithVisits) {
        self.id = placeWithVisits.place.id
        self.name = placeWithVisits.place.displayName
        self.rating = placeWithVisits.place.avgRating
        self.visitCount = placeWithVisits.visitCount
        self.address = placeWithVisits.place.formattedAddress
        self.photoUrl = placeWithVisits.place.photoUrls?.first
        self.coordinate = placeWithVisits.place.coordinate
    }
    
    init(from searchResult: PlaceSearchResult) {
        self.id = searchResult.id.uuidString
        self.name = searchResult.displayName
        self.rating = nil
        self.visitCount = nil
        self.address = searchResult.formattedAddress
        self.photoUrl = searchResult.photoUrls?.first
        self.coordinate = searchResult.coordinate
    }
}
