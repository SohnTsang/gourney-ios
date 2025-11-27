// Views/Profile/ProfileVisitCard.swift
// Hybrid visit card: photo or text-only with gradient
// Production-ready with memory optimization (3-col, 4:5 ratio)
// Navigation handled by parent view

import SwiftUI

struct ProfileVisitCard: View {
    let visit: ProfileVisit
    
    var body: some View {
        GeometryReader { geo in
            if visit.hasPhotos {
                photoCard(size: geo.size)
            } else {
                textOnlyCard(size: geo.size)
            }
        }
        .contentShape(Rectangle())
    }
    
    // MARK: - Photo Card (no comment)
    
    private func photoCard(size: CGSize) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Photo
            AsyncImage(url: URL(string: visit.photos.first ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                case .failure:
                    placeholderView(size: size)
                case .empty:
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .shimmer()
                @unknown default:
                    placeholderView(size: size)
                }
            }
            
            // Gradient overlay
            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Info overlay (place name + rating only)
            photoCardInfo
                .padding(8)
        }
        .clipShape(Rectangle())
    }
    
    // MARK: - Text-Only Card (with comment)
    
    private func textOnlyCard(size: CGSize) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Coral gradient background
            LinearGradient(
                colors: [
                    GourneyColors.coral.opacity(0.8),
                    GourneyColors.coralDark.opacity(0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Food icon
            VStack {
                Image(systemName: "fork.knife")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 16)
            
            // Info overlay (with comment)
            textCardInfo
                .padding(8)
        }
        .clipShape(Rectangle())
    }
    
    // MARK: - Photo Card Info (no comment)
    
    private var photoCardInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Place name
            Text(visit.place?.displayName ?? "Unknown")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            // Rating
            if let rating = visit.rating, rating > 0 {
                RatingStarsView(
                    rating: rating,
                    size: 8,
                    spacing: 1,
                    filledColor: .yellow,
                    emptyColor: .white.opacity(0.3)
                )
            }
        }
    }
    
    // MARK: - Text Card Info (with comment)
    
    private var textCardInfo: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Place name
            Text(visit.place?.displayName ?? "Unknown")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            // Rating
            if let rating = visit.rating, rating > 0 {
                RatingStarsView(
                    rating: rating,
                    size: 8,
                    spacing: 1,
                    filledColor: .yellow,
                    emptyColor: .white.opacity(0.3)
                )
            }
            
            // Comment preview (30 chars) - only for text cards
            if let comment = visit.comment, !comment.isEmpty {
                Text(truncatedComment(comment, maxLength: 30))
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
            }
        }
    }
    
    // MARK: - Placeholder
    
    private func placeholderView(size: CGSize) -> some View {
        ZStack {
            Color(.systemGray5)
            
            Image(systemName: "photo")
                .font(.system(size: 20))
                .foregroundColor(.gray)
        }
        .frame(width: size.width, height: size.height)
    }
    
    // MARK: - Helpers
    
    private func truncatedComment(_ comment: String, maxLength: Int) -> String {
        if comment.count <= maxLength {
            return comment
        }
        let index = comment.index(comment.startIndex, offsetBy: maxLength)
        return String(comment[..<index]) + "..."
    }
}

#Preview {
    let sampleVisit = ProfileVisit(
        id: "1",
        rating: 4,
        comment: "Amazing ramen! The broth was rich.",
        photoUrls: ["https://example.com/photo.jpg"],
        visibility: "public",
        visitedAt: "2024-01-15T12:00:00Z",
        createdAt: "2024-01-15T12:00:00Z",
        place: ProfilePlace(
            id: "p1",
            nameEn: "Ichiran",
            nameJa: "一蘭",
            nameZh: nil,
            city: "Tokyo",
            ward: "Shibuya",
            categories: ["ramen"],
            lat: 35.659,
            lng: 139.700
        )
    )
    
    LazyVGrid(
        columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
        spacing: 2
    ) {
        ProfileVisitCard(visit: sampleVisit)
            .aspectRatio(4/5, contentMode: .fill)
        
        ProfileVisitCard(visit: ProfileVisit(
            id: "2",
            rating: 5,
            comment: "Best sushi ever!",
            photoUrls: nil,
            visibility: "public",
            visitedAt: "2024-01-14T18:00:00Z",
            createdAt: "2024-01-14T18:00:00Z",
            place: ProfilePlace(
                id: "p2",
                nameEn: "Sukiyabashi Jiro",
                nameJa: nil,
                nameZh: nil,
                city: "Tokyo",
                ward: "Ginza",
                categories: ["sushi"],
                lat: 35.673,
                lng: 139.763
            )
        ))
        .aspectRatio(4/5, contentMode: .fill)
        
        ProfileVisitCard(visit: sampleVisit)
            .aspectRatio(4/5, contentMode: .fill)
    }
    .padding(2)
}
