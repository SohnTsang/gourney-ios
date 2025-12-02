//
//  NavigationCoordinator.swift
//  gourney
//
//  Created by 曾家浩 on 2025/12/02.
//


// Services/NavigationCoordinator.swift
// Centralized navigation coordinator for profile navigation across the app
// Uses standard NavigationStack push (like ListsView → ListDetailView)

import SwiftUI
import Combine

@MainActor
class NavigationCoordinator: ObservableObject {
    static let shared = NavigationCoordinator()
    
    // MARK: - Profile Navigation State
    /// The userId to navigate to - bind directly to navigationDestination(item:)
    /// SwiftUI will automatically set this to nil when the view is popped
    @Published var navigateToProfileUserId: String?
    
    private init() {}
    
    // MARK: - Profile Navigation
    
    /// Navigate to a user's profile
    /// - Parameter userId: The user ID to navigate to
    /// - Note: Automatically prevents navigating to own profile
    func showProfile(userId: String) {
        // Don't navigate to own profile
        guard userId != AuthManager.shared.currentUser?.id else {
            print("⚠️ [Nav] Attempted to navigate to own profile, skipping")
            return
        }
        
        print("🧭 [Nav] Showing profile for userId: \(userId)")
        navigateToProfileUserId = userId
    }
    
    // MARK: - Helper
    
    /// Check if navigation to this user is allowed
    /// - Parameter userId: The user ID to check
    /// - Returns: True if navigation is allowed (not own profile)
    func canNavigateToProfile(userId: String) -> Bool {
        return userId != AuthManager.shared.currentUser?.id
    }
}
