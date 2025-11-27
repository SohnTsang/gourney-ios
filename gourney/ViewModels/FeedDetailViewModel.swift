//
//  FeedDetailViewModel.swift
//  gourney
//
//  Created by 曾家浩 on 2025/11/26.
//


// ViewModels/FeedDetailViewModel.swift
// ViewModel for Feed Detail View - handles comments, likes, and interactions
// Production-ready with memory optimization following Instagram patterns

import Foundation
import SwiftUI
import Combine

@MainActor
class FeedDetailViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published private(set) var comments: [Comment] = []
    @Published private(set) var isLoadingComments = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isPostingComment = false
    @Published private(set) var hasMoreComments = true
    @Published var error: String?
    @Published var commentText: String = ""
    @Published private(set) var editingComment: Comment? = nil
    
    // MARK: - Private Properties
    
    private let client = SupabaseClient.shared
    private let visitId: String
    private var nextCursor: String? = nil
    private let pageSize = 20
    private var fetchTask: Task<Void, Never>?
    private var hasLoadedOnce = false
    
    // Callback to update parent feed's comment count
    var onCommentCountChanged: ((Int) -> Void)?
    
    // MARK: - Computed Properties
    
    var commentCount: Int {
        comments.count
    }
    
    var canPostComment: Bool {
        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 1500 && !isPostingComment
    }
    
    var characterCount: Int {
        commentText.count
    }
    
    var isNearCharacterLimit: Bool {
        characterCount > 1400
    }
    
    var isEditing: Bool {
        editingComment != nil
    }
    
    // MARK: - Initialization
    
    init(visitId: String) {
        self.visitId = visitId
    }
    
    deinit {
        fetchTask?.cancel()
    }
    
    // MARK: - Load Comments
    
    func loadComments(refresh: Bool = false) {
        if hasLoadedOnce && !refresh && !comments.isEmpty {
            print("💬 [Comments] Already loaded, skipping")
            return
        }
        
        if fetchTask != nil && !refresh {
            print("⚠️ [Comments] Already fetching, skipping")
            return
        }
        
        if refresh {
            fetchTask?.cancel()
        }
        
        fetchTask = Task { [weak self] in
            guard let self = self else { return }
            await self.performFetch(refresh: refresh)
            self.fetchTask = nil
        }
    }
    
    private func performFetch(refresh: Bool) async {
        if refresh {
            nextCursor = nil
            hasMoreComments = true
        }
        
        guard hasMoreComments else {
            print("📭 [Comments] No more comments")
            return
        }
        
        if refresh || comments.isEmpty {
            isLoadingComments = true
        } else {
            isLoadingMore = true
        }
        
        defer {
            isLoadingComments = false
            isLoadingMore = false
        }
        
        do {
            try Task.checkCancellation()
            
            var path = "/functions/v1/comments-list?visit_id=\(visitId)&limit=\(pageSize)"
            if let cursor = nextCursor {
                path += "&cursor=\(cursor)"
            }
            print("📡 [Comments] Fetching: \(path)")
            
            let response: CommentsResponse = try await client.get(
                path: path,
                requiresAuth: true
            )
            
            try Task.checkCancellation()
            
            print("✅ [Comments] Got \(response.comments.count) comments")
            
            if refresh {
                comments = response.comments
            } else {
                let existingIds = Set(comments.map { $0.id })
                let newComments = response.comments.filter { !existingIds.contains($0.id) }
                comments.append(contentsOf: newComments)
            }
            
            hasMoreComments = response.nextCursor != nil
            nextCursor = response.nextCursor
            hasLoadedOnce = true
            error = nil
            
        } catch is CancellationError {
            print("⚠️ [Comments] Task cancelled")
        } catch {
            print("❌ [Comments] Error: \(error)")
            if !Task.isCancelled {
                self.error = "Failed to load comments"
            }
        }
    }
    
    // MARK: - Load More (Pagination)
    
    func loadMoreIfNeeded(currentComment: Comment) {
        guard let index = comments.firstIndex(where: { $0.id == currentComment.id }) else { return }
        
        if index >= comments.count - 5 && hasMoreComments && fetchTask == nil {
            fetchTask = Task { [weak self] in
                guard let self = self else { return }
                await self.performFetch(refresh: false)
                self.fetchTask = nil
            }
        }
    }
    
    // MARK: - Refresh
    
    func refresh() async {
        fetchTask?.cancel()
        fetchTask = nil
        
        let task = Task { [weak self] in
            guard let self = self else { return }
            await self.performFetch(refresh: true)
        }
        fetchTask = task
        await task.value
        fetchTask = nil
    }
    
    // MARK: - Post Comment
    
    func postComment() {
        let trimmedText = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, trimmedText.count <= 1500 else { return }
        
        // Check if editing or creating
        if let editing = editingComment {
            updateComment(editing, newText: trimmedText)
        } else {
            createComment(trimmedText)
        }
    }
    
    private func createComment(_ text: String) {
        isPostingComment = true
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        Task {
            do {
                let path = "/functions/v1/comments-create?visit_id=\(visitId)"
                print("📝 [Comment] Creating comment...")
                
                let response: CommentCreateResponse = try await client.post(
                    path: path,
                    body: ["comment_text": text],
                    requiresAuth: true
                )
                
                print("✅ [Comment] Created: \(response.id)")
                
                // Add to list
                let newComment = response.toComment(isOwnComment: true)
                comments.append(newComment)
                
                // Clear input
                commentText = ""
                
                // Notify parent to update count
                onCommentCountChanged?(1)
                
                // Success haptic
                let successGenerator = UINotificationFeedbackGenerator()
                successGenerator.notificationOccurred(.success)
                
            } catch {
                print("❌ [Comment] Create error: \(error)")
                self.error = "Failed to post comment"
                
                let errorGenerator = UINotificationFeedbackGenerator()
                errorGenerator.notificationOccurred(.error)
            }
            
            isPostingComment = false
        }
    }
    
    // MARK: - Edit Comment
    
    func startEditing(_ comment: Comment) {
        guard comment.isOwnComment else { return }
        editingComment = comment
        commentText = comment.commentText
    }
    
    func cancelEditing() {
        editingComment = nil
        commentText = ""
    }
    
    private func updateComment(_ comment: Comment, newText: String) {
        guard newText != comment.commentText else {
            cancelEditing()
            return
        }
        
        isPostingComment = true
        
        Task {
            do {
                let path = "/functions/v1/comments-update"
                print("✏️ [Comment] Updating: \(comment.id)")
                
                let response: CommentUpdateResponse = try await client.put(
                    path: path,
                    body: [
                        "comment_id": comment.id,
                        "comment_text": newText
                    ],
                    requiresAuth: true
                )
                
                print("✅ [Comment] Updated")
                
                // Update in list
                if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                    comments[index] = response.toComment(existingComment: comments[index])
                }
                
                // Clear editing state
                editingComment = nil
                commentText = ""
                
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
            } catch {
                print("❌ [Comment] Update error: \(error)")
                self.error = "Failed to update comment"
                
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
            
            isPostingComment = false
        }
    }
    
    // MARK: - Delete Comment
    
    func deleteComment(_ comment: Comment) {
        guard comment.isOwnComment else { return }
        
        // Optimistic removal
        let removedIndex = comments.firstIndex(where: { $0.id == comment.id })
        let removedComment = comment
        
        if let index = removedIndex {
            comments.remove(at: index)
        }
        
        // Notify parent
        onCommentCountChanged?(-1)
        
        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        Task {
            do {
                let path = "/functions/v1/comments-delete?comment_id=\(comment.id)"
                print("🗑️ [Comment] Deleting: \(comment.id)")
                
                let _: EmptyResponse = try await client.delete(
                    path: path,
                    requiresAuth: true
                )
                
                print("✅ [Comment] Deleted")
                
            } catch {
                print("❌ [Comment] Delete error: \(error)")
                
                // Rollback
                if let index = removedIndex, index <= comments.count {
                    comments.insert(removedComment, at: index)
                } else {
                    comments.append(removedComment)
                }
                onCommentCountChanged?(1)
                
                self.error = "Failed to delete comment"
            }
        }
    }
    
    // MARK: - Toggle Comment Like
    
    func toggleCommentLike(_ comment: Comment) {
        guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        
        // Can't like own comments
        guard !comment.isOwnComment else { return }
        
        let wasLiked = comments[index].isLiked
        let oldCount = comments[index].likeCount
        
        // Optimistic update
        comments[index].isLiked = !wasLiked
        comments[index].likeCount = wasLiked ? max(0, oldCount - 1) : oldCount + 1
        
        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        Task {
            do {
                let path = "/functions/v1/comment-like-toggle"
                print("❤️ [Comment Like] Toggling: \(comment.id)")
                
                let response: CommentLikeResponse = try await client.post(
                    path: path,
                    body: ["comment_id": comment.id],
                    requiresAuth: true
                )
                
                print("✅ [Comment Like] Result - liked: \(response.liked), count: \(response.likeCount)")
                
                // Sync with server
                if let idx = self.comments.firstIndex(where: { $0.id == comment.id }) {
                    self.comments[idx].isLiked = response.liked
                    self.comments[idx].likeCount = response.likeCount
                }
                
            } catch {
                print("❌ [Comment Like] Error: \(error)")
                
                // Rollback
                if let idx = self.comments.firstIndex(where: { $0.id == comment.id }) {
                    self.comments[idx].isLiked = wasLiked
                    self.comments[idx].likeCount = oldCount
                }
            }
        }
    }
    
    // MARK: - Memory Management
    
    func cleanup() {
        fetchTask?.cancel()
        fetchTask = nil
        
        // Keep reasonable number of comments in memory
        if comments.count > 50 {
            comments = Array(comments.prefix(50))
            hasMoreComments = true
        }
    }
    
    func reset() {
        fetchTask?.cancel()
        fetchTask = nil
        comments = []
        nextCursor = nil
        hasMoreComments = true
        hasLoadedOnce = false
        commentText = ""
        editingComment = nil
        error = nil
    }
}
