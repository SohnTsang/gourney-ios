// Services/LikeService.swift
// Standalone service for handling visit likes from any view
// Works independently of FeedViewModel/ProfileViewModel
// Broadcasts notifications so all views can stay in sync
// ✅ FIXED: Matches FeedViewModel/FeedDetailView pattern exactly
// - Cancel debounce task, NOT the API call
// - Check UI state before syncing
// - Retry on server mismatch (don't cancel)

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
    
    // Track debounce tasks per visit (only the sleep portion, NOT API calls)
    private var debounceTasks: [String: Task<Void, Never>] = [:]
    
    // Track current desired state per visit (what UI currently shows)
    private var currentStates: [String: Bool] = [:]
    
    private init() {}
    
    /// Toggle like for a visit - call this from any view
    /// Matches FeedViewModel/FeedDetailView pattern exactly
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
        
        // Store the current desired state
        currentStates[visitId] = newLikedState
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        // Cancel any pending DEBOUNCE task (NOT the API call)
        if debounceTasks[visitId] != nil {
            print("🚫 [LikeService] Cancelling pending debounce for \(visitId)")
            debounceTasks[visitId]?.cancel()
        }
        
        // Capture the final desired state AFTER the toggle
        let finalDesiredState = newLikedState
        
        print("⏳ [LikeService] Scheduling API call in 300ms, desiredState: \(finalDesiredState)")
        
        // Debounce: wait 300ms before making API call
        debounceTasks[visitId] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms
                print("⏰ [LikeService] 300ms passed, calling syncLikeWithServer")
                
                guard !Task.isCancelled else {
                    print("🚫 [LikeService] Debounce task was cancelled before sync")
                    return
                }
                
                // Run sync in a separate non-cancellable context
                await self?.syncLikeWithServer(
                    visitId: visitId,
                    desiredState: finalDesiredState,
                    onServerResponse: onServerResponse,
                    onError: onError
                )
                
            } catch {
                // Task.sleep throws CancellationError when cancelled
                print("🚫 [LikeService] Debounce cancelled (this is normal during rapid taps)")
            }
            
            self?.debounceTasks.removeValue(forKey: visitId)
        }
    }
    
    // MARK: - Sync with Server (matches FeedViewModel pattern exactly)
    
    private func syncLikeWithServer(
        visitId: String,
        desiredState: Bool,
        onServerResponse: @escaping (Bool, Int) -> Void,
        onError: ((Error) -> Void)?
    ) async {
        print("🌐 [LikeService] Starting sync for \(visitId), desiredState: \(desiredState)")
        
        // Check if UI state still matches what we want to sync
        guard currentStates[visitId] == desiredState else {
            print("⚠️ [LikeService] UI state changed (\(currentStates[visitId] ?? false) vs \(desiredState)), skipping sync")
            return
        }
        
        do {
            let path = "/functions/v1/likes-toggle?visit_id=\(visitId)"
            print("📤 [LikeService] Calling API: \(path)")
            
            let response: LikeResponse = try await client.post(
                path: path,
                body: [:],
                requiresAuth: true
            )
            
            print("📥 [LikeService] Server returned: liked=\(response.liked), count=\(response.likeCount)")
            
            // If server state matches desired state, sync the count
            if response.liked == desiredState {
                print("✅ [LikeService] Synced - liked: \(response.liked), count: \(response.likeCount)")
                onServerResponse(response.liked, response.likeCount)
                
                // Broadcast server-confirmed state
                broadcastLikeChange(visitId: visitId, isLiked: response.liked, likeCount: response.likeCount)
                
                // Clear stored state
                currentStates.removeValue(forKey: visitId)
            } else {
                // Server disagrees - retry (matches FeedViewModel pattern)
                print("⚠️ [LikeService] Server mismatch (got \(response.liked), wanted \(desiredState)), retrying...")
                await syncLikeWithServer(
                    visitId: visitId,
                    desiredState: desiredState,
                    onServerResponse: onServerResponse,
                    onError: onError
                )
                return
            }
            
        } catch {
            print("❌ [LikeService] Error: \(error.localizedDescription)")
            onError?(error)
            // Don't revert - keep UI state as user intended
            // Clear stored state
            currentStates.removeValue(forKey: visitId)
        }
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
        debounceTasks[visitId]?.cancel()
        debounceTasks.removeValue(forKey: visitId)
        currentStates.removeValue(forKey: visitId)
    }
    
    func cancelAll() {
        debounceTasks.values.forEach { $0.cancel() }
        debounceTasks.removeAll()
        currentStates.removeAll()
    }
}

// MARK: - Response Model

struct LikeResponse: Codable {
    let visitId: String
    let liked: Bool
    let likeCount: Int
    let createdAt: String?
}
