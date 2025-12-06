// Views/Feed/FeedDetailView.swift
// Full-screen visit detail with comments
// Uses shared PhotoCarouselView for Instagram-style dynamic height
// Double-tap to like (won't unlike if already liked)
// FIX: Added notification listener for seamless visit updates
// FIX: Comment input now shows current user's avatar
// Avatar taps now navigate via NavigationCoordinator
// ✅ UPDATE: feedViewModel is now optional to support navigation from PlaceVisitsListView

import SwiftUI

struct FeedDetailView: View {
    let feedItem: FeedItem
    var feedViewModel: FeedViewModel?  // ✅ Made optional
    
    @StateObject private var viewModel: FeedDetailViewModel
    @State private var displayItem: FeedItem  // Mutable copy for UI updates
    @State private var currentPhotoIndex = 0
    @State private var showDeleteAlert = false
    @State private var commentToDelete: Comment?
    @State private var showHeader = true
    @State private var lastScrollY: CGFloat = 0
    @State private var showLikeAnimation = false
    @FocusState private var isCommentFieldFocused: Bool
    
    // Visit menu states
    @State private var showVisitMenu = false
    @State private var showDeleteVisitAlert = false
    @State private var showEditVisit = false
    @State private var isDeletingVisit = false
    @State private var showPlaceDetail = false
    @State private var showAddVisitFromPlace = false
    @State private var pendingAddVisit = false
    
    // Local like state (since ProfileVisit doesn't track likes)
    @State private var localIsLiked: Bool = false
    @State private var localLikeCount: Int = 0
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var isOwnVisit: Bool {
        displayItem.user.id == AuthManager.shared.currentUser?.id
    }
    
