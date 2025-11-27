// Views/Feed/FeedCardView.swift
// Elegant feed card using shared PhotoCarouselView
// Instagram-style dynamic photo height

import SwiftUI

struct FeedCardView: View {
    let item: FeedItem
    var onLikeTap: (() -> Void)?
    var onCommentTap: (() -> Void)?
    var onSaveTap: (() -> Void)?
    var onShareTap: (() -> Void)?
    var onUserTap: (() -> Void)?
    var onPlaceTap: (() -> Void)?
    
    @State private var currentPhotoIndex = 0
    @Binding var showMenuForId: String?
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isMenuShown: Bool {
        showMenuForId == item.id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !item.photos.isEmpty {
                photoSection
            }
            contentSection
        }
        .background(colorScheme == .dark ? Color(.systemGray6).opacity(0.5) : Color.white)
    }
    
    // MARK: - Photo Section
    
    private var photoSection: some View {
        ZStack {
            PhotoCarouselView(
                photos: item.photos,
                currentIndex: $currentPhotoIndex
            )
            
            // Gradient overlay
            LinearGradient(
                colors: [.black.opacity(0.4), .clear, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            
            // User info - top left
            VStack {
                HStack {
                    Button { onUserTap?() } label: {
                        HStack(spacing: 10) {
                            AvatarView(url: item.user.avatarUrl, size: 36)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.user.displayNameOrHandle)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Text(timeAgoString(from: item.createdAt))
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Menu button - top right
                    menuButton(onPhoto: true)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                
                Spacer()
            }
        }
    }
    
    // MARK: - Menu Button
    
    private func menuButton(onPhoto: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                showMenuForId = isMenuShown ? nil : item.id
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(onPhoto ? .white : .secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Content Section
    
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if item.photos.isEmpty {
                noPhotoHeader
            }
            placeRow
            
            if let comment = item.comment, !comment.isEmpty {
                Text(comment)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            actionBar
        }
        .padding(16)
    }
    
    // MARK: - No Photo Header
    
    private var noPhotoHeader: some View {
        HStack(spacing: 12) {
            Button { onUserTap?() } label: {
                AvatarView(url: item.user.avatarUrl, size: 40)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.user.displayNameOrHandle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(timeAgoString(from: item.createdAt))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            menuButton(onPhoto: false)
        }
    }
    
    // MARK: - Place Row
    
    private var placeRow: some View {
        Button { onPlaceTap?() } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.place.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        if let rating = item.rating {
                            RatingStarsView(rating: rating, size: 12)
                        }
                        
                        if !item.place.locationString.isEmpty {
                            Text(item.place.locationString)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Action Bar
    
    private var actionBar: some View {
        HStack(spacing: 4) {
            FeedActionButton(
                icon: "heart",
                filledIcon: "heart.fill",
                count: item.likeCount > 0 ? item.likeCount : nil,
                isActive: item.isLiked,
                action: { onLikeTap?() }
            )
            
            FeedActionButton(
                icon: "bubble.right",
                count: item.commentCount > 0 ? item.commentCount : nil,
                action: { onCommentTap?() }
            )
            
            Spacer()
            
            FeedActionButton(
                icon: "bookmark",
                filledIcon: "bookmark.fill",
                action: { onSaveTap?() }
            )
            
            FeedActionButton(
                icon: "square.and.arrow.up",
                action: { onShareTap?() }
            )
        }
    }
}

// MARK: - Feed Menu Bottom Sheet

struct FeedMenuSheet: View {
    let item: FeedItem
    var onViewProfile: (() -> Void)?
    var onViewPlace: (() -> Void)?
    var onSaveToList: (() -> Void)?
    var onReport: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.systemGray3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 20)
            
            VStack(spacing: 0) {
                menuRow(icon: "person.circle", title: "View Profile", subtitle: "@\(item.user.handle)") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onViewProfile?() }
                }
                
                Divider().padding(.leading, 56)
                
                menuRow(icon: "mappin.circle", title: "View Place", subtitle: item.place.displayName) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onViewPlace?() }
                }
                
                Divider().padding(.leading, 56)
                
                menuRow(icon: "bookmark.circle", title: "Save to List") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onSaveToList?() }
                }
                
                Divider().padding(.leading, 56)
                
                menuRow(icon: "flag.circle", title: "Report", isDestructive: true) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onReport?() }
                }
            }
            
            Spacer()
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
    }
    
    private func menuRow(icon: String, title: String, subtitle: String? = nil, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundColor(isDestructive ? .red : .primary)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isDestructive ? .red : .primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(.systemGray3))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Skeleton Loading

struct FeedCardSkeleton: View {
    @State private var isAnimating = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(height: UIScreen.main.bounds.width)
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 180, height: 16)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 120, height: 12)
                }
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 14)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 200, height: 14)
            }
            .padding(16)
        }
        .background(colorScheme == .dark ? Color(.systemGray6).opacity(0.5) : Color.white)
        .overlay {
            LinearGradient(
                colors: [Color.clear, Color.white.opacity(0.3), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .offset(x: isAnimating ? 400 : -400)
        }
        .clipped()
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Preview Data

extension FeedItem {
    static var preview: FeedItem {
        FeedItem(
            id: "preview-1",
            rating: 4,
            comment: "Amazing ramen! The broth was incredibly rich and flavorful.",
            photoUrls: [
                "https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=800",
                "https://images.unsplash.com/photo-1617196034183-421b4917c92d?w=800"
            ],
            visibility: "public",
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600)),
            visitedAt: "2025-01-15",
            likeCount: 24,
            commentCount: 5,
            isLiked: false,
            isFollowing: true,
            user: FeedUser(id: "user-1", handle: "foodlover", displayName: "Sarah Chen", avatarUrl: nil),
            place: FeedPlace(id: "place-1", nameEn: "Ichiran Ramen Shibuya", nameJa: "一蘭 渋谷店", nameZh: "一蘭拉麵 澀谷店", city: "Tokyo", ward: "Shibuya", country: "Japan", categories: ["ramen"])
        )
    }
    
    static var previewNoPhoto: FeedItem {
        FeedItem(
            id: "preview-2",
            rating: 5,
            comment: "Best sushi in town! Fresh fish and excellent service.",
            photoUrls: nil,
            visibility: "public",
            createdAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7200)),
            visitedAt: "2025-01-14",
            likeCount: 10,
            commentCount: 2,
            isLiked: true,
            isFollowing: false,
            user: FeedUser(id: "user-2", handle: "sushifan", displayName: "Mike Tanaka", avatarUrl: nil),
            place: FeedPlace(id: "place-2", nameEn: "Sushi Dai", nameJa: "寿司大", nameZh: "壽司大", city: "Tokyo", ward: "Tsukiji", country: "Japan", categories: ["sushi"])
        )
    }
}

#Preview("Feed Card") {
    ScrollView {
        FeedCardView(item: .preview, showMenuForId: .constant(nil))
        FeedCardView(item: .previewNoPhoto, showMenuForId: .constant(nil))
    }
    .background(Color(.systemGroupedBackground))
}
