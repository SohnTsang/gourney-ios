//
//  NavigationCoordinator.swift
//  gourney
//
//  Created by 曾家浩 on 2025/12/02.
//


// Services/NavigationCoordinator.swift
// Centralized navigation coordinator for profile navigation across the app
// Uses standard NavigationStack push (like ListsView → ListDetailView)
// ✅ FIX: Added support for switching to Profile tab when tapping own avatar

import SwiftUI
import Combine

@MainActor
class NavigationCoordinator: ObservableObject {
    static let shared = NavigationCoordinator()
    
    // MARK: - Profile Navigation State
    /// The userId to navigate to - bind directly to navigationDestination(item:)
    /// SwiftUI will automatically set this to nil when the view is popped
    @Published var navigateToProfileUserId: String?
    
    // ✅ NEW: Tab switching state
    /// When true, MainTabView should switch to Profile tab
    @Published var shouldSwitchToProfileTab: Bool = false
    
    /// When true, ProfileView should pop to root
    @Published var shouldPopProfileToRoot: Bool = false
    
    private init() {}
    
    // MARK: - Profile Navigation
    
    /// Navigate to a user's profile
    /// - Parameter userId: The user ID to navigate to
    /// - Note: If own profile, switches to Profile tab instead of pushing
    func showProfile(userId: String) {
        // ✅ If own profile, switch to Profile tab instead
        guard userId != AuthManager.shared.currentUser?.id else {
            print("🧭 [Nav] Own profile tapped, switching to Profile tab (root)")
            switchToProfileTab()
            return
        }
        
        print("🧭 [Nav] Showing profile for userId: \(userId)")
        navigateToProfileUserId = userId
    }
    
    // ✅ NEW: Switch to Profile tab and pop to root
    func switchToProfileTab() {
        // First pop ProfileView to root
        shouldPopProfileToRoot = true
        
        // Then switch tab
        shouldSwitchToProfileTab = true
        
        // Reset after a short delay to allow for re-triggering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.shouldSwitchToProfileTab = false
            self?.shouldPopProfileToRoot = false
        }
    }
    
    // MARK: - Helper
    
    /// Check if navigation to this user is allowed (always true now - we handle own profile differently)
    /// - Parameter userId: The user ID to check
    /// - Returns: True if the avatar/username should be tappable
    func canNavigateToProfile(userId: String) -> Bool {
        // ✅ Changed: Always return true - we handle own profile with tab switch
        return true
    }
    
    /// Check if this is the current user
    /// - Parameter userId: The user ID to check
    /// - Returns: True if this is the current user's ID
    func isCurrentUser(userId: String) -> Bool {
        return userId == AuthManager.shared.currentUser?.id
    }
}
