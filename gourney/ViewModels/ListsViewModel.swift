// gourney/ViewModels/ListsViewModel.swift
// UPDATED: Fixed lists-get-following to use POST

import Foundation
import Combine

// MARK: - Following List Models

struct FollowingListItem: Identifiable {
    let id: String
    let title: String
    let userId: String
    let visibility: String
    let coverPhotoUrl: String?
    let createdAt: String
    let itemCount: Int
    let userHandle: String
    let userDisplayName: String?
    let userAvatarUrl: String?
    let likesCount: Int?  // Changed to stored property
}

struct FollowingListsResponse: Codable {
    let lists: [FollowingListAPIResponse]
}

struct FollowingListAPIResponse: Codable {
    let id: String
    let title: String
    let userId: String
    let visibility: String
    let coverPhotoUrl: String?
    let createdAt: String
    let itemCount: Int
    let userHandle: String
    let userDisplayName: String?
    let userAvatarUrl: String?
    let likesCount: Int?
}

// MARK: - ViewModel

@MainActor
class ListsViewModel: ObservableObject {
    @Published var defaultLists: [RestaurantList] = []
    @Published var customLists: [RestaurantList] = []
    @Published var followingLists: [FollowingListItem] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    
    // Pagination
    private var myListsPage = 0
    private var followingPage = 0
    private let pageSize = 15
    @Published var hasMoreMyLists = true
    @Published var hasMoreFollowing = true
    
    private let client = SupabaseClient.shared
    
    // Clear memory when leaving tab
    func clearMemory() {
        defaultLists.removeAll(keepingCapacity: false)
        customLists.removeAll(keepingCapacity: false)
        followingLists.removeAll(keepingCapacity: false)
        myListsPage = 0
        followingPage = 0
        hasMoreMyLists = true
        hasMoreFollowing = true
        print("🧹 [Lists] Memory cleared")
    }
    
    func loadLists(loadMore: Bool = false) async {
        if loadMore {
            guard hasMoreMyLists && !isLoadingMore else { return }
            isLoadingMore = true
        } else {
            isLoading = true
            myListsPage = 0
            hasMoreMyLists = true
        }
        
        errorMessage = nil
        
        do {
            guard let userId = client.getAuthToken() else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
            }
            
            if !loadMore {
                await createDefaultListsIfNeeded()
            }
            
            let body: [String: Any] = [:]
            let response: ListsGetResponse = try await client.post(
                path: "/functions/v1/lists-get",
                body: body,
                requiresAuth: true
            )
            
            let allLists = response.lists
            let defaults = allLists.filter {
                $0.title == NSLocalizedString("lists.default.want_to_try", comment: "") ||
                $0.title == NSLocalizedString("lists.default.favorites", comment: "")
            }
            let customs = allLists.filter { list in
                !defaults.contains { $0.id == list.id }
            }
            
            // Pagination for custom lists only
            let startIndex = myListsPage * pageSize
            let endIndex = min(startIndex + pageSize, customs.count)
            
            if loadMore {
                if startIndex < customs.count {
                    customLists.append(contentsOf: Array(customs[startIndex..<endIndex]))
                }
            } else {
                defaultLists = defaults
                customLists = endIndex > 0 ? Array(customs[0..<endIndex]) : []
            }
            
            hasMoreMyLists = endIndex < customs.count
            myListsPage += 1
            
            isLoading = false
            isLoadingMore = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            isLoadingMore = false
            print("❌ [Lists] Load error: \(error)")
        }
    }
    
    func loadFollowingLists(loadMore: Bool = false) async {
        if loadMore {
            guard hasMoreFollowing && !isLoadingMore else { return }
            isLoadingMore = true
        } else {
            // Don't reset the list immediately for smoother UI
            isLoading = true
            followingPage = 0
            hasMoreFollowing = true
        }
        
        errorMessage = nil
        
        do {
            let response: FollowingListsResponse = try await client.post(
                path: "/functions/v1/lists-get-following",
                body: [:],
                requiresAuth: true
            )
            
            let allFollowing = response.lists.map { apiList in
                FollowingListItem(
                    id: apiList.id,
                    title: apiList.title,
                    userId: apiList.userId,
                    visibility: apiList.visibility,
                    coverPhotoUrl: apiList.coverPhotoUrl,
                    createdAt: apiList.createdAt,
                    itemCount: apiList.itemCount,
                    userHandle: apiList.userHandle,
                    userDisplayName: apiList.userDisplayName,
                    userAvatarUrl: apiList.userAvatarUrl,
                    likesCount: apiList.likesCount
                )
            }
            
            if loadMore {
                // Pagination - append
                let startIndex = followingPage * pageSize
                let endIndex = min(startIndex + pageSize, allFollowing.count)
                
                if startIndex < allFollowing.count {
                    followingLists.append(contentsOf: Array(allFollowing[startIndex..<endIndex]))
                }
            } else {
                // Fresh load - replace
                followingLists = allFollowing
            }
            
            hasMoreFollowing = allFollowing.count > followingLists.count
            if !loadMore {
                followingPage = 1
            } else {
                followingPage += 1
            }
            
            isLoading = false
            isLoadingMore = false
            print("✅ [Lists] Loaded \(followingLists.count) following lists")
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            isLoadingMore = false
            print("❌ [Lists] Following lists error: \(error)")
        }
    }
    
    private func createDefaultListsIfNeeded() async {
        if !defaultLists.isEmpty || !customLists.isEmpty { return }
        
        do {
            let body: [String: Any] = [:]
            let response: ListsGetResponse = try await client.post(
                path: "/functions/v1/lists-get",
                body: body,
                requiresAuth: true
            )
            
            let wantToTryTitle = NSLocalizedString("lists.default.want_to_try", comment: "")
            let favoritesTitle = NSLocalizedString("lists.default.favorites", comment: "")
            
            let hasWantToTry = response.lists.contains { $0.title == wantToTryTitle }
            let hasFavorites = response.lists.contains { $0.title == favoritesTitle }
            
            if hasWantToTry && hasFavorites { return }
            
            print("⚠️ [Lists] Default lists missing - should be created by database trigger")
        } catch {
            print("❌ [Lists] Check defaults error: \(error)")
        }
    }
    
    func deleteList(listId: String) async -> Bool {
        do {
            let _: EmptyResponse = try await client.delete(
                path: "/functions/v1/lists-delete/\(listId)",
                requiresAuth: true
            )
            
            customLists.removeAll { $0.id == listId }
            print("✅ [Lists] Deleted list: \(listId)")
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ [Lists] Delete error: \(error)")
            return false
        }
    }
    
    func createList(title: String, description: String?, visibility: String) async -> Bool {
        do {
            let body: [String: Any] = [
                "title": title,
                "description": description ?? "",
                "visibility": visibility
            ]
            
            let response: CreateListResponse = try await client.post(
                path: "/functions/v1/lists-create",
                body: body,
                requiresAuth: true
            )
            
            let newList = response.list
            customLists.insert(newList, at: 0)
            
            print("✅ [Lists] Created: \(newList.title)")
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ [Lists] Create error: \(error)")
            return false
        }
    }
}
