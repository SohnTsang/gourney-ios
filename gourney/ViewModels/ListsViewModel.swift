// gourney/ViewModels/ListsViewModel.swift
// ✅ FIXED: Load ownership pattern to prevent placeholder flash on tab switch

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
    @Published var popularLists: [PopularList] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    
    // ✅ Track whether initial load has completed for each tab
    @Published var hasLoadedMyLists = false
    @Published var hasLoadedFollowing = false
    @Published var hasLoadedPopular = false
    
    // Pagination
    private var myListsPage = 0
    private var followingPage = 0
    private let pageSize = 15
    @Published var hasMoreMyLists = true
    @Published var hasMoreFollowing = true
    
    private let client = SupabaseClient.shared
    
    // ✅ Load ownership tracking to prevent race conditions on tab switch
    private var currentLoadId: UUID?
    
    // Clear memory when leaving tab
    func clearMemory() {
        defaultLists.removeAll(keepingCapacity: false)
        customLists.removeAll(keepingCapacity: false)
        followingLists.removeAll(keepingCapacity: false)
        popularLists.removeAll(keepingCapacity: false)
        myListsPage = 0
        followingPage = 0
        hasMoreMyLists = true
        hasMoreFollowing = true
        currentLoadId = nil
        hasLoadedMyLists = false
        hasLoadedFollowing = false
        hasLoadedPopular = false
        print("🧹 [Lists] Memory cleared")
    }
    
    // MARK: - My Lists
    
    func loadLists(loadMore: Bool = false) async {
        // ✅ Generate new load ID and set loading state BEFORE starting async work
        let loadId = UUID()
        currentLoadId = loadId
        
        if loadMore {
            guard hasMoreMyLists && !isLoadingMore else { return }
            isLoadingMore = true
        } else {
            isLoading = true
            myListsPage = 0
            hasMoreMyLists = true
        }
        
        print("🔄 [Lists] loadLists started - loadId: \(loadId.uuidString.prefix(8))")
        errorMessage = nil
        
        do {
            guard client.getAuthToken() != nil else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
            }
            
            if !loadMore {
                await createDefaultListsIfNeeded()
            }
            
            // ✅ Check ownership before network call
            guard currentLoadId == loadId else {
                print("⚡ [Lists] MyLists load cancelled before request - ownership changed")
                return
            }
            
            let body: [String: Any] = [:]
            let response: ListsGetResponse = try await client.post(
                path: "/functions/v1/lists-get",
                body: body,
                requiresAuth: true
            )
            
            // ✅ Check ownership after network call - critical!
            guard currentLoadId == loadId else {
                print("⚡ [Lists] MyLists load completed but ownership changed - discarding")
                return
            }
            
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
            hasLoadedMyLists = true
            print("✅ [Lists] Loaded \(allLists.count) lists")
        } catch {
            // ✅ Only update state if we still own the load
            guard currentLoadId == loadId else {
                print("⚡ [Lists] MyLists error but ownership changed - ignoring")
                return
            }
            errorMessage = error.localizedDescription
            isLoading = false
            isLoadingMore = false
            hasLoadedMyLists = true  // Still mark as loaded even on error
            print("❌ [Lists] Load error: \(error)")
        }
    }
    
    // MARK: - Following Lists
    
    func loadFollowingLists(loadMore: Bool = false) async {
        // ✅ Generate new load ID and set loading state BEFORE starting async work
        let loadId = UUID()
        currentLoadId = loadId
        
        if loadMore {
            guard hasMoreFollowing && !isLoadingMore else { return }
            isLoadingMore = true
        } else {
            isLoading = true
            followingPage = 0
            hasMoreFollowing = true
        }
        
        print("🔄 [Lists] loadFollowingLists started - loadId: \(loadId.uuidString.prefix(8))")
        errorMessage = nil
        
        do {
            // ✅ Check ownership before network call
            guard currentLoadId == loadId else {
                print("⚡ [Lists] Following load cancelled before request - ownership changed")
                return
            }
            
            let response: FollowingListsResponse = try await client.post(
                path: "/functions/v1/lists-get-following",
                body: [:],
                requiresAuth: true
            )
            
            // ✅ Check ownership after network call - critical!
            guard currentLoadId == loadId else {
                print("⚡ [Lists] Following load completed but ownership changed - discarding")
                return
            }
            
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
            hasLoadedFollowing = true
            print("✅ [Lists] Loaded \(followingLists.count) following lists")
        } catch {
            // ✅ Only update state if we still own the load
            guard currentLoadId == loadId else {
                print("⚡ [Lists] Following error but ownership changed - ignoring")
                return
            }
            errorMessage = error.localizedDescription
            isLoading = false
            isLoadingMore = false
            hasLoadedFollowing = true  // Still mark as loaded even on error
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
            // Build URL with query parameter
            let path = "/functions/v1/lists-delete?list_id=\(listId)"
            
            let _: EmptyResponse = try await client.delete(
                path: path,
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
            
            // Edge function returns list directly, not wrapped in {list: ...}
            let newList: RestaurantList = try await client.post(
                path: "/functions/v1/lists-create",
                body: body,
                requiresAuth: true
            )
            
            customLists.insert(newList, at: 0)
            
            print("✅ [Lists] Created: \(newList.title)")
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ [Lists] Create error: \(error)")
            return false
        }
    }
    
    func updateListCoverPhoto(listId: String, photoUrl: String) async -> Bool {
        do {
            // Build URL with query parameter
            let path = "/functions/v1/lists-update?list_id=\(listId)"
            
            let body: [String: Any] = [
                "cover_photo_url": photoUrl
            ]
            
            let updatedList: RestaurantList = try await client.patch(
                path: path,
                body: body,
                requiresAuth: true
            )
            
            // Update in memory
            if let index = defaultLists.firstIndex(where: { $0.id == listId }) {
                defaultLists[index] = updatedList
            }
            if let index = customLists.firstIndex(where: { $0.id == listId }) {
                customLists[index] = updatedList
            }
            
            print("✅ [Lists] Updated cover photo: \(listId)")
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ [Lists] Update cover photo error: \(error)")
            return false
        }
    }
}

