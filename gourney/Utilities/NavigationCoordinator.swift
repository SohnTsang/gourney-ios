// Utilities/NavigationCoordinator.swift
// Centralized navigation coordinator for profile navigation across the app
// Uses standard NavigationStack push (like ListsView → ListDetailView)
// ✅ UPDATED: Always push ProfileView, even for own profile (slide from right)
// ✅ Kept shouldSwitchToProfileTab for search flows that need tab switching

import SwiftUI
import Combine

@MainActor
class NavigationCoordinator: ObservableObject {
    static let shared = NavigationCoordinator()
    
    // MARK: - Profile Navigation State
    /// The userId to navigate to - bind directly to navigationDestination(item:)
    /// SwiftUI will automatically set this to nil when the view is popped
    @Published var navigateToProfileUserId: String?
    
    // MARK: - Tab Switching State (for search flows)
    /// When true, MainTabView should switch to Profile tab
    @Published var shouldSwitchToProfileTab: Bool = false
    
    // MARK: - Pop to Root for All Tabs
    /// Tab index that should pop to root (0=Feed, 1=Discover, 2=Add, 3=Rank, 4=Profile)
    @Published var popToRootTab: Int?
    
    private init() {}
    
    // MARK: - Profile Navigation
    
    /// Navigate to a user's profile - ALWAYS pushes ProfileView (slide from right)
    /// Works for both own profile and other users' profiles
    /// - Parameter userId: The user ID to navigate to
    func showProfile(userId: String) {
        print("🧭 [Nav] Showing profile for userId: \(userId)")
        navigateToProfileUserId = userId
    }
    
    // MARK: - Switch to Profile Tab (for specific flows like search)
    
    /// Switch to the Profile tab in MainTabView
    /// Use for search results when user taps their own profile
    func switchToProfileTab() {
        shouldSwitchToProfileTab = true
        
        // Reset after a short delay to allow for re-triggering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.shouldSwitchToProfileTab = false
        }
    }
    
    // MARK: - Pop to Root
    
    /// Trigger pop-to-root for a specific tab
    /// - Parameter tabIndex: The tab index (0=Feed, 1=Discover, 2=Add, 3=Rank, 4=Profile)
    func triggerPopToRoot(tab tabIndex: Int) {
        print("🧭 [Nav] Triggering pop to root for tab \(tabIndex)")
        popToRootTab = tabIndex
        
        // Reset after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.popToRootTab = nil
        }
    }
    
    // MARK: - Helpers
    
    /// Check if navigation to this user is allowed (always true - all profiles are tappable)
    /// - Parameter userId: The user ID to check
    /// - Returns: True if the avatar/username should be tappable
    func canNavigateToProfile(userId: String) -> Bool {
        return true
    }
    
    /// Check if this is the current user
    /// - Parameter userId: The user ID to check
    /// - Returns: True if this is the current user's ID
    func isCurrentUser(userId: String) -> Bool {
        return userId == AuthManager.shared.currentUser?.id
    }
}
