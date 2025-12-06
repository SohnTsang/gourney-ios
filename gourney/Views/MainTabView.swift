// Views/MainTabView.swift
// ✅ UIKit UITabBarController - Industry standard (Instagram, TikTok, Twitter)
// ✅ INSTANT tab switching - no animations
// ✅ Proper memory management
// ✅ Same tab tap triggers pop to root
// ✅ FIX: Proper NavigationCoordinator access in UIViewControllerRepresentable

import SwiftUI
import UIKit
import Combine
// Global state for avatar preview (covers entire screen including tabs)
class AvatarPreviewState: ObservableObject {
    static let shared = AvatarPreviewState()
    
    @Published var isPresented = false
    @Published var image: UIImage? = nil
    @Published var imageUrl: String? = nil
    @Published var sourceFrame: CGRect = .zero
    
    func show(image: UIImage?, imageUrl: String?, sourceFrame: CGRect) {
        self.image = image
        self.imageUrl = imageUrl
        self.sourceFrame = sourceFrame
        self.isPresented = true
    }
    
    func hide() {
        self.isPresented = false
    }
}

struct MainTabView: View {
    @StateObject private var avatarPreviewState = AvatarPreviewState.shared
    
    var body: some View {
        ZStack {
            MainTabBarController()
                .ignoresSafeArea()
            
            // Full screen avatar preview overlay (covers tabs)
            if avatarPreviewState.isPresented {
                AvatarPreviewOverlay(
                    image: avatarPreviewState.image,
                    imageUrl: avatarPreviewState.imageUrl,
                    sourceFrame: avatarPreviewState.sourceFrame,
                    isPresented: $avatarPreviewState.isPresented
                )
            }
        }
    }
}

// MARK: - UIKit Tab Bar Controller (Instagram/TikTok Pattern)

struct MainTabBarController: UIViewControllerRepresentable {
    @ObservedObject private var navigator = NavigationCoordinator.shared
    
    func makeUIViewController(context: Context) -> UITabBarController {
        let tabBar = UITabBarController()
        tabBar.delegate = context.coordinator
        
        // Gourney coral color
        let coralColor = UIColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)
        
        // Configure tab bar appearance
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: coralColor
        ]
        
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttrs
        appearance.stackedLayoutAppearance.normal.iconColor = .secondaryLabel
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttrs
        appearance.stackedLayoutAppearance.selected.iconColor = coralColor
        
        tabBar.tabBar.standardAppearance = appearance
        tabBar.tabBar.scrollEdgeAppearance = appearance
        tabBar.tabBar.tintColor = coralColor
        
        // ✅ Create view controllers for each tab
        // Using UIHostingController to embed SwiftUI views
        
        // Tab 1: Feed
        let feedVC = UIHostingController(rootView: FeedView())
        feedVC.tabBarItem = UITabBarItem(
            title: "Feed",
            image: UIImage(systemName: "house"),
            selectedImage: UIImage(systemName: "house.fill")
        )
        feedVC.tabBarItem.tag = 0
        
        // Tab 2: Discover
        let discoverVC = UIHostingController(rootView: DiscoverView())
        discoverVC.tabBarItem = UITabBarItem(
            title: "Discover",
            image: UIImage(systemName: "magnifyingglass"),
            selectedImage: UIImage(systemName: "magnifyingglass.circle.fill")
        )
        discoverVC.tabBarItem.tag = 1
        
        // Tab 3: Add Visit
        let addVC = UIHostingController(rootView: AddVisitView())
        addVC.tabBarItem = UITabBarItem(
            title: "Add",
            image: UIImage(systemName: "plus.circle.fill"),
            selectedImage: UIImage(systemName: "plus.circle.fill")
        )
        addVC.tabBarItem.tag = 2
        
        // Tab 4: Rank
        let rankVC = UIHostingController(rootView: RankView())
        rankVC.tabBarItem = UITabBarItem(
            title: "Rank",
            image: UIImage(systemName: "trophy"),
            selectedImage: UIImage(systemName: "trophy.fill")
        )
        rankVC.tabBarItem.tag = 3
        
        // Tab 5: Profile
        let profileVC = UIHostingController(rootView: ProfileView())
        profileVC.tabBarItem = UITabBarItem(
            title: "Profile",
            image: UIImage(systemName: "person"),
            selectedImage: UIImage(systemName: "person.fill")
        )
        profileVC.tabBarItem.tag = 4
        
        tabBar.viewControllers = [feedVC, discoverVC, addVC, rankVC, profileVC]
        
        // Store reference in coordinator
        context.coordinator.tabBarController = tabBar
        
        return tabBar
    }
    
    func updateUIViewController(_ uiViewController: UITabBarController, context: Context) {
        // Handle programmatic tab switching (e.g., from search)
        if navigator.shouldSwitchToProfileTab {
            uiViewController.selectedIndex = 4
            DispatchQueue.main.async {
                NavigationCoordinator.shared.shouldSwitchToProfileTab = false
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, UITabBarControllerDelegate {
        weak var tabBarController: UITabBarController?
        private var previousIndex: Int = 0
        
        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            let newIndex = tabBarController.selectedIndex
            
            print("🔄 [Tab] Switched to tab \(newIndex)")
            
            // Same tab tapped - trigger pop to root
            if newIndex == previousIndex {
                print("🔄 [Tab] Same tab tapped - triggering pop to root")
                NavigationCoordinator.shared.triggerPopToRoot(tab: newIndex)
            }
            
            previousIndex = newIndex
        }
        
        // ✅ IMPORTANT: Prevent interactive pop gesture from interfering
        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            return true
        }
    }
}

#Preview {
    MainTabView()
}