// MARK: - Popular Lists Extension

extension ListsViewModel {
    @MainActor
    func loadPopularLists(loadMore: Bool = false) async {
        // ✅ Generate new load ID and set loading state BEFORE starting async work
        let loadId = UUID()
        currentLoadId = loadId
        
        print("🔍 [Popular] loadPopularLists called - loadMore: \(loadMore), loadId: \(loadId.uuidString.prefix(8))")
        print("🔍 [Popular] Current state - count: \(popularLists.count), isLoading: \(isLoading), isLoadingMore: \(isLoadingMore)")
        
        // Skip if already loaded (not loading more)
        if !loadMore && !popularLists.isEmpty {
            print("⏭️ [Popular] Already loaded (\(popularLists.count) items), skipping")
            return
        }
        
        // Set loading flags BEFORE any async work
        if loadMore {
            guard !isLoadingMore else {
                print("⏭️ [Popular] Already loading more, skipping")
                return
            }
            print("🔄 [Popular] Setting isLoadingMore = true")
            isLoadingMore = true
        } else {
            print("🔄 [Popular] Setting isLoading = true")
            isLoading = true
        }
        
        do {
            // ✅ Check ownership before network call
            guard currentLoadId == loadId else {
                print("⚡ [Popular] Load cancelled before request - ownership changed")
                return
            }
            
            let body: [String: Any] = ["limit": 20]
            let response: PopularListsResponse = try await client.post(
                path: "/functions/v1/lists-get-popular",
                body: body,
                requiresAuth: true
            )
            
            // ✅ Check ownership after network call - critical!
            guard currentLoadId == loadId else {
                print("⚡ [Popular] Load completed but ownership changed - discarding")
                return
            }
            
            if loadMore {
                // Filter out duplicates before appending
                let newLists = response.lists.filter { newList in
                    !popularLists.contains(where: { $0.id == newList.id })
                }
                popularLists.append(contentsOf: newLists)
            } else {
                popularLists = response.lists
            }
            
            print("✅ [Popular] Loaded \(response.lists.count) popular lists")
            
            // ✅ Only reset loading state if we still own it
            isLoading = false
            isLoadingMore = false
            hasLoadedPopular = true
        } catch {
            // ✅ Only update state if we still own the load
            guard currentLoadId == loadId else {
                print("⚡ [Popular] Error but ownership changed - ignoring")
                return
            }
            print("❌ [Popular] Error loading: \(error)")
            errorMessage = error.localizedDescription
            isLoading = false
            isLoadingMore = false
            hasLoadedPopular = true  // Still mark as loaded even on error
        }
        
        print("🔄 [Popular] Load complete for loadId: \(loadId.uuidString.prefix(8))")
    }
    
    @MainActor
    func incrementListView(listId: String) async {
        do {
            let body = ["list_id": listId]
            let _: EmptyResponse = try await client.post(
                path: "/functions/v1/lists-increment-view",
                body: body,
                requiresAuth: true
            )
            print("✅ [View] Incremented view count for list: \(listId)")
        } catch {
            print("⚠️ [View] Failed to increment: \(error.localizedDescription)")
            // Silent fail - don't show error to user
        }
    }
    
    @MainActor
    func updateListItemCount(listId: String, newCount: Int) {
        print("🔄 [Lists] Updating itemCount for list \(listId): → \(newCount)")
        
        // Update in defaultLists
        if let index = defaultLists.firstIndex(where: { $0.id == listId }) {
            var updatedList = defaultLists[index]
            updatedList.itemCount = newCount
            defaultLists[index] = updatedList
            print("✅ [Lists] Updated defaultList[\(index)].itemCount = \(newCount)")
        }
        
        // Update in customLists
        if let index = customLists.firstIndex(where: { $0.id == listId }) {
            var updatedList = customLists[index]
            updatedList.itemCount = newCount
            customLists[index] = updatedList
            print("✅ [Lists] Updated customList[\(index)].itemCount = \(newCount)")
        }
    }
    
    @MainActor
    func refreshSingleList(listId: String) async {
        do {
            let body: [String: Any] = ["list_id": listId]
            let response: ListDetailResponse = try await client.post(
                path: "/functions/v1/lists-get-detail",
                body: body,
                requiresAuth: true
            )
            
            let updatedList = RestaurantList(
                id: response.list.id,
                title: response.list.title,
                description: response.list.description,
                visibility: response.list.visibility,
                itemCount: response.list.itemCount,
                coverPhotoUrl: response.list.coverPhotoUrl,
                createdAt: response.list.createdAt,
                likesCount: response.list.likesCount
            )
            
            if let index = defaultLists.firstIndex(where: { $0.id == listId }) {
                defaultLists[index] = updatedList
                print("✅ [Lists] Refreshed defaultList[\(index)] - cover: \(updatedList.coverPhotoUrl ?? "nil")")
            }
            
            if let index = customLists.firstIndex(where: { $0.id == listId }) {
                customLists[index] = updatedList
                print("✅ [Lists] Refreshed customList[\(index)] - cover: \(updatedList.coverPhotoUrl ?? "nil")")
            }
        } catch {
            print("❌ [Lists] Refresh single list error: \(error)")
        }
    }
}
