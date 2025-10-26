// Views/Discover/Shared/PlaceDetailComponents.swift
// ✅ EXACT ORIGINAL DESIGN: No categories, address under rating, distance badge on right

import SwiftUI

// MARK: - Photo Grid View

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
            // Rating stars
            Text(ratingText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
            
            HStack(spacing: 2) {
                ForEach(0..<5) { index in
                    Image(systemName: "star")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
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
}

// MARK: - Address View (small font, under rating)

struct AddressView: View {
    let address: String
    
    var body: some View {
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