    init(feedItem: FeedItem, feedViewModel: FeedViewModel? = nil) {  // ✅ Default to nil
        self.feedItem = feedItem
        self.feedViewModel = feedViewModel
        self._displayItem = State(initialValue: feedItem)
        self._viewModel = StateObject(wrappedValue: FeedDetailViewModel(visitId: feedItem.id))
        // Initialize local like state from feedItem
        self._localIsLiked = State(initialValue: feedItem.isLiked)
        self._localLikeCount = State(initialValue: feedItem.likeCount)
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Main content
            VStack(spacing: 0) {
                // Spacer for header when visible
                Color.clear
                    .frame(height: showHeader ? 44 : 0)
                    .animation(.easeInOut(duration: 0.2), value: showHeader)
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Photo carousel with double-tap to like
                        if !displayItem.photos.isEmpty {
                            photoSection
                        }
                        
                        // Visit content
                        visitContent
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                        
                        // Action bar
                        actionBar
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        
                        Divider()
                            .padding(.horizontal, 16)
                        
                        // Comments section
                        commentsSection
                    }
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .preference(
                                    key: ScrollOffsetKey.self,
                                    value: geometry.frame(in: .global).minY
                                )
                        }
                    )
                }
                .onPreferenceChange(ScrollOffsetKey.self) { currentY in
                    handleScroll(currentY: currentY)
                }
                .scrollDismissesKeyboard(.interactively)
                
                // Comment input bar (fixed at bottom)
                commentInputBar
            }
            
            // Fixed header overlay
            if showHeader {
                DetailTopBar(
                    title: "Visit",
                    rightButtonIcon: isOwnVisit ? "ellipsis" : nil,
                    showRightButton: isOwnVisit,
                    usePrimaryColor: true,
                    onBack: { dismiss() },
                    onRightAction: { showVisitMenu = true }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        .navigationBarHidden(true)
        .onAppear {
            viewModel.loadComments()
            viewModel.onCommentCountChanged = { delta in
                feedViewModel?.updateCommentCount(for: displayItem.id, delta: delta)  // ✅ Optional chaining
            }
            // Fetch actual like status (ProfileVisit doesn't have this data)
            fetchLikeStatus()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        // Listen for visit updates from notification
        .onReceive(NotificationCenter.default.publisher(for: .visitDidUpdate)) { notification in
            handleVisitUpdate(notification)
        }
        .navigationDestination(isPresented: $showEditVisit) {
            EditVisitView(feedItem: displayItem) { updatedItem in
                // Update local display
                displayItem = updatedItem
                // Update in feed list
                feedViewModel?.updateItem(updatedItem)  // ✅ Optional chaining
                // Note: ProfileView update now handled via NotificationCenter
            }
        }
        .sheet(isPresented: $showVisitMenu) {
            VisitActionSheet(
                onEdit: {
                    showEditVisit = true
                },
                onDelete: {
                    showDeleteVisitAlert = true
                }
            )
        }
        .sheet(isPresented: $showPlaceDetail) {
            PlaceDetailSheet(
                placeId: displayItem.place.id,
                displayName: displayItem.place.displayName,
                lat: 0, // Will be fetched by PlaceDetailSheet
                lng: 0,
                formattedAddress: nil,
                phoneNumber: nil,
                website: nil,
                photoUrls: nil,
                googlePlaceId: nil,
                primaryButtonTitle: "Add Visit",
                primaryButtonAction: {
                    // Set flag and dismiss sheet
                    pendingAddVisit = true
                    showPlaceDetail = false
                },
                onDismiss: {
                    showPlaceDetail = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .onChange(of: showPlaceDetail) { _, newValue in
            // When sheet dismisses and we have pending AddVisit
            if !newValue && pendingAddVisit {
                pendingAddVisit = false
                showAddVisitFromPlace = true
            }
        }
        .fullScreenCover(isPresented: $showAddVisitFromPlace) {
            AddVisitView(
                prefilledPlace: PlaceSearchResult(
                    source: .google,
                    googlePlaceId: nil,
                    applePlaceId: nil,
                    nameEn: displayItem.place.nameEn,
                    nameJa: displayItem.place.nameJa,
                    nameZh: displayItem.place.nameZh,
                    lat: 0,
                    lng: 0,
                    formattedAddress: nil,
                    categories: displayItem.place.categories,
                    photoUrls: nil,
                    existsInDb: true,
                    dbPlaceId: displayItem.place.id,
                    appleFullData: nil
                ),
                showBackButton: true,
                onVisitPosted: { _ in
                    showAddVisitFromPlace = false
                }
            )
        }
        .customDeleteAlert(
            isPresented: $showDeleteVisitAlert,
            title: "Delete Visit",
            message: "Are you sure you want to delete this visit? This cannot be undone.",
            confirmTitle: "Delete",
            onConfirm: {
                deleteVisit()
            }
        )
        .customDeleteAlert(
            isPresented: $showDeleteAlert,
            title: "Delete Comment",
            message: "Are you sure you want to delete this comment? This cannot be undone.",
            confirmTitle: "Delete",
            onConfirm: {
                if let comment = commentToDelete {
                    viewModel.deleteComment(comment)
                }
                commentToDelete = nil
            }
        )
        .loadingOverlay(isShowing: isDeletingVisit, message: "Deleting...")
    }
    
    // MARK: - Photo Section with Double-Tap to Like
    
    private var photoSection: some View {
        ZStack {
            PhotoCarouselView(
                photos: displayItem.photos,
                currentIndex: $currentPhotoIndex,
                onPhotoTap: nil  // Remove single-tap preview
            )
            
            // Double-tap like heart animation
            if showLikeAnimation {
                Image(systemName: "heart.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            handleDoubleTapLike()
        }
        // Single tap does nothing - no image preview
    }
    
    // MARK: - Double Tap Like Handler
    
    private func handleDoubleTapLike() {
        // Only like if not already liked (Instagram behavior)
        if !currentIsLiked {
            toggleLike()
        }
        
        // Always show animation on double-tap
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showLikeAnimation = true
        }
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Hide animation after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.3)) {
                showLikeAnimation = false
            }
        }
    }
    
    // MARK: - Handle Visit Update Notification
    
    private func handleVisitUpdate(_ notification: Notification) {
        guard let visitId = notification.userInfo?[VisitNotificationKeys.visitId] as? String,
              visitId == displayItem.id,
              let updatedData = notification.userInfo?[VisitNotificationKeys.updatedVisit] as? VisitUpdateData else {
            return
        }
        
        print("📥 [FeedDetailView] Received update for current visit: \(visitId)")
        
        // Update displayItem with the new data, preserving user/place/engagement data
        displayItem = FeedItem(
            id: updatedData.id,
            rating: updatedData.rating,
            comment: updatedData.comment,
            photoUrls: updatedData.photoUrls,
            visibility: updatedData.visibility,
            createdAt: updatedData.createdAt,
            visitedAt: updatedData.visitedAt,
            likeCount: displayItem.likeCount,
            commentCount: displayItem.commentCount,
            isLiked: displayItem.isLiked,
            isFollowing: displayItem.isFollowing,
            user: displayItem.user,
            place: displayItem.place
        )
        
        print("✅ [FeedDetailView] Updated displayItem")
    }
    
    // MARK: - Scroll Handling
    
    private func handleScroll(currentY: CGFloat) {
        let delta = currentY - lastScrollY
        let threshold: CGFloat = 8
        
        if abs(delta) > threshold {
            withAnimation(.easeInOut(duration: 0.2)) {
                if delta < 0 {
                    // Scrolling down - hide header
                    showHeader = false
                } else {
                    // Scrolling up - show header
                    showHeader = true
                }
            }
            lastScrollY = currentY
        }
    }
    
    // MARK: - Delete Visit
    
    private func deleteVisit() {
        isDeletingVisit = true
        
        Task { @MainActor in
            do {
                let path = "/functions/v1/visits-delete?visit_id=\(displayItem.id)"
                print("🗑️ [Visit] Deleting: \(displayItem.id)")
                
                let _: EmptyResponse = try await SupabaseClient.shared.delete(
                    path: path,
                    requiresAuth: true
                )
                
                print("✅ [Visit] Deleted successfully")
                
                // Broadcast delete notification to all listening views
                VisitUpdateService.shared.notifyVisitDeleted(visitId: displayItem.id)
                
                // Remove from feed (if available)
                feedViewModel?.removeVisit(id: displayItem.id)  // ✅ Optional chaining
                
                // Success haptic
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
                // Dismiss view
                dismiss()
                
            } catch {
                print("❌ [Visit] Delete error: \(error)")
                isDeletingVisit = false
                
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
        }
    }
    
    // MARK: - Visit Content
    
    private var visitContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // User header - avatar and username now tappable via NavigationCoordinator
            HStack(spacing: 10) {
                AvatarView(url: displayItem.user.avatarUrl, size: 40, userId: displayItem.user.id)
                
                VStack(alignment: .leading, spacing: 2) {
                    TappableUsername(
                        username: displayItem.user.displayNameOrHandle,
                        userId: displayItem.user.id,
                        font: .system(size: 15, weight: .semibold),
                        color: .primary
                    )
                    
                    Text(timeAgoString(from: displayItem.createdAt))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Place info - tappable
            Button {
                showPlaceDetail = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayItem.place.displayName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 8) {
                            // Rating number + stars
                            HStack(spacing: 4) {
                                Text(String(format: "%.1f", Double(displayItem.rating ?? 0)))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                RatingStarsView(rating: displayItem.rating ?? 0, size: 14)
                            }
                            
                            if !displayItem.place.locationString.isEmpty {
                                Text(displayItem.place.locationString)
                                    .font(.system(size: 13))
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
            
            // Comment text
            if let comment = displayItem.comment, !comment.isEmpty {
                Text(comment)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    // MARK: - Action Bar
    
    private var actionBar: some View {
        HStack(spacing: 4) {
            FeedActionButton(
                icon: "heart",
                filledIcon: "heart.fill",
                count: currentLikeCount > 0 ? currentLikeCount : nil,
                isActive: currentIsLiked,
                action: {
                    toggleLike()
                }
            )
            
            HStack(spacing: 4) {
                Image(systemName: "bubble.right")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                
                if currentCommentCount > 0 {
                    Text("\(currentCommentCount)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            
            Spacer()
            
            FeedActionButton(
                icon: "bookmark",
                filledIcon: "bookmark.fill",
                action: { }
            )
            
            FeedActionButton(
                icon: "square.and.arrow.up",
                action: { shareVisit() }
            )
        }
    }
    
    // MARK: - Toggle Like (uses LikeService for consistency)
    
    private func toggleLike() {
        LikeService.shared.toggleLike(
            visitId: displayItem.id,
            currentlyLiked: localIsLiked,
            currentCount: localLikeCount,
            onOptimisticUpdate: { [self] newLiked, newCount in
                localIsLiked = newLiked
                localLikeCount = newCount
                print("💫 [FeedDetail] Optimistic: liked=\(newLiked), count=\(newCount)")
            },
            onServerResponse: { [self] serverLiked, serverCount in
                localIsLiked = serverLiked
                localLikeCount = serverCount
                // Update FeedViewModel if available
                feedViewModel?.updateLikeState(visitId: displayItem.id, isLiked: serverLiked, likeCount: serverCount)
                print("✅ [FeedDetail] Server synced: liked=\(serverLiked), count=\(serverCount)")
            },
            onError: { error in
                print("❌ [FeedDetail] Like error: \(error.localizedDescription)")
            }
        )
    }
    
    private var currentIsLiked: Bool {
        localIsLiked
    }
    
    private var currentLikeCount: Int {
        localLikeCount
    }
    
    private var currentCommentCount: Int {
        feedViewModel?.items.first(where: { $0.id == displayItem.id })?.commentCount ?? displayItem.commentCount  // ✅ Optional chaining
    }
    
    // MARK: - Fetch Like Status
    
    private func fetchLikeStatus() {
        // If we already have valid data from FeedViewModel, use that
        if let feedItem = feedViewModel?.getItem(id: displayItem.id) {  // ✅ Optional chaining
            localIsLiked = feedItem.isLiked
            localLikeCount = feedItem.likeCount
            print("📋 [FeedDetail] Using FeedViewModel state: liked=\(localIsLiked), count=\(localLikeCount)")
            return
        }
        
        // Otherwise fetch from API (for visits opened from ProfileView or PlaceVisitsListView)
        Task {
            do {
                let path = "/functions/v1/likes-list?visit_id=\(displayItem.id)&limit=1"
                print("📡 [FeedDetail] Fetching like status...")
                
                struct LikesListResponse: Codable {
                    let visitId: String
                    let likes: [LikeUser]
                    let likeCount: Int
                    let hasLiked: Bool
                    let nextCursor: String?
                    
                    struct LikeUser: Codable {
                        let userId: String
                    }
                }
                
                let response: LikesListResponse = try await SupabaseClient.shared.get(
                    path: path,
                    requiresAuth: true
                )
                
                localIsLiked = response.hasLiked
                localLikeCount = response.likeCount
                print("✅ [FeedDetail] Like status: liked=\(localIsLiked), count=\(localLikeCount)")
                
            } catch {
                print("⚠️ [FeedDetail] Failed to fetch like status: \(error.localizedDescription)")
                // Keep initial values from feedItem
            }
        }
    }
    
    // MARK: - Comments Section
    
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Comments")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                
                if currentCommentCount > 0 {
                    Text("(\(currentCommentCount))")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            if viewModel.isLoadingComments && viewModel.comments.isEmpty {
                VStack(spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        CommentSkeletonView()
                    }
                }
                .padding(.horizontal, 16)
            } else if viewModel.comments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.4))
                    
                    Text("Be the first to comment!")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.comments) { comment in
                        CommentRowView(
                            comment: comment,
                            onLikeTap: { viewModel.toggleCommentLike(comment) },
                            onEditTap: {
                                viewModel.startEditing(comment)
                                isCommentFieldFocused = true
                            },
                            onDeleteTap: {
                                commentToDelete = comment
                                showDeleteAlert = true
                            }
                        )
                        .onAppear {
                            viewModel.loadMoreIfNeeded(currentComment: comment)
                        }
                        
                        if comment.id != viewModel.comments.last?.id {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.horizontal, 16)
                
                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView().tint(GourneyColors.coral)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
            }
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Comment Input Bar
    
    private var commentInputBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            if viewModel.isEditing {
                HStack {
                    Text("Editing comment")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        viewModel.cancelEditing()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(GourneyColors.coral)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            
            HStack(alignment: .center, spacing: 12) {
                // ✅ FIX: Use current user's avatar instead of nil
                AvatarView(url: AuthManager.shared.currentUser?.avatarUrl, size: 32)
                
                VStack(alignment: .trailing, spacing: 4) {
                    TextField("Add a comment...", text: $viewModel.commentText, axis: .vertical)
                        .font(.system(size: 15))
                        .lineLimit(1...5)
                        .focused($isCommentFieldFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    if viewModel.isNearCharacterLimit {
                        Text("\(viewModel.characterCount)/1500")
                            .font(.system(size: 11))
                            .foregroundColor(viewModel.characterCount > 1500 ? .red : .secondary)
                    }
                }
                
                Button {
                    viewModel.postComment()
                    isCommentFieldFocused = false
                } label: {
                    if viewModel.isPostingComment {
                        ProgressView()
                            .tint(GourneyColors.coral)
                            .frame(width: 40, height: 32)
                    } else {
                        Text(viewModel.isEditing ? "Save" : "Post")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(viewModel.canPostComment ? GourneyColors.coral : .secondary)
                            .frame(height: 32)
                    }
                }
                .disabled(!viewModel.canPostComment || viewModel.isPostingComment)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(colorScheme == .dark ? Color(.systemGray6).opacity(0.5) : Color.white)
    }
    
    private func shareVisit() {
        let text = "\(displayItem.user.displayNameOrHandle) visited \(displayItem.place.displayName)"
        let url = URL(string: "https://gourney.app/visit/\(displayItem.id)")
        
        var items: [Any] = [text]
        if let url = url { items.append(url) }
        
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Scroll Offset Preference Key

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Comment Row View

struct CommentRowView: View {
    let comment: Comment
    var onLikeTap: (() -> Void)?
    var onEditTap: (() -> Void)?
    var onDeleteTap: (() -> Void)?
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar with userId for automatic navigation
            AvatarView(url: comment.userAvatarUrl, size: 32, userId: comment.userId)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Username also tappable
                    TappableUsername(
                        username: comment.displayName,
                        userId: comment.userId,
                        font: .system(size: 14, weight: .semibold),
                        color: .primary
                    )
                    
                    Text(comment.timeAgo)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    if comment.isEdited {
                        Text("(edited)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                Text(comment.commentText)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                if !comment.isOwnComment {
                    Button {
                        onLikeTap?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: comment.isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 14))
                                .foregroundColor(comment.isLiked ? GourneyColors.coral : .secondary)
                            
                            if comment.likeCount > 0 {
                                Text("\(comment.likeCount)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                if comment.isOwnComment {
                    Menu {
                        Button { onEditTap?() } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) { onDeleteTap?() } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                    }
                }
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Comment Skeleton View

struct CommentSkeletonView: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 120, height: 12)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(height: 14)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 180, height: 14)
            }
            
            Spacer()
        }
        .padding(.vertical, 12)
        .overlay {
            LinearGradient(
                colors: [Color.clear, Color.white.opacity(0.3), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .offset(x: isAnimating ? 300 : -300)
        }
        .clipped()
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Fullscreen Photo Viewer (Dots Only)

struct FullscreenPhotoViewer: View {
    let photos: [String]
    @Binding var currentIndex: Int
    
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Photo pages - NO built-in indicator
            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, urlString in
                    photoPage(urlString: urlString)
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            
            // Close button - top right
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 16)
                }
                Spacer()
            }
            
            // Custom dots only - bottom center
            if photos.count > 1 {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(0..<photos.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentIndex ? Color.white : Color.white.opacity(0.4))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .gesture(
            scale <= 1.0 ?
            DragGesture()
                .onChanged { value in
                    if abs(value.translation.height) > abs(value.translation.width) {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    if abs(value.translation.height) > 100 {
                        dismiss()
                    } else {
                        withAnimation(.spring()) { dragOffset = .zero }
                    }
                }
            : nil
        )
        .offset(y: scale <= 1.0 ? dragOffset.height : 0)
        .animation(.interactiveSpring(), value: dragOffset)
    }
    
    private func photoPage(urlString: String) -> some View {
        GeometryReader { geometry in
            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in scale = max(1.0, value) }
                                .onEnded { _ in
                                    withAnimation(.spring()) {
                                        if scale < 1.0 { scale = 1.0 }
                                        if scale > 4.0 { scale = 4.0 }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            scale > 1.0 ?
                            DragGesture()
                                .onChanged { value in dragOffset = value.translation }
                                .onEnded { _ in
                                    offset = CGSize(
                                        width: offset.width + dragOffset.width,
                                        height: offset.height + dragOffset.height
                                    )
                                    dragOffset = .zero
                                }
                            : nil
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                } else {
                                    scale = 2.0
                                }
                            }
                        }
                case .failure:
                    VStack {
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("Failed to load")
                            .foregroundColor(.gray)
                    }
                case .empty:
                    ProgressView().tint(.white)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

// MARK: - Visit Action Sheet (Same design as FeedMenuSheet)

struct VisitActionSheet: View {
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.systemGray3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 20)
            
            VStack(spacing: 0) {
                menuRow(icon: "pencil.circle", title: "Edit Visit") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onEdit() }
                }
                
                Divider().padding(.leading, 56)
                
                menuRow(icon: "trash.circle", title: "Delete Visit", isDestructive: true) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDelete() }
                }
            }
            
            Spacer()
        }
        .presentationDetents([.height(180)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
    }
    
    private func menuRow(icon: String, title: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundColor(isDestructive ? .red : .primary)
                    .frame(width: 32)
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isDestructive ? .red : .primary)
                
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

#Preview {
    NavigationStack {
        FeedDetailView(
            feedItem: .preview
        )
    }
}
