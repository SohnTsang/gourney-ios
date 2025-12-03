// ViewModels/FollowersFollowingViewModel.swift
// Manages followers/following list data with pagination
// Production-ready with memory optimization

import Foundation
import Combine

// MARK: - List Type Enum

enum FollowListType: String, CaseIterable {
    case followers = "followers"
    case following = "following"
    
    var title: String {
        switch self {
        case .followers: return "Followers"
        case .following: return "Following"
        }
    }
}

// MARK: - Follow User Model
// Note: SupabaseClient uses .convertFromSnakeCase automatically
// So we don't need explicit CodingKeys - just use camelCase property names

struct FollowUserItem: Codable, Identifiable, Equatable {
    let userId: String
    let userHandle: String
    let userDisplayName: String?
    let userAvatarUrl: String?
    var isFollowing: Bool
    let followedAt: String
    
    var id: String { userId }
    
    var displayNameOrHandle: String {
        if let name = userDisplayName, !name.isEmpty {
            return name
        }
        return userHandle
    }
    // No CodingKeys needed - automatic snake_case conversion handles it
}

// MARK: - API Response

struct FollowsListResponse: Codable {
    let users: [FollowUserItem]
    let totalCount: Int
    let nextCursor: String?
    // No CodingKeys needed - automatic snake_case conversion handles it
}

// Simple response for follow toggle - no CodingKeys needed
struct FollowToggleResponse: Codable {
    let success: Bool
    let action: String
    let followeeId: String
    let followeeHandle: String
    let followerCount: Int
    // No CodingKeys - automatic conversion handles snake_case → camelCase
}

// MARK: - ViewModel

@MainActor
class FollowersFollowingViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published private(set) var users: [FollowUserItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var error: String?
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var hasMore = true
    
    // For toggling follow state
    @Published private(set) var togglingFollowIds: Set<String> = []
    
    // MARK: - Private Properties
    
    private let client = SupabaseClient.shared
    private var userId: String?
    private var listType: FollowListType = .followers
    private var nextCursor: String?
    private var currentTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private let pageSize = 20
    
    // MARK: - Initialization
    
    deinit {
        currentTask?.cancel()
        paginationTask?.cancel()
    }
    
    // MARK: - Load Data
    
    func load(userId: String, type: FollowListType) {
        self.userId = userId
        self.listType = type
        
        currentTask?.cancel()
        paginationTask?.cancel()
        
        currentTask = Task { [weak self] in
            await self?.performLoad(refresh: true)
        }
    }
    
    func refresh() async {
        guard userId != nil else { return }
        await performLoad(refresh: true)
    }
    
    private func performLoad(refresh: Bool) async {
        if refresh {
            isLoading = true
            users = []
            nextCursor = nil
            hasMore = true
        }
        error = nil
        
        guard let userId = userId else {
            isLoading = false
            return
        }
        
        do {
            var path = "/functions/v1/follows-list?user_id=\(userId)&type=\(listType.rawValue)&limit=\(pageSize)"
            
            if let cursor = nextCursor, !refresh {
                let encodedCursor = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cursor
                path += "&cursor=\(encodedCursor)"
            }
            
            print("📋 [FollowList] Fetching \(listType.rawValue) for user: \(userId)")
            
            let response: FollowsListResponse = try await client.get(
                path: path,
                requiresAuth: true
            )
            
            if Task.isCancelled { return }
            
            if refresh {
                users = response.users
            } else {
                // Append without duplicates
                let existingIds = Set(users.map { $0.id })
                let newUsers = response.users.filter { !existingIds.contains($0.id) }
                users.append(contentsOf: newUsers)
            }
            
            totalCount = response.totalCount
            nextCursor = response.nextCursor
            hasMore = response.nextCursor != nil
            
            print("✅ [FollowList] Loaded \(response.users.count) users, total: \(totalCount), hasMore: \(hasMore)")
            
        } catch {
            if Task.isCancelled { return }
            print("❌ [FollowList] Error: \(error)")
            self.error = "Failed to load \(listType.title.lowercased())"
        }
        
        isLoading = false
        isLoadingMore = false
    }
    
    // MARK: - Pagination
    
    func loadMoreIfNeeded(currentUser: FollowUserItem) {
        guard hasMore,
              !isLoadingMore,
              nextCursor != nil,
              let index = users.firstIndex(where: { $0.id == currentUser.id }),
              index >= users.count - 5 else {
            return
        }
        
        paginationTask?.cancel()
        paginationTask = Task { [weak self] in
            self?.isLoadingMore = true
            await self?.performLoad(refresh: false)
        }
    }
    
    // MARK: - Toggle Follow
    
    func toggleFollow(for user: FollowUserItem) {
        guard !togglingFollowIds.contains(user.id) else { return }
        
        // Don't allow following yourself
        if user.userId == AuthManager.shared.currentUser?.id {
            return
        }
        
        togglingFollowIds.insert(user.id)
        
        Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let method = user.isFollowing ? "DELETE" : "POST"
                let path = "/functions/v1/follows-manage?user_id=\(user.userId)"
                
                print("🔄 [FollowList] \(user.isFollowing ? "Unfollowing" : "Following") @\(user.userHandle)")
                
                // Use FollowToggleResponse - no CodingKeys so auto-conversion works
                let _: FollowToggleResponse = try await client.request(
                    path: path,
                    method: method,
                    requiresAuth: true
                )
                
                // Update local state
                if let index = self.users.firstIndex(where: { $0.id == user.id }) {
                    var updatedUser = self.users[index]
                    updatedUser.isFollowing.toggle()
                    self.users[index] = updatedUser
                }
                
                print("✅ [FollowList] Follow toggled for @\(user.userHandle)")
                
            } catch {
                print("❌ [FollowList] Toggle follow error: \(error)")
            }
            
            self.togglingFollowIds.remove(user.id)
        }
    }
    
    // MARK: - Memory Management
    
    func cleanup() {
        currentTask?.cancel()
        paginationTask?.cancel()
        
        // Keep first 50 users for memory efficiency
        if users.count > 50 {
            users = Array(users.prefix(50))
            hasMore = true
        }
    }
}
