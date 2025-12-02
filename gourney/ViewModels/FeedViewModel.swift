// ViewModels/FeedViewModel.swift
// ViewModel for "For You" feed with cursor-based pagination
// Memory optimized following Instagram patterns
// FIX: Added notification listeners for seamless visit updates

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
    private var nextCursor: String? = nil
    private let pageSize = 10
    private var fetchTask: Task<Void, Never>?
    private var hasLoadedOnce = false
    
    // Notification subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // Debouncing for fast like taps
    private var pendingLikeTasks: [String: Task<Void, Never>] = [:]
    
    init() {
        setupNotificationListeners()
    }
    
    deinit {
        fetchTask?.cancel()
        cancellables.removeAll()
        pendingLikeTasks.values.forEach { $0.cancel() }
    }
    
    // MARK: - Notification Listeners
    
    private func setupNotificationListeners() {
        // Listen for visit updates
        NotificationCenter.default.publisher(for: .visitDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleVisitUpdate(notification)
            }
            .store(in: &cancellables)
        
        // Listen for visit deletes
        NotificationCenter.default.publisher(for: .visitDidDelete)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleVisitDelete(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleVisitUpdate(_ notification: Notification) {
        guard let visitId = notification.userInfo?[VisitNotificationKeys.visitId] as? String,
              let updatedData = notification.userInfo?[VisitNotificationKeys.updatedVisit] as? VisitUpdateData else {
            return
        }
        
        // Only update if this visit is in our feed
        guard let index = items.firstIndex(where: { $0.id == visitId }) else {
            print("📭 [FeedVM] Visit \(visitId) not in feed, skipping")
            return
        }
        
        print("📥 [FeedVM] Updating feed item at index \(index): \(visitId)")
        
        // Preserve existing item data that isn't in the update
        let existingItem = items[index]
        items[index] = FeedItem(
            id: updatedData.id,
            rating: updatedData.rating,
            comment: updatedData.comment,
            photoUrls: updatedData.photoUrls,
            visibility: updatedData.visibility,
            createdAt: updatedData.createdAt,
            visitedAt: updatedData.visitedAt,
            likeCount: existingItem.likeCount,
            commentCount: existingItem.commentCount,
            isLiked: existingItem.isLiked,
            isFollowing: existingItem.isFollowing,
            user: existingItem.user,
            place: existingItem.place
        )
        
        print("✅ [FeedVM] Feed item updated successfully")
    }
    
    private func handleVisitDelete(_ notification: Notification) {
        guard let visitId = notification.userInfo?[VisitNotificationKeys.visitId] as? String else {
            return
        }
        
        if let index = items.firstIndex(where: { $0.id == visitId }) {
            items.remove(at: index)
            print("🗑️ [FeedVM] Removed feed item: \(visitId)")
        }
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
    
    // MARK: - Toggle Like (Instagram-style - final state always wins)
    
    func toggleLike(for item: FeedItem) {
        print("🔥 [toggleLike] Called for item: \(item.id)")
        
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            print("⚠️ [toggleLike] Item NOT FOUND in items array!")
            return
        }
        
        let itemId = item.id
        let wasLiked = items[index].isLiked
        
        // Optimistic UI update immediately
        items[index].isLiked.toggle()
        items[index].likeCount += items[index].isLiked ? 1 : -1
        items[index].likeCount = max(0, items[index].likeCount)
        
        print("💫 [toggleLike] Optimistic update: \(wasLiked) -> \(items[index].isLiked), count: \(items[index].likeCount)")
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        // Cancel any pending API call for this item
        if pendingLikeTasks[itemId] != nil {
            print("🚫 [toggleLike] Cancelling pending task for \(itemId)")
            pendingLikeTasks[itemId]?.cancel()
        }
        
        // Capture the final desired state AFTER the toggle
        let finalDesiredState = items[index].isLiked
        
        print("⏳ [toggleLike] Scheduling API call in 300ms, desiredState: \(finalDesiredState)")
        
        // Debounce: wait 300ms before making API call
        pendingLikeTasks[itemId] = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms
                print("⏰ [toggleLike] 300ms passed, calling syncLikeWithServer")
                
                guard !Task.isCancelled else {
                    print("🚫 [toggleLike] Task was cancelled before sync")
                    return
                }
                
                await syncLikeWithServer(itemId: itemId, desiredState: finalDesiredState)
            } catch {
                print("❌ [toggleLike] Sleep error: \(error)")
            }
        }
    }
    
    private func syncLikeWithServer(itemId: String, desiredState: Bool) async {
        print("🌐 [syncLike] Starting for \(itemId), desiredState: \(desiredState)")
        
        // Get current UI state - this is what user expects to see
        guard let index = items.firstIndex(where: { $0.id == itemId }) else {
            print("⚠️ [syncLike] Item not found in array, aborting")
            return
        }
        let currentUIState = items[index].isLiked
        print("🔍 [syncLike] Current UI state: \(currentUIState)")
        
        // If UI state changed since we scheduled this call, don't proceed
        // (another tap happened and will handle it)
        guard currentUIState == desiredState else {
            print("⚠️ [syncLike] UI state changed (\(currentUIState) != \(desiredState)), skipping")
            return
        }
        
        do {
            let path = "/functions/v1/likes-toggle?visit_id=\(itemId)"
            print("📤 [syncLike] Calling API: \(path)")
            
            let response: LikeToggleResponse = try await client.post(
                path: path,
                body: [:],
                requiresAuth: true
            )
            
            print("📥 [syncLike] API Response - liked: \(response.liked), count: \(response.likeCount)")
            
            guard !Task.isCancelled else {
                print("🚫 [syncLike] Task cancelled after API call")
                return
            }
            
            // Check if UI state still matches what we wanted
            guard let idx = self.items.firstIndex(where: { $0.id == itemId }) else {
                print("⚠️ [syncLike] Item disappeared from array after API call")
                return
            }
            let currentState = items[idx].isLiked
            
            // If server state matches desired state, sync the count
            if response.liked == desiredState {
                self.items[idx].likeCount = response.likeCount
                print("✅ [Like] Synced - liked: \(response.liked), count: \(response.likeCount)")
            } else if currentState == desiredState {
                // Server disagrees but UI shows what user wants - call API again to fix
                print("⚠️ [Like] Server mismatch (server: \(response.liked), wanted: \(desiredState)), retrying...")
                await syncLikeWithServer(itemId: itemId, desiredState: desiredState)
                return
            }
            
        } catch {
            guard !Task.isCancelled else {
                print("🚫 [syncLike] Task cancelled during error handling")
                return
            }
            print("❌ [Like] Error: \(error)")
            // Don't revert - keep UI state as user intended
            // Next refresh will sync properly
        }
        
        pendingLikeTasks.removeValue(forKey: itemId)
        print("🧹 [syncLike] Cleaned up pending task for \(itemId)")
    }
    
    // MARK: - Update Like State (called from LikeService)
    
    func updateLikeState(visitId: String, isLiked: Bool, likeCount: Int) {
        if let index = items.firstIndex(where: { $0.id == visitId }) {
            items[index].isLiked = isLiked
            items[index].likeCount = likeCount
            print("✅ [Feed] Updated like state for: \(visitId)")
        }
    }
    
    // MARK: - Update Comment Count (called from FeedDetailView)
    
    func updateCommentCount(for visitId: String, delta: Int) {
        if let index = items.firstIndex(where: { $0.id == visitId }) {
            items[index].commentCount = max(0, items[index].commentCount + delta)
        }
    }
    
    // MARK: - Remove Visit (called after delete)
    
    func removeVisit(id: String) {
        items.removeAll { $0.id == id }
        print("🗑️ [Feed] Removed item: \(id)")
    }
    
    // MARK: - Update Item (after edit)
    
    func updateItem(_ updatedItem: FeedItem) {
        if let index = items.firstIndex(where: { $0.id == updatedItem.id }) {
            items[index] = updatedItem
            print("✅ [Feed] Updated item: \(updatedItem.id)")
        }
    }

    // MARK: - Update Item from Visit Response

    func updateItemFromVisit(visitId: String, rating: Int?, comment: String?, photoUrls: [String]?, visibility: String?) {
        guard let index = items.firstIndex(where: { $0.id == visitId }) else { return }
        
        if let rating = rating {
            items[index].rating = rating
        }
        if let comment = comment {
            items[index].comment = comment.isEmpty ? nil : comment
        }
        if let photoUrls = photoUrls {
            items[index].photoUrls = photoUrls.isEmpty ? nil : photoUrls
        }
        if let visibility = visibility {
            items[index].visibility = visibility
        }
        
        print("✅ [Feed] Updated item fields: \(visitId)")
    }

    // MARK: - Get Updated Item

    func getItem(id: String) -> FeedItem? {
        items.first { $0.id == id }
    }
    
    // MARK: - Memory Cleanup
    
    func cleanup() {
        fetchTask?.cancel()
        fetchTask = nil
        if items.count > 30 {
            items = Array(items.prefix(30))
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
