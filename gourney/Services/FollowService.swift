// Services/FollowService.swift
// Centralized follow/unfollow service with debouncing for fast taps
// Follows the same pattern as SaveService for consistent UX
// ✅ Sends desired_state to avoid toggle race conditions

import Foundation
import UIKit

@MainActor
final class FollowService {
    static let shared = FollowService()
    
    private let client = SupabaseClient.shared
    
    // Debouncing: track pending tasks per user
    private var pendingTasks: [String: Task<Void, Never>] = [:]
    
    // Track the "intended" UI state after rapid taps
    private var intendedStates: [String: Bool] = [:]
    
    // Track if an API call is currently in flight
    private var inFlightRequests: Set<String> = []
    
    private let debounceDelay: UInt64 = 300_000_000 // 300ms
    
    private init() {}
    
    /// Toggle follow with debouncing
    /// - Parameters:
    ///   - userId: The user ID to follow/unfollow
    ///   - currentlyFollowing: Current follow state
    ///   - onOptimisticUpdate: Called immediately with new state (for UI)
    ///   - onServerResponse: Called when server confirms (with actual state and follower count)
    ///   - onError: Called on error
    func toggleFollow(
        userId: String,
        currentlyFollowing: Bool,
        onOptimisticUpdate: @escaping (Bool) -> Void,
        onServerResponse: @escaping (Bool, Int) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        // Calculate new intended state
        let newFollowState = !currentlyFollowing
        intendedStates[userId] = newFollowState
        
        // Optimistic UI update immediately
        onOptimisticUpdate(newFollowState)
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        print("👥 [FollowService] Toggle \(userId) -> \(newFollowState ? "follow" : "unfollow")")
        
        // Cancel any pending debounce task
        pendingTasks[userId]?.cancel()
        
        // Create debounced task
        let task = Task { [weak self] in
            guard let self = self else { return }
            
            // Wait for debounce period
            do {
                try await Task.sleep(nanoseconds: self.debounceDelay)
            } catch {
                // Task was cancelled - another tap came in
                return
            }
            
            // After debounce, get the final intended state
            guard let intendedState = self.intendedStates[userId] else {
                return
            }
            
            // Don't start new request if one is already in flight
            guard !self.inFlightRequests.contains(userId) else {
                print("👥 [FollowService] Request already in flight for \(userId)")
                return
            }
            
            // Make API call with desired state
            await self.syncWithServer(
                userId: userId,
                desiredState: intendedState,
                onServerResponse: onServerResponse,
                onError: onError
            )
        }
        
        pendingTasks[userId] = task
    }
    
    private func syncWithServer(
        userId: String,
        desiredState: Bool,
        onServerResponse: @escaping (Bool, Int) -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        inFlightRequests.insert(userId)
        
        do {
            // Send desired_state to avoid toggle race conditions
            let body: [String: Any] = [
                "followee_id": userId,
                "desired_state": desiredState
            ]
            
            print("📤 [FollowService] Syncing \(userId) -> \(desiredState ? "follow" : "unfollow")")
            
            let response: FollowServiceResponse = try await client.post(
                path: "/functions/v1/follows-toggle",
                body: body,
                requiresAuth: true
            )
            
            inFlightRequests.remove(userId)
            
            // Server should now match our desired state
            if response.isFollowing == desiredState {
                print("✅ [FollowService] Confirmed: \(userId) -> \(response.isFollowing ? "following" : "not following")")
            } else {
                print("⚠️ [FollowService] Unexpected: wanted \(desiredState), got \(response.isFollowing)")
            }
            
            // Clean up and report
            cleanup(userId: userId)
            onServerResponse(response.isFollowing, response.followerCount)
            
        } catch let error as NSError where error.code == NSURLErrorCancelled {
            // Request was cancelled - ignore silently
            inFlightRequests.remove(userId)
            // Don't cleanup intended state - let next request use it
            
        } catch {
            print("❌ [FollowService] Error: \(error.localizedDescription)")
            inFlightRequests.remove(userId)
            cleanup(userId: userId)
            
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            onError(error)
        }
    }
    
    private func cleanup(userId: String) {
        pendingTasks[userId] = nil
        intendedStates[userId] = nil
    }
    
    /// Cancel any pending follow operation for a user
    func cancelPending(userId: String) {
        pendingTasks[userId]?.cancel()
        cleanup(userId: userId)
        inFlightRequests.remove(userId)
    }
    
    /// Cancel all pending operations
    func cancelAll() {
        pendingTasks.values.forEach { $0.cancel() }
        pendingTasks.removeAll()
        intendedStates.removeAll()
        inFlightRequests.removeAll()
    }
}

// MARK: - Response Model (for follows-toggle endpoint)

struct FollowServiceResponse: Codable {
    let success: Bool
    let isFollowing: Bool
    let action: String
    let followeeId: String
    let followerCount: Int
}
