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
    
    // TODO: Add when backend implements list_likes table
    var likesCount: Int? { return 0 }
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
    
    enum CodingKeys: String, CodingKey {
        case id, title, visibility, itemCount, createdAt
        case userId = "user_id"
        case coverPhotoUrl = "cover_photo_url"
        case userHandle = "user_handle"
        case userDisplayName = "user_display_name"
        case userAvatarUrl = "user_avatar_url"
    }
}

// MARK: - ViewModel

@MainActor
class ListsViewModel: ObservableObject {
    @Published var defaultLists: [RestaurantList] = []
    @Published var customLists: [RestaurantList] = []
    @Published var followingLists: [FollowingListItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let client = SupabaseClient.shared
    
    func loadLists() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let userId = client.getAuthToken() else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
            }
            
            await createDefaultListsIfNeeded()
            
            let body: [String: Any] = [:]
            let response: ListsGetResponse = try await client.post(
                path: "/functions/v1/lists-get",
                body: body,
                requiresAuth: true
            )
            
            let lists = response.lists
            
            defaultLists = lists.filter {
                $0.title == NSLocalizedString("lists.default.want_to_try", comment: "") ||
                $0.title == NSLocalizedString("lists.default.favorites", comment: "")
            }
            customLists = lists.filter { list in
                !defaultLists.contains { $0.id == list.id }
            }
            
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            print("❌ [Lists] Load error: \(error)")
        }
    }
    
    func loadFollowingLists() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response: FollowingListsResponse = try await client.get(
                path: "/functions/v1/lists-get-following?limit=20",
                requiresAuth: true
            )
            
            followingLists = response.lists.map { apiList in
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
                    userAvatarUrl: apiList.userAvatarUrl
                )
            }
            
            isLoading = false
            print("✅ [Lists] Loaded \(followingLists.count) following lists")
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
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
