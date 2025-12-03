// Views/Profile/FollowersFollowingListView.swift
// Shared component for displaying followers/following lists
// Instagram-style design with coral theme
// Supports navigation to user profiles

import SwiftUI

struct FollowersFollowingListView: View {
    let userId: String
    let userHandle: String
    let initialTab: FollowListType
    let followerCount: Int
    let followingCount: Int
    
    @StateObject private var viewModel = FollowersFollowingViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedTab: FollowListType
    @State private var searchText = ""
    
    // For pushing user profiles within this view's navigation context
    @State private var selectedUserIdForNavigation: String?
    
    init(
        userId: String,
        userHandle: String,
        initialTab: FollowListType,
        followerCount: Int = 0,
        followingCount: Int = 0
    ) {
        self.userId = userId
        self.userHandle = userHandle
        self.initialTab = initialTab
        self.followerCount = followerCount
        self.followingCount = followingCount
        _selectedTab = State(initialValue: initialTab)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    // Filtered users based on search
    private var filteredUsers: [FollowUserItem] {
        if searchText.isEmpty {
            return viewModel.users
        }
        let query = searchText.lowercased()
        return viewModel.users.filter { user in
            user.userHandle.lowercased().contains(query) ||
            (user.userDisplayName?.lowercased().contains(query) ?? false)
        }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Spacer for top bar
                Color.clear.frame(height: 52)
                
                // Tab Picker
                tabPicker
                
                // Search Bar (uses shared SearchTextField component)
                SearchTextField(text: $searchText, placeholder: "Search users")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                // Content
                if viewModel.isLoading && viewModel.users.isEmpty {
                    Spacer()
                    LoadingSpinner()
                    Spacer()
                } else if let error = viewModel.error, viewModel.users.isEmpty {
                    Spacer()
                    errorView(error)
                    Spacer()
                } else if filteredUsers.isEmpty {
                    Spacer()
                    emptyStateView
                    Spacer()
                } else {
                    usersList
                }
            }
            
            // Fixed Top Bar
            topBar
        }
        .navigationBarHidden(true)
        // Navigation to user profile when tapping a row
        .navigationDestination(item: $selectedUserIdForNavigation) { userId in
            ProfileView(userId: userId)
        }
        .onAppear {
            viewModel.load(userId: userId, type: selectedTab)
        }
        .onChange(of: selectedTab) { _, newTab in
            viewModel.load(userId: userId, type: newTab)
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        VStack(spacing: 0) {
            ZStack {
                // Center: Username
                Text(userHandle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Left: Back button
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .padding(.leading, 4)
                    
                    Spacer()
                }
            }
            .frame(height: 44)
            .padding(.top, 8)
            .background(backgroundColor)
        }
    }
    
    // MARK: - Tab Picker (Instagram-style with counts)
    
    private var tabPicker: some View {
        HStack(spacing: 0) {
            // Followers Tab
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = .followers
                }
            } label: {
                VStack(spacing: 4) {
                    Text("\(formatCount(followerCount))")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(selectedTab == .followers ? .primary : .secondary)
                    
                    Text("Followers")
                        .font(.system(size: 13))
                        .foregroundColor(selectedTab == .followers ? .primary : .secondary)
                    
                    Rectangle()
                        .fill(selectedTab == .followers ? GourneyColors.coral : Color.clear)
                        .frame(height: 2)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            
            // Following Tab
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = .following
                }
            } label: {
                VStack(spacing: 4) {
                    Text("\(formatCount(followingCount))")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(selectedTab == .following ? .primary : .secondary)
                    
                    Text("Following")
                        .font(.system(size: 13))
                        .foregroundColor(selectedTab == .following ? .primary : .secondary)
                    
                    Rectangle()
                        .fill(selectedTab == .following ? GourneyColors.coral : Color.clear)
                        .frame(height: 2)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Users List
    
    private var usersList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredUsers) { user in
                    FollowUserRow(
                        user: user,
                        isToggling: viewModel.togglingFollowIds.contains(user.id),
                        onFollowTap: {
                            viewModel.toggleFollow(for: user)
                        },
                        onRowTap: {
                            // Check if it's own profile - switch to profile tab
                            if user.userId == AuthManager.shared.currentUser?.id {
                                NavigationCoordinator.shared.switchToProfileTab()
                            } else {
                                // Push the user's profile view
                                selectedUserIdForNavigation = user.userId
                            }
                        }
                    )
                    .onAppear {
                        viewModel.loadMoreIfNeeded(currentUser: user)
                    }
                    
                    // Divider (except for last item)
                    if user.id != filteredUsers.last?.id {
                        Divider()
                            .padding(.leading, 76)
                    }
                }
                
                // Loading more indicator
                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        LoadingSpinner(size: 16)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
            }
            .padding(.bottom, 100)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedTab == .followers ? "person.2" : "person.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(GourneyColors.coral.opacity(0.5))
            
            if searchText.isEmpty {
                Text(selectedTab == .followers ? "No followers yet" : "Not following anyone yet")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            } else {
                Text("No users found")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 48))
                .foregroundColor(GourneyColors.coral.opacity(0.5))
            
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            
            Button {
                viewModel.load(userId: userId, type: selectedTab)
            } label: {
                Text("Try Again")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(GourneyColors.coral)
                    .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatCount(_ value: Int) -> String {
        if value >= 1000000 {
            return String(format: "%.1fM", Double(value) / 1000000)
        } else if value >= 10000 {
            return String(format: "%.1fK", Double(value) / 1000)
        }
        return "\(value)"
    }
}

// MARK: - Follow User Row

struct FollowUserRow: View {
    let user: FollowUserItem
    let isToggling: Bool
    let onFollowTap: () -> Void
    let onRowTap: () -> Void
    
    private var isOwnProfile: Bool {
        user.userId == AuthManager.shared.currentUser?.id
    }
    
    var body: some View {
        Button(action: onRowTap) {
            HStack(spacing: 12) {
                // Avatar
                AvatarView(url: user.userAvatarUrl, size: 52)
                
                // Name & Handle
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayNameOrHandle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("@\(user.userHandle)")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Follow Button (not shown for own profile)
                if !isOwnProfile {
                    followButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var followButton: some View {
        Button {
            onFollowTap()
        } label: {
            Group {
                if isToggling {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Text(user.isFollowing ? "Following" : "Follow")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(width: 100, height: 34)
            .background(GourneyColors.coral)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(isToggling)
    }
}

// MARK: - Preview

#Preview("Followers List") {
    FollowersFollowingListView(
        userId: "test-user-id",
        userHandle: "foodie_lover",
        initialTab: .followers,
        followerCount: 1234,
        followingCount: 567
    )
}

#Preview("Following List") {
    FollowersFollowingListView(
        userId: "test-user-id",
        userHandle: "foodie_lover",
        initialTab: .following,
        followerCount: 1234,
        followingCount: 567
    )
}
