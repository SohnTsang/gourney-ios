// ViewModels/FeedViewModel.swift
// ViewModel for "For You" feed with pagination and optimistic UI
// Memory optimized following Instagram patterns

import Foundation
import SwiftUI
import Combine  // ← Add this line


@MainActor
class FeedViewModel: ObservableObject {
    @Published private(set) var items: [FeedItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var error: String?
    @Published private(set) var showAllCaughtUp = false
    
    private let client = SupabaseClient.shared
    private var currentOffset = 0
    private let pageSize = 5
    private var isFetching = false
    private var loadTask: Task<Void, Never>?
    
    deinit {
        loadTask?.cancel()
    }
    
    // MARK: - Load Feed
    
    func loadFeed(refresh: Bool = false) async {
        guard !isFetching else {
            print("⚠️ [Feed] Already fetching, skipping")
            return
        }
        
        if refresh {
            currentOffset = 0
            hasMore = true
            showAllCaughtUp = false
        }
        
        guard hasMore else {
            print("📭 [Feed] No more items")
            return
        }
        
        isFetching = true
        
        if refresh || items.isEmpty {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        
        do {
            let path = "/functions/v1/feed-for-you?limit=\(pageSize)&offset=\(currentOffset)"
            print("📡 [Feed] Fetching: \(path)")
            
            let response: FeedResponse = try await client.get(
                path: path,
                requiresAuth: true
            )
            
            print("✅ [Feed] Got \(response.items.count) items, hasMore: \(response.hasMore)")
            
            if refresh {
                items = response.items
            } else {
                let existingIds = Set(items.map { $0.id })
                let newItems = response.items.filter { !existingIds.contains($0.id) }
                items.append(contentsOf: newItems)
            }
            
            hasMore = response.hasMore
            currentOffset = response.nextOffset ?? (currentOffset + pageSize)
            
            if !hasMore && !items.isEmpty {
                showAllCaughtUp = true
            }
            
            error = nil
            
        } catch {
            print("❌ [Feed] Error: \(error)")
            self.error = error.localizedDescription
        }
        
        isLoading = false
        isLoadingMore = false
        isFetching = false
    }
    
    // MARK: - Load More (Pagination)
    
    func loadMoreIfNeeded(currentItem: FeedItem) {
        loadTask?.cancel()
        
        guard let index = items.firstIndex(where: { $0.id == currentItem.id }) else { return }
        
        if index >= items.count - 2 && hasMore && !isFetching {
            loadTask = Task {
                await loadFeed()
            }
        }
    }
    
    // MARK: - Toggle Like (Optimistic UI)
    
    func toggleLike(for item: FeedItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        
        let wasLiked = items[index].isLiked
        items[index].isLiked = !wasLiked
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        Task {
            do {
                let path = "/functions/v1/likes-toggle?visit_id=\(item.id)"
                print("❤️ [Like] Toggling for visit: \(item.id)")
                
                let _: LikeToggleResponse = try await client.post(
                    path: path,
                    body: [:],
                    requiresAuth: true
                )
                
                print("✅ [Like] Toggle successful")
                
            } catch {
                print("❌ [Like] Error: \(error)")
                await MainActor.run {
                    if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[idx].isLiked = wasLiked
                    }
                }
            }
        }
    }
    
    // MARK: - Refresh
    
    func refresh() async {
        await loadFeed(refresh: true)
    }
    
    // MARK: - Memory Cleanup
    
    func cleanup() {
        loadTask?.cancel()
        loadTask = nil
        if items.count > 20 {
            items = Array(items.prefix(20))
            currentOffset = 20
            hasMore = true
            showAllCaughtUp = false
        }
    }
}

// MARK: - Like Toggle Response

private struct LikeToggleResponse: Codable {
    let liked: Bool
    let likeCount: Int
    
    enum CodingKeys: String, CodingKey {
        case liked
        case likeCount = "like_count"
    }
}
