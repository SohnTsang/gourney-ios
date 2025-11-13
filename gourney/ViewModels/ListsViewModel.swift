import Foundation
import Combine

@MainActor
class ListsViewModel: ObservableObject {
    @Published var defaultLists: [RestaurantList] = []
    @Published var customLists: [RestaurantList] = []
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
    
    private func createDefaultListsIfNeeded() async {
        // Skip if we already have defaults OR any lists exist
        if !defaultLists.isEmpty || !customLists.isEmpty { return }
        
        do {
            // Fetch all lists first to check if defaults exist
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
            
            // Only create if missing
            if !hasWantToTry {
                let _: EmptyResponse = try await client.post(
                    path: "/functions/v1/lists-create",
                    body: ["title": wantToTryTitle, "visibility": "private"],
                    requiresAuth: true
                )
            }
            
            if !hasFavorites {
                let _: EmptyResponse = try await client.post(
                    path: "/functions/v1/lists-create",
                    body: ["title": favoritesTitle, "visibility": "private"],
                    requiresAuth: true
                )
            }
        } catch {
            print("⚠️ [Lists] Failed to create default lists: \(error)")
        }
    }
    
    func createList(title: String, description: String?, visibility: String) async -> Bool {
        do {
            let body: [String: Any] = [
                "title": title,
                "description": description ?? "",
                "visibility": visibility
            ]
            
            let _: EmptyResponse = try await client.post(
                path: "/functions/v1/lists-create",
                body: body,
                requiresAuth: true
            )
            
            await loadLists()
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ [Lists] Create error: \(error)")
            return false
        }
    }
    
    func deleteList(listId: String) async -> Bool {
        do {
            let _: EmptyResponse = try await client.delete(
                path: "/functions/v1/lists-delete?list_id=\(listId)",
                requiresAuth: true
            )
            
            await loadLists()
            return true
        } catch {
            errorMessage = error.localizedDescription
            print("❌ [Lists] Delete error: \(error)")
            return false
        }
    }
}

// MARK: - Response Models

struct ListsGetResponse: Codable {
    let lists: [RestaurantList]
}

struct EmptyResponse: Codable {}
