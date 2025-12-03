// Views/Profile/ProfileView.swift
// User profile with visits grid and mini-map
// Production-ready with memory optimization
// ✅ NEW: Added navigation to Followers/Following list views

import SwiftUI
import MapKit

struct ProfileView: View {
    // For viewing other users' profiles
    var userHandle: String? = nil
    var userId: String? = nil
    
    @StateObject private var viewModel = ProfileViewModel()
    @ObservedObject private var authManager = AuthManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    @State private var showListsView = false
    @State private var showFollowers = false
    @State private var showFollowing = false
    @State private var avatarFrame: CGRect = .zero
    
    // Navigation path for programmatic navigation
    @State private var navigationPath = NavigationPath()
    
    private var isOwnProfile: Bool {
        userHandle == nil && userId == nil
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .top) {
                // Background
                backgroundColor.ignoresSafeArea()
                
                // Content
                VStack(spacing: 0) {
                    // Spacer for top bar height
                    Color.clear.frame(height: 52)
                    
                    if viewModel.isLoading && viewModel.profile == nil {
                        Spacer()
                        loadingView
                        Spacer()
                    } else if let error = viewModel.error, viewModel.profile == nil {
                        Spacer()
                        errorView(error)
                        Spacer()
                    } else if let profile = viewModel.profile {
                        profileContent(profile)
                    }
                }
                
                // Fixed Top Bar (always on top)
                topBar
            }
            .navigationBarHidden(true)
            .navigationDestination(for: FeedItem.self) { feedItem in
                FeedDetailView(feedItem: feedItem, feedViewModel: FeedViewModel())
            }
            .navigationDestination(for: String.self) { destination in
                // Handle both navigation strings and user IDs
                switch destination {
                case "editProfile":
                    EditProfileView()
                case "settings":
                    SettingsView()
                default:
                    // Assume it's a userId for profile navigation
                    ProfileView(userId: destination)
                }
            }
            // ✅ NEW: Navigation to Followers list
            .navigationDestination(isPresented: $showFollowers) {
                if let profile = viewModel.profile {
                    FollowersFollowingListView(
                        userId: profile.id,
                        userHandle: profile.handle,
                        initialTab: .followers,
                        followerCount: profile.followerCount,
                        followingCount: profile.followingCount
                    )
                }
            }
            // ✅ NEW: Navigation to Following list
            .navigationDestination(isPresented: $showFollowing) {
                if let profile = viewModel.profile {
                    FollowersFollowingListView(
                        userId: profile.id,
                        userHandle: profile.handle,
                        initialTab: .following,
                        followerCount: profile.followerCount,
                        followingCount: profile.followingCount
                    )
                }
            }
            .navigationDestination(isPresented: $showListsView) {
                ListsView()
            }
        }
        .onAppear {
            // Load profile normally - notifications handle updates
            if let handle = userHandle {
                viewModel.loadProfile(handle: handle)
            } else if let id = userId {
                viewModel.loadProfile(userId: id)
            } else {
                viewModel.loadOwnProfile()
            }
        }
        .onChange(of: authManager.currentUser?.avatarUrl) { _, _ in
            // Refresh own profile when user data changes (e.g., after EditProfile save)
            if isOwnProfile {
                viewModel.loadOwnProfile()
            }
        }
        .onChange(of: authManager.currentUser?.displayName) { _, _ in
            if isOwnProfile {
                viewModel.loadOwnProfile()
            }
        }
        .onChange(of: authManager.currentUser?.bio) { _, _ in
            if isOwnProfile {
                viewModel.loadOwnProfile()
            }
        }
        .onDisappear {
            // Only cleanup for memory management, don't reset data
            // This preserves data when navigating to detail views
            // Visit updates are handled via NotificationCenter
            viewModel.cleanup()
        }
        .onReceive(NavigationCoordinator.shared.$shouldPopProfileToRoot) { shouldPop in
            if shouldPop && isOwnProfile {
                navigationPath = NavigationPath()
            }
        }

    }
    
    // MARK: - Top Bar (Fixed at top) - Title Always Centered
    
    private var topBar: some View {
        VStack(spacing: 0) {
            ZStack {
                // Center: Username (always centered using ZStack)
                Text(viewModel.profile?.displayNameOrHandle ?? "Profile")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Left and Right buttons using HStack overlay
                HStack {
                    // Left: Back button (for other profiles only)
                    if !isOwnProfile {
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
                    } else {
                        // Invisible spacer to balance
                        Color.clear
                            .frame(width: 44, height: 44)
                            .padding(.leading, 4)
                    }
                    
                    Spacer()
                    
                    // Right: Settings (own profile only)
                    if isOwnProfile {
                        Button {
                            navigationPath.append("settings")
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 20))
                                .foregroundColor(.primary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .padding(.trailing, 4)
                    } else {
                        // Invisible spacer to balance
                        Color.clear
                            .frame(width: 44, height: 44)
                            .padding(.trailing, 4)
                    }
                }
            }
            .frame(height: 44)
            .padding(.top, 8)
            .background(backgroundColor)
        }
    }
    
    // MARK: - Profile Content
    
    private func profileContent(_ profile: UserProfile) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header Section (3-column layout)
                headerSection(profile)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                
                // Bio Section (centered, narrower width)
                if let bio = profile.bio, !bio.isEmpty {
                    bioSection(bio)
                        .padding(.horizontal, 32) // Narrower than header
                        .padding(.top, 12)
                }
                
                // Action Button
                actionButton(profile)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                
                // Tab Picker (DiscoverView style)
                tabPicker
                    .padding(.top, 20)
                
                // Tab Content (reduced gap, no bottom padding)
                tabContent
            }
            // No bottom padding - grid goes right to tab bar
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
    
    // MARK: - Header Section (3-Column Layout)
    // Left: pts (upper), lists + visits (lower)
    // Center: Avatar + Name + Handle
    // Right: following (upper), followers (lower)
    
    private func headerSection(_ profile: UserProfile) -> some View {
        HStack(spacing: 0) {
            // Left Column: Pts (upper), Lists + Visits (lower)
            VStack(spacing: 12) {
                // Pts - same font size as following/followers
                VStack(spacing: 2) {
                    Text(formatNumber(viewModel.displayPoints))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(GourneyColors.coral)
                    Text("pts")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                // Lists + Visits row - same font size as following/followers
                HStack(spacing: 16) {
                    Button { showListsView = true } label: {
                        statItem(value: profile.listCount, label: "Lists")
                    }
                    .buttonStyle(.plain)
                    
                    statItem(value: profile.visitCount, label: "Visits")
                }
            }
            .frame(maxWidth: .infinity)
            
            // Center Column: Avatar + Name + Handle
            VStack(spacing: 8) {
                // Avatar (larger, no border) - tappable for preview on own profile
                if isOwnProfile {
                    Button {
                        // Show avatar preview
                        if let avatarUrl = profile.avatarUrl {
                            AvatarPreviewState.shared.show(
                                image: nil,
                                imageUrl: avatarUrl,
                                sourceFrame: avatarFrame
                            )
                        }
                    } label: {
                        AvatarView(url: profile.avatarUrl, size: 80)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.onAppear {
                                        avatarFrame = geo.frame(in: .global)
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                } else {
                    AvatarView(url: profile.avatarUrl, size: 80)
                }
                
                // Handle (below avatar)
                Text("@\(profile.handle)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            // Right Column: Following (upper), Followers (lower)
            // MARK: - Feature Flag: View Others' Follow Lists
            // Set to `true` to allow viewing any user's followers/following
            // Set to `false` (or use `isOwnProfile`) to only allow viewing your own
            let canViewFollowLists = isOwnProfile // ← Change to `true` to enable for all profiles
            
            VStack(spacing: 12) {
                if canViewFollowLists {
                    Button { showFollowing = true } label: {
                        statItem(value: profile.followingCount, label: "Following")
                    }
                    .buttonStyle(.plain)
                    
                    Button { showFollowers = true } label: {
                        statItem(value: profile.followerCount, label: "Followers")
                    }
                    .buttonStyle(.plain)
                } else {
                    // Non-tappable stats for other users' profiles
                    statItem(value: profile.followingCount, label: "Following")
                    statItem(value: profile.followerCount, label: "Followers")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Stat Item
    
    private func statItem(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text(formatNumber(value))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Bio Section (Centered, truncated to 3 lines)
    
    private func bioSection(_ bio: String) -> some View {
        VStack(spacing: 4) {
            Text(bio)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(viewModel.isBioExpanded ? nil : 3)
            
            if bio.count > 100 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.isBioExpanded.toggle()
                    }
                } label: {
                    Text(viewModel.isBioExpanded ? "Less" : "More")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(GourneyColors.coral)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Action Button (Theme color for Edit Profile)
    
    private func actionButton(_ profile: UserProfile) -> some View {
        Group {
            if viewModel.isOwnProfile {
                Button {
                    navigationPath.append("editProfile")
                } label: {
                    Text("Edit Profile")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(GourneyColors.coral)
                        .cornerRadius(6)
                }
            } else {
                Button {
                    viewModel.toggleFollow()
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isTogglingFollow {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(viewModel.isFollowing ? GourneyColors.coral : .white)
                        }
                        
                        Text(viewModel.isFollowing ? "Following" : "Follow")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(viewModel.isFollowing ? GourneyColors.coral : .white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(
                        viewModel.isFollowing
                        ? Color(.systemGray5)
                        : GourneyColors.coral
                    )
                    .cornerRadius(6)
                }
                .disabled(viewModel.isTogglingFollow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    // MARK: - Tab Picker (DiscoverView Style with Underline)
    
    private var tabPicker: some View {
        HStack(spacing: 40) {
            // Visits Tab
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = 0
                }
            } label: {
                VStack(spacing: 6) {
                    Text("Visits")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(selectedTab == 0 ? GourneyColors.coral : .secondary)
                    
                    Rectangle()
                        .fill(selectedTab == 0 ? GourneyColors.coral : Color.clear)
                        .frame(height: 2)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 80)
            
            // Map Tab
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = 1
                }
            } label: {
                VStack(spacing: 6) {
                    Text("Map")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(selectedTab == 1 ? GourneyColors.coral : .secondary)
                    
                    Rectangle()
                        .fill(selectedTab == 1 ? GourneyColors.coral : Color.clear)
                        .frame(height: 2)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 80)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Tab Content (Reduced gap)
    
    private var tabContent: some View {
        Group {
            if selectedTab == 0 {
                visitsGrid
            } else {
                profileMapView
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Visits Grid (3 columns, 4:5 ratio)
    
    private var visitsGrid: some View {
        ZStack {
            if viewModel.isLoadingVisits && viewModel.visits.isEmpty {
                // Loading overlay - shared component
                CenteredLoadingView()
                    .frame(height: 300)
            } else if viewModel.visits.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "fork.knife.circle")
                        .font(.system(size: 40))
                        .foregroundColor(GourneyColors.coral.opacity(0.5))
                    Text("No visits yet")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(height: 200)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2)
                    ],
                    spacing: 2
                ) {
                    ForEach(Array(viewModel.visits.enumerated()), id: \.element.id) { index, visit in
                        ProfileVisitCard(visit: visit)
                            .aspectRatio(4/5, contentMode: .fill)
                            .onTapGesture {
                                // Convert to FeedItem and navigate
                                if let profile = viewModel.profile {
                                    let feedItem = visit.toFeedItem(user: profile)
                                    navigationPath.append(feedItem)
                                }
                            }
                            .onAppear {
                                // ✅ Trigger pagination when near the end
                                if index >= viewModel.visits.count - 3 {
                                    print("📜 [Profile] Near end, triggering pagination at index \(index)")
                                    viewModel.loadMoreVisitsIfNeeded(currentVisit: visit)
                                }
                            }
                    }
                    
                    // Pagination loading - shared skeleton cells
                    if viewModel.isLoadingVisits && !viewModel.visits.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            GridSkeletonCell(aspectRatio: 4/5)
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 100) // Space for tab bar
            }
        }
    }
    
    // MARK: - Map View
    
    private var profileMapView: some View {
        ProfileMapView(visits: viewModel.visits)
            .frame(height: 400)
            .cornerRadius(12)
            .padding(.horizontal, 16)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        LoadingSpinner()
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
                if let handle = userHandle {
                    viewModel.loadProfile(handle: handle)
                } else if let id = userId {
                    viewModel.loadProfile(userId: id)
                } else {
                    viewModel.loadOwnProfile()
                }
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
    
    private func formatNumber(_ value: Int) -> String {
        if value >= 1000000 {
            return String(format: "%.1fM", Double(value) / 1000000)
        } else if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000)
        }
        return "\(value)"
    }
}

#Preview {
    ProfileView()
}
