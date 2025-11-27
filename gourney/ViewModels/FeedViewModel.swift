// ViewModels/FeedViewModel.swift
// ViewModel for "For You" feed with cursor-based pagination
// Memory optimized following Instagram patterns

import Foundation
import SwiftUI
import Combine

@MainActor
class FeedViewModel: ObservableObject {
    @Published private(set) var items: [FeedItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var error: String?
    @Published private(set) var showAllCaughtUp = false
    
    private let client = SupabaseClient.shared
    private var nextCursor: String? = nil  // Changed from offset
    private let pageSize = 10
    private var fetchTask: Task<Void, Never>?
    private var hasLoadedOnce = false
    
    deinit {
        fetchTask?.cancel()
    }
    
    // MARK: - Load Feed (Non-async entry point)
    
    func loadFeed(refresh: Bool = false) {
        if hasLoadedOnce && !refresh && !items.isEmpty {
            print("📋 [Feed] Already loaded, skipping")
            return
        }
        
        if fetchTask != nil && !refresh {
            print("⚠️ [Feed] Already fetching, skipping")
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
    
    // MARK: - Perform Fetch (Internal async logic)
    
    private func performFetch(refresh: Bool) async {
        if refresh {
            nextCursor = nil
            hasMore = true
            showAllCaughtUp = false
        }
        
        guard hasMore else {
            print("📭 [Feed] No more items")
            return
        }
        
        if refresh || items.isEmpty {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        
        defer {
            isLoading = false
            isLoadingMore = false
        }
        
        do {
            try Task.checkCancellation()
            
            var path = "/functions/v1/feed-for-you?limit=\(pageSize)"
            if let cursor = nextCursor {
                path += "&cursor=\(cursor)"
            }
            print("📡 [Feed] Fetching: \(path)")
            
            let response: FeedResponse = try await client.get(
                path: path,
                requiresAuth: true
            )
            
            try Task.checkCancellation()
            
            print("✅ [Feed] Got \(response.items.count) items, hasMore: \(response.hasMore)")
            
            if refresh {
                items = response.items
            } else {
                let existingIds = Set(items.map { $0.id })
                let newItems = response.items.filter { !existingIds.contains($0.id) }
                items.append(contentsOf: newItems)
            }
            
            hasMore = response.hasMore
            nextCursor = response.nextCursor
            hasLoadedOnce = true
            
            if !hasMore && !items.isEmpty {
                showAllCaughtUp = true
            }
            
            error = nil
            
        } catch is CancellationError {
            print("⚠️ [Feed] Task cancelled - ignoring")
        } catch let urlError as NSError where urlError.domain == NSURLErrorDomain && urlError.code == NSURLErrorCancelled {
            print("⚠️ [Feed] URL request cancelled - ignoring")
        } catch {
            print("❌ [Feed] Error: \(error)")
            if !Task.isCancelled {
                self.error = error.localizedDescription
            }
        }
    }
    
    // MARK: - Load More (Pagination)
    
    func loadMoreIfNeeded(currentItem: FeedItem) {
        guard let index = items.firstIndex(where: { $0.id == currentItem.id }) else { return }
        
        if index >= items.count - 3 && hasMore && fetchTask == nil {
            fetchTask = Task { [weak self] in
                guard let self = self else { return }
                await self.performFetch(refresh: false)
                self.fetchTask = nil
            }
        }
    }
    
    // MARK: - Refresh (for pull-to-refresh)
    
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
    
    // MARK: - Toggle Like (Optimistic UI)
    
    func toggleLike(for item: FeedItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        
        let wasLiked = items[index].isLiked
        let oldCount = items[index].likeCount
        
        items[index].isLiked = !wasLiked
        items[index].likeCount = wasLiked ? max(0, oldCount - 1) : oldCount + 1
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        Task {
            do {
                let path = "/functions/v1/likes-toggle?visit_id=\(item.id)"
                print("❤️ [Like] Toggling for visit: \(item.id)")
                
                let response: LikeToggleResponse = try await client.post(
                    path: path,
                    body: [:],
                    requiresAuth: true
                )
                
                print("✅ [Like] Toggle successful - liked: \(response.liked), count: \(response.likeCount)")
                
                if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                    self.items[idx].isLiked = response.liked
                    self.items[idx].likeCount = response.likeCount
                }
                
            } catch {
                print("❌ [Like] Error: \(error)")
                if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                    self.items[idx].isLiked = wasLiked
                    self.items[idx].likeCount = oldCount
                }
            }
        }
    }
    
    // MARK: - Update Comment Count (called from FeedDetailView)
    
    func updateCommentCount(for visitId: String, delta: Int) {
        if let index = items.firstIndex(where: { $0.id == visitId }) {
            items[index].commentCount = max(0, items[index].commentCount + delta)
        }
    }
    
    // MARK: - Memory Cleanup
    
    func cleanup() {
        fetchTask?.cancel()
        fetchTask = nil
        if items.count > 30 {
            items = Array(items.prefix(30))
            // Reset cursor to allow reloading from where we trimmed
            hasMore = true
            showAllCaughtUp = false
        }
    }
    
    func reset() {
        fetchTask?.cancel()
        fetchTask = nil
        items = []
        nextCursor = nil
        hasMore = true
        hasLoadedOnce = false
        showAllCaughtUp = false
        error = nil
    }
}

// MARK: - Like Toggle Response

private struct LikeToggleResponse: Codable {
    let visitId: String
    let liked: Bool
    let likeCount: Int
    let createdAt: String?
}
