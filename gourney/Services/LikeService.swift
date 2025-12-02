// Services/LikeService.swift
// Standalone service for handling visit likes from any view
// Works independently of FeedViewModel/ProfileViewModel
// Broadcasts notifications so all views can stay in sync

import Foundation
import SwiftUI
import Combine

// MARK: - Like Notification

extension Notification.Name {
    static let visitLikeDidChange = Notification.Name("visitLikeDidChange")
}

struct LikeNotificationKeys {
    static let visitId = "visitId"
    static let isLiked = "isLiked"
    static let likeCount = "likeCount"
}

@MainActor
class LikeService: ObservableObject {
    static let shared = LikeService()
    
    private let client = SupabaseClient.shared
    private var pendingTasks: [String: Task<Void, Never>] = [:]
    
    private init() {}
    
    /// Toggle like for a visit - call this from any view
    /// Returns the new like state and count via the callback
    func toggleLike(
        visitId: String,
        currentlyLiked: Bool,
        currentCount: Int,
        onOptimisticUpdate: @escaping (Bool, Int) -> Void,
        onServerResponse: @escaping (Bool, Int) -> Void,
        onError: ((Error) -> Void)? = nil
    ) {
        print("🔥 [LikeService] toggleLike for: \(visitId), currentlyLiked: \(currentlyLiked)")
        
        // Calculate optimistic state
        let newLikedState = !currentlyLiked
        let newCount = max(0, currentCount + (newLikedState ? 1 : -1))
        
        // Optimistic UI update immediately
        onOptimisticUpdate(newLikedState, newCount)
        print("💫 [LikeService] Optimistic: liked=\(newLikedState), count=\(newCount)")
        
        // Broadcast optimistic update
        broadcastLikeChange(visitId: visitId, isLiked: newLikedState, likeCount: newCount)
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        // Cancel any pending task for this visit
        pendingTasks[visitId]?.cancel()
        
        // Debounce API call
        pendingTasks[visitId] = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms
                
                guard !Task.isCancelled else {
                    print("🚫 [LikeService] Task cancelled")
                    return
                }
                
                print("📤 [LikeService] Calling API...")
                let response = try await syncWithServer(visitId: visitId)
                
                guard !Task.isCancelled else { return }
                
                print("✅ [LikeService] Server response: liked=\(response.liked), count=\(response.likeCount)")
                onServerResponse(response.liked, response.likeCount)
                
                // Broadcast server-confirmed state
                broadcastLikeChange(visitId: visitId, isLiked: response.liked, likeCount: response.likeCount)
                
            } catch is CancellationError {
                print("🚫 [LikeService] Cancelled")
            } catch {
                print("❌ [LikeService] Error: \(error)")
                onError?(error)
            }
            
            pendingTasks.removeValue(forKey: visitId)
        }
    }
    
    private func syncWithServer(visitId: String) async throws -> LikeResponse {
        let path = "/functions/v1/likes-toggle?visit_id=\(visitId)"
        
        let response: LikeResponse = try await client.post(
            path: path,
            body: [:],
            requiresAuth: true
        )
        
        return response
    }
    
    private func broadcastLikeChange(visitId: String, isLiked: Bool, likeCount: Int) {
        NotificationCenter.default.post(
            name: .visitLikeDidChange,
            object: nil,
            userInfo: [
                LikeNotificationKeys.visitId: visitId,
                LikeNotificationKeys.isLiked: isLiked,
                LikeNotificationKeys.likeCount: likeCount
            ]
        )
    }
    
    func cancelPending(for visitId: String) {
        pendingTasks[visitId]?.cancel()
        pendingTasks.removeValue(forKey: visitId)
    }
    
    func cancelAll() {
        pendingTasks.values.forEach { $0.cancel() }
        pendingTasks.removeAll()
    }
}

// MARK: - Response Model

struct LikeResponse: Codable {
    let visitId: String
    let liked: Bool
    let likeCount: Int
    let createdAt: String?
}
