// Services/SaveService.swift
// Centralized save (bookmark) service with debouncing for fast taps
// Follows the same pattern as LikeService for consistent UX
// ✅ FIX: Sends desired_state to avoid toggle race conditions

import Foundation
import UIKit

@MainActor
final class SaveService {
    static let shared = SaveService()
    
    private let client = SupabaseClient.shared
    
    // Debouncing: track pending tasks per visit
    private var pendingTasks: [String: Task<Void, Never>] = [:]
    
    // Track the "intended" UI state after rapid taps
    private var intendedStates: [String: Bool] = [:]
    
    // Track if an API call is currently in flight
    private var inFlightRequests: Set<String> = []
    
    private let debounceDelay: UInt64 = 300_000_000 // 300ms
    
    private init() {}
    
    /// Toggle save with debouncing
    func toggleSave(
        visitId: String,
        currentlySaved: Bool,
        onOptimisticUpdate: @escaping (Bool) -> Void,
        onServerResponse: @escaping (Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        // Calculate new intended state
        let newSavedState = !currentlySaved
        intendedStates[visitId] = newSavedState
        
        // Optimistic UI update immediately
        onOptimisticUpdate(newSavedState)
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        print("🔖 [SaveService] Toggle \(visitId) -> \(newSavedState)")
        
        // Cancel any pending debounce task
        pendingTasks[visitId]?.cancel()
        
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
            guard let intendedState = self.intendedStates[visitId] else {
                return
            }
            
            // Don't start new request if one is already in flight for same state
            guard !self.inFlightRequests.contains(visitId) else {
                print("🔖 [SaveService] Request already in flight for \(visitId)")
                return
            }
            
            // Make API call with desired state
            await self.syncWithServer(
                visitId: visitId,
                desiredState: intendedState,
                onServerResponse: onServerResponse,
                onError: onError
            )
        }
        
        pendingTasks[visitId] = task
    }
    
    private func syncWithServer(
        visitId: String,
        desiredState: Bool,
        onServerResponse: @escaping (Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        inFlightRequests.insert(visitId)
        
        do {
            // Send desired_state to avoid toggle race conditions
            let body: [String: Any] = [
                "visit_id": visitId,
                "desired_state": desiredState
            ]
            
            print("📤 [SaveService] Syncing \(visitId) -> \(desiredState)")
            
            let response: VisitSaveToggleResponse = try await client.post(
                path: "/functions/v1/visits-save-toggle",
                body: body,
                requiresAuth: true
            )
            
            inFlightRequests.remove(visitId)
            
            // Server should now match our desired state
            if response.isSaved == desiredState {
                print("✅ [SaveService] Confirmed: \(visitId) -> \(response.isSaved)")
            } else {
                print("⚠️ [SaveService] Unexpected: wanted \(desiredState), got \(response.isSaved)")
            }
            
            // Clean up and report
            cleanup(visitId: visitId)
            onServerResponse(response.isSaved)
            
        } catch let error as NSError where error.code == NSURLErrorCancelled {
            // Request was cancelled - ignore silently
            inFlightRequests.remove(visitId)
            // Don't cleanup intended state - let next request use it
            
        } catch {
            print("❌ [SaveService] Error: \(error.localizedDescription)")
            inFlightRequests.remove(visitId)
            cleanup(visitId: visitId)
            
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            onError(error)
        }
    }
    
    private func cleanup(visitId: String) {
        pendingTasks[visitId] = nil
        intendedStates[visitId] = nil
    }
    
    /// Cancel any pending save operation for a visit
    func cancelPending(visitId: String) {
        pendingTasks[visitId]?.cancel()
        cleanup(visitId: visitId)
        inFlightRequests.remove(visitId)
    }
    
    /// Cancel all pending operations
    func cancelAll() {
        pendingTasks.values.forEach { $0.cancel() }
        pendingTasks.removeAll()
        intendedStates.removeAll()
        inFlightRequests.removeAll()
    }
}
