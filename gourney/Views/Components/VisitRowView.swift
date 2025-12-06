// Views/Shared/VisitRowView.swift
// Reusable visit row component used in PlaceVisitsListView and potentially other views
// Supports: avatar tap → profile, row tap → detail, like toggle, relative time

import SwiftUI
import Combine

// MARK: - Visit Row Data (unified model for display)

struct VisitRowData: Identifiable {
    let id: String
    let visitorId: String
    let visitorHandle: String
    let visitorDisplayName: String?
    let visitorAvatarUrl: String?
    let rating: Int?
    let comment: String?
    let photoUrls: [String]
    let visitedAt: String
    var likeCount: Int
    var isLiked: Bool
    
    // Place info (for creating FeedItem if needed)
    let placeId: String?
    let placeName: String?
    let placeNameEn: String?
    let placeNameJa: String?
    let placeNameZh: String?
    let placeCity: String?
    let placeWard: String?
    let placeCategories: [String]?
    
    var displayName: String {
        visitorDisplayName ?? visitorHandle
    }
    
    // Create from EdgeFunctionVisit
    init(from visit: EdgeFunctionVisit, placeId: String? = nil, placeName: String? = nil) {
        self.id = visit.id
        self.visitorId = visit.userId
        self.visitorHandle = visit.userHandle
        self.visitorDisplayName = visit.userDisplayName
        self.visitorAvatarUrl = visit.userAvatarUrl
        self.rating = visit.rating
        self.comment = visit.comment
        self.photoUrls = visit.photoUrls
        self.visitedAt = visit.visitedAt
        self.likeCount = visit.likesCount ?? 0
        self.isLiked = false  // Will be fetched if needed
        self.placeId = placeId
        self.placeName = placeName
        self.placeNameEn = placeName
        self.placeNameJa = nil
        self.placeNameZh = nil
        self.placeCity = nil
        self.placeWard = nil
        self.placeCategories = nil
    }
    
    // Convert to FeedItem for FeedDetailView
    func toFeedItem() -> FeedItem {
        FeedItem(
            id: id,
            rating: rating,
            comment: comment,
            photoUrls: photoUrls.isEmpty ? nil : photoUrls,
            visibility: "public",
            createdAt: visitedAt,
            visitedAt: visitedAt,
            likeCount: likeCount,
            commentCount: 0,
            isLiked: isLiked,
            isFollowing: false,
            user: FeedUser(
                id: visitorId,
                handle: visitorHandle,
                displayName: visitorDisplayName,
                avatarUrl: visitorAvatarUrl
            ),
            place: FeedPlace(
                id: placeId ?? "",
                nameEn: placeNameEn,
                nameJa: placeNameJa,
                nameZh: placeNameZh,
                city: placeCity,
                ward: placeWard,
                country: nil,
                categories: placeCategories
            )
        )
    }
}

// MARK: - Visit Row View

struct VisitRowView: View {
    @Binding var visit: VisitRowData
    let onAvatarTap: () -> Void
    let onRowTap: () -> Void
    
    @State private var isLikeAnimating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // User info row
            HStack(spacing: 10) {
                // Avatar - high priority tap for profile
                avatarView
                    .highPriorityGesture(TapGesture().onEnded { onAvatarTap() })
                
                // Name & handle - high priority tap for profile
                VStack(alignment: .leading, spacing: 2) {
                    Text(visit.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("@\(visit.visitorHandle)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .highPriorityGesture(TapGesture().onEnded { onAvatarTap() })
                
                Spacer()
                
                // Rating stars
                if let rating = visit.rating, rating > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<5) { index in
                            Image(systemName: index < rating ? "star.fill" : "star")
                                .font(.system(size: 10))
                                .foregroundColor(index < rating ? .yellow : .gray)
                        }
                    }
                }
            }
            
            // Comment
            if let comment = visit.comment, !comment.isEmpty {
                Text(comment)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Photos
            if !visit.photoUrls.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(visit.photoUrls, id: \.self) { photoUrl in
                            AsyncImage(url: URL(string: photoUrl)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                case .failure:
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray5))
                                        .frame(width: 100, height: 100)
                                case .empty:
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray5))
                                        .frame(width: 100, height: 100)
                                        .overlay { ProgressView() }
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                    }
                }
            }
            
            // Bottom row: Time and Like button
            HStack {
                // Relative time
                Text(RelativeTimeFormatter.format(from: visit.visitedAt))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Like button - high priority tap
                HStack(spacing: 4) {
                    Image(systemName: visit.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 18))
                        .foregroundColor(visit.isLiked ? GourneyColors.coral : .secondary)
                        .scaleEffect(isLikeAnimating ? 1.2 : 1.0)
                    
                    if visit.likeCount > 0 {
                        Text("\(visit.likeCount)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded { toggleLike() })
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            // Row tap - goes to FeedDetailView
            onRowTap()
        }
        .onReceive(NotificationCenter.default.publisher(for: .visitLikeDidChange)) { notification in
            handleLikeNotification(notification)
        }
    }
    
    // MARK: - Avatar View
    
    private var avatarView: some View {
        Group {
            if let avatarUrl = visit.visitorAvatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    case .failure, .empty:
                        placeholderAvatar
                    @unknown default:
                        placeholderAvatar
                    }
                }
            } else {
                placeholderAvatar
            }
        }
    }
    
    private var placeholderAvatar: some View {
        Circle()
            .fill(GourneyColors.coralLight)
            .frame(width: 40, height: 40)
            .overlay(
                Text(String(visit.visitorHandle.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(GourneyColors.coral)
            )
    }
    
    // MARK: - Like Toggle (uses LikeService, animation matches FeedActionButton)
    
    private func toggleLike() {
        // Trigger spring animation (matches FeedActionButton)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isLikeAnimating = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isLikeAnimating = false
            }
        }
        
        LikeService.shared.toggleLike(
            visitId: visit.id,
            currentlyLiked: visit.isLiked,
            currentCount: visit.likeCount,
            onOptimisticUpdate: { newLiked, newCount in
                visit.isLiked = newLiked
                visit.likeCount = newCount
            },
            onServerResponse: { serverLiked, serverCount in
                visit.isLiked = serverLiked
                visit.likeCount = serverCount
            },
            onError: { error in
                print("❌ [VisitRow] Like error: \(error)")
            }
        )
    }
    
    private func handleLikeNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let visitId = userInfo[LikeNotificationKeys.visitId] as? String,
              visitId == visit.id,
              let isLiked = userInfo[LikeNotificationKeys.isLiked] as? Bool,
              let likeCount = userInfo[LikeNotificationKeys.likeCount] as? Int else {
            return
        }
        
        visit.isLiked = isLiked
        visit.likeCount = likeCount
    }
}
