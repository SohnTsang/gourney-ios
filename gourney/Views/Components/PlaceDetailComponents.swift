// Views/Discover/Shared/PlaceDetailComponents.swift
// ✅ EXACT ORIGINAL DESIGN: No categories, address under rating, distance badge on right
// ✅ UPDATED: AddressView without mappin icon

import SwiftUI

// MARK: - Photo Grid View

struct PhotoGridView: View {
    let photos: [String]
    let photoSize: CGFloat
    let onFirstPhotoLoaded: () -> Void
    
    @State private var hasNotified = false
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, photoUrl in
                    AsyncImage(url: URL(string: photoUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: photoSize, height: photoSize)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .onAppear {
                                    if !hasNotified {
                                        hasNotified = true
                                        onFirstPhotoLoaded()
                                        print("✅ [Photo \(index+1)/\(photos.count)] First photo loaded - hiding skeleton")
                                    }
                                }
                        case .failure(let error):
                            EmptyView()
                                .onAppear {
                                    print("❌ [Photo \(index+1)/\(photos.count)] Failed - \(error)")
                                }
                        case .empty:
                            EmptyView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Preloaded Photo Grid View (No Gap)


struct PlaceholderPhotoView: View {
    let size: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: size / 4))
                    .foregroundColor(.secondary.opacity(0.5))
            }
    }
}

// MARK: - Rating Section with Distance Badge

struct RatingWithDistanceView: View {
    let rating: Double?
    let distance: String?
    
    var body: some View {
        HStack(spacing: 4) {
            // Rating text
            Text(ratingText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            
            // Rating stars (filled based on rating)
            HStack(spacing: 2) {
                ForEach(0..<5) { index in
                    Image(systemName: index < filledStarsCount ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundColor(index < filledStarsCount ? .yellow : .gray)
                }
            }
            
            Spacer()
            
            // Distance badge (on right)
            if let distance = distance {
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
                .cornerRadius(12)
            }
        }
    }
    
    private var ratingText: String {
        if let rating = rating {
            return String(format: "%.1f", rating)
        }
        return "0"
    }
    
    private var filledStarsCount: Int {
        if let rating = rating {
            return Int(round(rating))
        }
        return 0
    }
}

// MARK: - Address View (small font, under rating) - NO ICON

struct AddressView: View {
    let address: String
    
    var body: some View {
        // ✅ REMOVED: mappin.circle.fill icon - just plain text now
        Text(address)
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(.gray)
            .lineLimit(2)
    }
}

// MARK: - Address Button (styled like Phone/Website buttons - copies address)

struct AddressButton: View {
    let address: String
    let placeName: String
    
    @State private var showCopied = false
    
    var body: some View {
        Button {
            copyAddress()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(Color(red: 1.0, green: 0.4, blue: 0.4), lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "mappin")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Address")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(address)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // ✅ Show checkmark when copied, otherwise copy icon
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(showCopied ? .green : .secondary)
            }
            .padding(.vertical, 8)
        }
    }
    
    private func copyAddress() {
        UIPasteboard.general.string = address
        
        // Show feedback
        withAnimation {
            showCopied = true
        }
        
        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopied = false
            }
        }
    }
}

// MARK: - Phone Button

struct PhoneButton: View {
    let phone: String
    
    var body: some View {
        Button(action: {
            if let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") {
                UIApplication.shared.open(url)
            }
        }) {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(Color(red: 1.0, green: 0.4, blue: 0.4), lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "phone")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Call")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(phone)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Website Button

struct WebsiteButton: View {
    let website: String
    
    var body: some View {
        Button(action: {
            if let url = URL(string: website) {
                UIApplication.shared.open(url)
            }
        }) {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(Color(red: 1.0, green: 0.4, blue: 0.4), lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "safari")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Website")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(website.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Directions Button

struct DirectionsButton: View {
    let placeName: String
    let address: String
    
    var body: some View {
        Button {
            openInMaps()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(Color(red: 1.0, green: 0.4, blue: 0.4), lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "map")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Directions")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Open in Maps")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
    }
    
    private func openInMaps() {
        let searchQuery = "\(placeName), \(address)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        let googleMapsURL = "comgooglemaps://?q=\(searchQuery)"
        if let url = URL(string: googleMapsURL), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            let webURL = "https://www.google.com/maps/search/?api=1&query=\(searchQuery)"
            if let url = URL(string: webURL) {
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - Visit Status View

struct VisitStatusView: View {
    let visitCount: Int
    let isLoading: Bool
    
    var body: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading visits...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        } else if visitCount == 0 {
            HStack(spacing: 6) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)
                Text("Be the first to visit!")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.orange)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                Text("\(visitCount) visit\(visitCount == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
    }
}

// MARK: - Empty Photo View

struct EmptyPhotoView: View {
    let height: CGFloat
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 50))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No visit photos yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .padding(.bottom, 20)
    }
}

// MARK: - Loading Photo View (Skeleton)

struct LoadingPhotoView: View {
    let height: CGFloat
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Skeleton rectangles
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(width: 120, height: 120)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.clear,
                                            Color.white.opacity(0.3),
                                            Color.clear
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .offset(x: isAnimating ? 200 : -200)
                        }
                        .clipped()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .padding(.bottom, 20)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}
