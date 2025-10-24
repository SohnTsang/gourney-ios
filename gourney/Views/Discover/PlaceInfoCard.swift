// Views/Discover/PlaceInfoCard.swift
// Enhanced: Basic mode (rating stars) + Expanded mode (detailed info)

import SwiftUI
import MapKit

struct PlaceInfoCard: View {
    let place: Place
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var locationManager = LocationManager.shared
    @State private var visitPhotos: [String] = []
    @State private var isLoadingVisits = false
    @State private var friendVisitCount: Int = 0
    @State private var currentDetent: PresentationDetent = .fraction(0.4)
    
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
                        // Photos section (size depends on mode)
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
                            
                            // ✅ RATING ROW (with stars)
                            HStack(spacing: 12) {
                                // Rating with stars
                                if let rating = place.rating {
                                    HStack(spacing: 4) {
                                        Text(String(format: "%.1f", rating))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)
                                        
                                        // Star rating
                                        HStack(spacing: 2) {
                                            ForEach(0..<5) { index in
                                                Image(systemName: index < Int(rating.rounded()) ? "star.fill" : "star")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.yellow)
                                            }
                                        }
                                    }
                                } else {
                                    // No rating - show 0 with empty stars
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
                            
                            // ✅ EXPANDED MODE: Additional details
                            if currentDetent == .large {
                                expandedDetailsSection
                            }
                            
                            // Address (always show)
                            if let address = place.formattedAddress {
                                HStack(spacing: 4) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Text(address)
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(.gray)
                                        .lineLimit(currentDetent == .large ? nil : 2)
                                }
                            }
                            
                            // Open/Closed status (always show)
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
                            
                            // ✅ EXPANDED MODE: Action buttons row
                            if currentDetent == .large {
                                expandedActionsRow
                            }
                            
                            // ✅ BOTTOM ACTION BUTTONS (always visible)
                            bottomActionButtons
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer()
                            .frame(height: max(20, geometry.safeAreaInsets.bottom + 20))
                    }
                }
            }
        }
        .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
        .presentationDetents([.fraction(0.4), .large], selection: $currentDetent)
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
        .onDisappear {
            visitPhotos = []
            URLCache.shared.removeAllCachedResponses()
            isLoadingVisits = false
        }
        .task {
            await loadVisitData()
        }
    }
    
    // MARK: - Photo Section
    
    @ViewBuilder
    private var photoSection: some View {
        let isExpanded = currentDetent == .large
        let photoSize: CGFloat = isExpanded ? 160 : 120
        
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
        } else {
            PhotoGridView(photos: Array(visitPhotos.prefix(10)), photoSize: photoSize)
                .padding(.bottom, 20)
        }
    }
    
    // MARK: - Expanded Mode: Additional Details
    
    @ViewBuilder
    private var expandedDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .padding(.vertical, 8)
            
            // Friend visits count
            if friendVisitCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    Text("\(friendVisitCount) friend\(friendVisitCount == 1 ? "" : "s") visited")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
            
            // Categories
            if let categories = place.categories, !categories.isEmpty {
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
                                .background(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.1))
                                .cornerRadius(12)
                        }
                    }
                }
            }
            
            // Price level
            if let priceLevel = place.priceLevel {
                HStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("Price: " + String(repeating: "$", count: priceLevel))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
            
            // Phone
            if let phone = place.phoneNumber {
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text(phone)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
            
            // Website
            if let website = place.website {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text(website)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            // Opening hours
            if let hours = place.openingHours, !hours.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hours")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(hours.prefix(7), id: \.self) { hour in
                            Text(hour)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Expanded Mode: Action Buttons Row
    
    @ViewBuilder
    private var expandedActionsRow: some View {
        HStack(spacing: 12) {
            // Add to List button
            Button(action: {
                print("➕ Add to List tapped")
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    Text("Add to List")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            // Share button
            Button(action: {
                sharePlace()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    Text("Share")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            // Directions button
            Button(action: {
                openDirections()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    Text("Directions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Bottom Action Buttons (Always Visible)
    
    @ViewBuilder
    private var bottomActionButtons: some View {
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
                // Toggle between basic and expanded
                withAnimation {
                    currentDetent = currentDetent == .large ? .fraction(0.4) : .large
                }
            }) {
                Text(currentDetent == .large ? "Show Less" : "Details")
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
    
    // MARK: - Data Loading
    
    private func loadVisitData() async {
        isLoadingVisits = true
        
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // TODO: Fetch actual visit photos from backend
        // For now, use mock data
        visitPhotos = []
        
        // TODO: Fetch friend visit count
        friendVisitCount = Int.random(in: 0...5) // Mock data
        
        isLoadingVisits = false
    }
    
    // MARK: - Actions
    
    private func sharePlace() {
        // Share via iOS share sheet
        guard let url = URL(string: place.website ?? "https://gourney.app/place/\(place.id)") else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [
                "\(place.displayName)\n\(place.formattedAddress ?? "")",
                url
            ],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func openDirections() {
        // Open Apple Maps with directions
        let coordinate = place.coordinate
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = place.displayName
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault
        ])
    }
}

// MARK: - Photo Grid

struct PhotoGridView: View {
    let photos: [String]
    let photoSize: CGFloat
    
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
                                .frame(width: photoSize, height: photoSize)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        case .failure:
                            PlaceholderPhotoView(size: photoSize)
                        case .empty:
                            PlaceholderPhotoView(size: photoSize)
                                .overlay {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                        @unknown default:
                            PlaceholderPhotoView(size: photoSize)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

struct PlaceholderPhotoView: View {
    let size: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray6))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: size * 0.25))
                    .foregroundColor(.secondary)
            }
    }
}

// MARK: - Flow Layout (for categories)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            
            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
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
                    provider: .google,
                    googlePlaceId: "test",
                    applePlaceId: nil,
                    nameEn: "Ichiran Ramen",
                    nameJa: "一蘭ラーメン",
                    nameZh: nil,
                    lat: 35.6762,
                    lng: 139.6503,
                    formattedAddress: "1-22-7 Shibuya, Tokyo",
                    categories: ["ramen", "japanese", "noodles"],
                    photoUrls: ["https://example.com/photo1.jpg"],
                    openNow: true,
                    priceLevel: 2,
                    rating: 4.5,
                    userRatingsTotal: 1234,
                    phoneNumber: "+81-3-1234-5678",
                    website: "https://ichiran.com",
                    openingHours: ["Mon: 11:00 AM - 10:00 PM", "Tue: 11:00 AM - 10:00 PM"],
                    createdAt: nil,
                    updatedAt: nil
                )
            )
        }
}
