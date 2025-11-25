// Views/MainTabView.swift
// Main tab bar with Gourney design system
// Tab order: Feed, Discover, Add, Rank, Lists, Profile

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    
    // Gourney coral color
    private let coralColor = Color(red: 1.0, green: 0.4, blue: 0.4)
    
    var body: some View {
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
            
            // Tab 5: Lists
            ListsView()
                .tabItem {
                    Image(systemName: selectedTab == 4 ? "bookmark.fill" : "bookmark")
                        .environment(\.symbolVariants, .none)
                    Text("Lists")
                }
                .tag(4)
            
            // Tab 6: Profile
            ProfilePlaceholderView()
                .tabItem {
                    Image(systemName: selectedTab == 5 ? "person.fill" : "person")
                        .environment(\.symbolVariants, .none)
                    Text("Profile")
                }
                .tag(5)
        }
        .tint(coralColor)
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

// MARK: - Profile Placeholder

struct ProfilePlaceholderView: View {
    @StateObject private var authManager = AuthManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private let coralColor = Color(red: 1.0, green: 0.4, blue: 0.4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header
                    profileHeader
                    
                    // Stats Row
                    if let user = authManager.currentUser {
                        statsRow(user: user)
                    }
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Coming Soon
                    comingSoonSection
                    
                    // Sign Out Button
                    signOutButton
                    
                    Spacer(minLength: 100)
                }
            }
            .background(colorScheme == .dark ? Color.black : Color(.systemGroupedBackground))
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var profileHeader: some View {
        VStack(spacing: 12) {
            // Avatar
            if let user = authManager.currentUser,
               let avatarUrl = user.avatarUrl,
               let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    default:
                        defaultAvatar
                    }
                }
            } else {
                defaultAvatar
            }
            
            // Name & Handle
            if let user = authManager.currentUser {
                VStack(spacing: 4) {
                    Text(user.displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("@\(user.handle)")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.top, 20)
    }
    
    private func statsRow(user: User) -> some View {
        HStack(spacing: 40) {
            statItem(value: user.visitCount ?? 0, label: "Visits")
            statItem(value: user.followerCount ?? 0, label: "Followers")
            statItem(value: user.followingCount ?? 0, label: "Following")
        }
        .padding(.vertical, 16)
    }
    
    private var comingSoonSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 40))
                .foregroundColor(coralColor.opacity(0.5))
            
            Text("Profile Coming Soon")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 40)
    }
    
    private var signOutButton: some View {
        Button(action: {
            authManager.signOut()
        }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding(.horizontal, 20)
    }
    
    private var defaultAvatar: some View {
        Circle()
            .fill(Color(.systemGray5))
            .frame(width: 80, height: 80)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
            }
    }
    
    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    MainTabView()
}
