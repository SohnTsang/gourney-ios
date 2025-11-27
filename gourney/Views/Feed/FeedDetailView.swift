// Views/Feed/FeedDetailView.swift
// Full-screen visit detail with comments
// Uses shared PhotoCarouselView for Instagram-style dynamic height

import SwiftUI

struct FeedDetailView: View {
    let feedItem: FeedItem
    @ObservedObject var feedViewModel: FeedViewModel
    
    @StateObject private var viewModel: FeedDetailViewModel
    @State private var currentPhotoIndex = 0
    @State private var showFullscreenPhoto = false
    @State private var showDeleteAlert = false
    @State private var commentToDelete: Comment?
    @State private var showHeader = true
    @State private var lastScrollY: CGFloat = 0
    @FocusState private var isCommentFieldFocused: Bool
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    init(feedItem: FeedItem, feedViewModel: FeedViewModel) {
        self.feedItem = feedItem
        self.feedViewModel = feedViewModel
        self._viewModel = StateObject(wrappedValue: FeedDetailViewModel(visitId: feedItem.id))
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
                        // Photo carousel
                        if !feedItem.photos.isEmpty {
                            PhotoCarouselView(
                                photos: feedItem.photos,
                                currentIndex: $currentPhotoIndex,
                                onPhotoTap: {
                                    showFullscreenPhoto = true
                                }
                            )
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
                customHeaderBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        .navigationBarHidden(true)
        .onAppear {
            viewModel.loadComments()
            viewModel.onCommentCountChanged = { delta in
                feedViewModel.updateCommentCount(for: feedItem.id, delta: delta)
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .fullScreenCover(isPresented: $showFullscreenPhoto) {
            FullscreenPhotoViewer(
                photos: feedItem.photos,
                currentIndex: $currentPhotoIndex
            )
        }
        .alert("Delete Comment", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {
                commentToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let comment = commentToDelete {
                    viewModel.deleteComment(comment)
                }
                commentToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this comment? This cannot be undone.")
        }
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
    
    // MARK: - Custom Header Bar
    
    private var customHeaderBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            
            Spacer()
            
            Text("Visit")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
            
            Spacer()
            
            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
    
    // MARK: - Visit Content
    
    private var visitContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // User header
            HStack(spacing: 10) {
                AvatarView(url: feedItem.user.avatarUrl, size: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(feedItem.user.displayNameOrHandle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    Text(timeAgoString(from: feedItem.createdAt))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Place info
            VStack(alignment: .leading, spacing: 4) {
                Text(feedItem.place.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    if let rating = feedItem.rating {
                        RatingStarsView(rating: rating, size: 14)
                    }
                    
                    if !feedItem.place.locationString.isEmpty {
                        Text(feedItem.place.locationString)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            // Comment text
            if let comment = feedItem.comment, !comment.isEmpty {
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
                    feedViewModel.toggleLike(for: feedItem)
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
    
    private var currentIsLiked: Bool {
        feedViewModel.items.first(where: { $0.id == feedItem.id })?.isLiked ?? feedItem.isLiked
    }
    
    private var currentLikeCount: Int {
        feedViewModel.items.first(where: { $0.id == feedItem.id })?.likeCount ?? feedItem.likeCount
    }
    
    private var currentCommentCount: Int {
        feedViewModel.items.first(where: { $0.id == feedItem.id })?.commentCount ?? feedItem.commentCount
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
                AvatarView(url: nil, size: 32)
                
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
        let text = "\(feedItem.user.displayNameOrHandle) visited \(feedItem.place.displayName)"
        let url = URL(string: "https://gourney.app/visit/\(feedItem.id)")
        
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
            AvatarView(url: comment.userAvatarUrl, size: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
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

#Preview {
    NavigationStack {
        FeedDetailView(
            feedItem: .preview,
            feedViewModel: FeedViewModel()
        )
    }
}
