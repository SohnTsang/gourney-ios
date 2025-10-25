// Views/MainTabView.swift
// Week 7 Day 4: Main tab bar with AddVisitView enabled for testing

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Discover (ACTIVE)
            DiscoverView()
                .tabItem {
                    Label(
                        NSLocalizedString("tab.discover", comment: ""),
                        systemImage: selectedTab == 0 ? "map.fill" : "map"
                    )
                }
                .tag(0)
            
            // Tab 2: Add Visit (ACTIVE - Testing)
            AddVisitView()
                .tabItem {
                    Label(
                        NSLocalizedString("tab.add", comment: ""),
                        systemImage: selectedTab == 1 ? "plus.circle.fill" : "plus.circle"
                    )
                }
                .tag(1)
            
            // Tab 3: Lists (Placeholder for Day 5)
            ListsPlaceholderView()
                .tabItem {
                    Label(
                        NSLocalizedString("tab.lists", comment: ""),
                        systemImage: selectedTab == 2 ? "list.bullet.rectangle.fill" : "list.bullet.rectangle"
                    )
                }
                .tag(2)
            
            // Tab 4: Feed (Placeholder for Day 6)
            FeedPlaceholderView()
                .tabItem {
                    Label(
                        NSLocalizedString("tab.feed", comment: ""),
                        systemImage: selectedTab == 3 ? "house.fill" : "house"
                    )
                }
                .tag(3)
            
            // Tab 5: Profile (Placeholder for Day 7)
            ProfilePlaceholderView()
                .tabItem {
                    Label(
                        NSLocalizedString("tab.profile", comment: ""),
                        systemImage: selectedTab == 4 ? "person.fill" : "person"
                    )
                }
                .tag(4)
        }
        .tint(.blue)
    }
}

// MARK: - Placeholder Views (Temporary for Days 5-7)

struct ListsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                Text("Lists")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Coming in Day 5")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Lists")
        }
    }
}

struct FeedPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "house")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                Text("Feed")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Coming in Day 6")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Feed")
        }
    }
}

struct ProfilePlaceholderView: View {
    @StateObject private var authManager = AuthManager.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.circle")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                
                Text("Profile")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Coming in Day 7")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Show current user info
                if let user = authManager.currentUser {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Logged in as:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("@\(user.handle)")
                            .font(.headline)
                        
                        Text(user.displayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                
                // Sign Out Button
                Button(action: {
                    authManager.signOut()
                }) {
                    Text("Sign Out")
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.top, 20)
            }
            .navigationTitle("Profile")
        }
    }
}

// MARK: - Preview

#Preview {
    MainTabView()
}
