// Views/MainTabView.swift
// Main tab bar with Gourney design system
// Tab order: Feed, Discover, Add, Rank, Profile (5 tabs)

import SwiftUI
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
    @State private var selectedTab = 0
    @StateObject private var avatarPreviewState = AvatarPreviewState.shared
    
    // Gourney coral color
    private let coralColor = Color(red: 1.0, green: 0.4, blue: 0.4)
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                // Tab 1: Feed (Home)
                FeedView()
                    .tabItem {
                        Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                            .environment(\.symbolVariants, .none)
                        Text("Feed")
                    }
                    .tag(0)
                
                // Tab 2: Discover (Search/Map)
                DiscoverView()
                    .tabItem {
                        Image(systemName: selectedTab == 1 ? "magnifyingglass.circle.fill" : "magnifyingglass")
                            .environment(\.symbolVariants, .none)
                        Text("Discover")
                    }
                    .tag(1)
                
                // Tab 3: Add Visit (Center)
                AddVisitView()
                    .tabItem {
                        Image(systemName: "plus.circle.fill")
                            .environment(\.symbolVariants, .none)
                        Text("Add")
                    }
                    .tag(2)
                
                // Tab 4: Rank (Leaderboard)
                RankView()
                    .tabItem {
                        Image(systemName: selectedTab == 3 ? "trophy.fill" : "trophy")
                            .environment(\.symbolVariants, .none)
                        Text("Rank")
                    }
                    .tag(3)
                
                // Tab 5: Profile (has its own NavigationStack)
                ProfileView()
                    .tabItem {
                        Image(systemName: selectedTab == 4 ? "person.fill" : "person")
                            .environment(\.symbolVariants, .none)
                        Text("Profile")
                    }
                    .tag(4)
            }
            .tint(coralColor)
            
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
        .onAppear {
            configureTabBarAppearance()
        }
    }
    
    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        
        // Smaller font for tab labels
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)
        ]
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)
        ]
        
        // Normal state
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttrs
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.secondaryLabel
        
        // Selected state
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttrs
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    MainTabView()
}
