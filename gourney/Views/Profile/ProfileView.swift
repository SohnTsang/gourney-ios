// Views/Profile/ProfileView.swift
// User profile with visits grid, mini-map, and saved visits tab
// Production-ready with memory optimization
// ✅ NEW: Added Saved tab for own profile (bookmarked visits)
// ✅ FIX: Removed spacing between tabs and content

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
        .onReceive(NavigationCoordinator.shared.$popToRootTab) { tabIndex in
            if tabIndex == 4 && isOwnProfile {
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
                
                // Tab Content - ✅ REMOVED spacing
                tabContent
                
                // ✅ Pagination trigger - for visits or saved tab
                if selectedTab == 0 && viewModel.hasMoreVisits && !viewModel.isLoadingVisits && !viewModel.visits.isEmpty {
                    visitsPaginationTrigger
                }
                
                if selectedTab == 2 && viewModel.hasMoreSavedVisits && !viewModel.isLoadingSavedVisits && !viewModel.savedVisits.isEmpty {
                    savedVisitsPaginationTrigger
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .scrollIndicators(.hidden)
    }
    
    // MARK: - Pagination Triggers
    
    private var visitsPaginationTrigger: some View {
        GeometryReader { geo in
            Color.clear
                .onChange(of: geo.frame(in: .global).minY) { _, minY in
                    let screenHeight = UIScreen.main.bounds.height
                    if minY < screenHeight && minY > 0 {
                        print("📜 [Profile] 🔥 Bottom trigger visible (y: \(Int(minY))) - loading more visits")
                        viewModel.loadMoreVisits()
                    }
                }
        }
        .frame(height: 50)
    }
    
    private var savedVisitsPaginationTrigger: some View {
        GeometryReader { geo in
            Color.clear
                .onChange(of: geo.frame(in: .global).minY) { _, minY in
                    let screenHeight = UIScreen.main.bounds.height
                    if minY < screenHeight && minY > 0 {
                        print("📜 [Profile] 🔥 Bottom trigger visible (y: \(Int(minY))) - loading more saved visits")
                        viewModel.loadMoreSavedVisits()
                    }
                }
        }
        .frame(height: 50)
    }
    
    // MARK: - Header Section (3-Column Layout)
    // Left: pts (upper), lists + visits (lower)
    // Center: Avatar + Name + Handle
    // Right: following (upper), followers (lower)
    
    private func headerSection(_ profile: UserProfile) -> some View {
        HStack(spacing: 0) {
            // Left Column: Pts (upper), Lists + Visits (lower)
            VStack(spacing: 16) {
                // Points
                VStack(spacing: 2) {
                    Text("\(profile.points)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    Text("pts")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                // Lists + Visits Row
                HStack(spacing: 20) {
                    // Lists (tappable - only for own profile)
                    if viewModel.isOwnProfile {
                        Button {
                            showListsView = true
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(profile.listCount)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("lists")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Non-tappable for other profiles
                        VStack(spacing: 2) {
                            Text("\(profile.listCount)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("lists")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Visits (non-tappable for now)
                    VStack(spacing: 2) {
                        Text("\(profile.visitCount)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("visits")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            // Center Column: Avatar + Name + Handle
            VStack(spacing: 8) {
                // Avatar with tap gesture
                AvatarView(
                    url: profile.avatarUrl,
                    size: 80
                )
                .onTapGesture {
                    if let urlString = profile.avatarUrl, !urlString.isEmpty {
                        // Get the avatar frame for animation
                        AvatarPreviewState.shared.show(
                            image: nil,
                            imageUrl: urlString,
                            sourceFrame: avatarFrame
                        )
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            avatarFrame = geo.frame(in: .global)
                        }
                    }
                )
                
                // Name
                Text(profile.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Handle
                Text("@\(profile.handle)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            // Right Column: Following (upper), Followers (lower)
            VStack(spacing: 16) {
                // Following (tappable)
                Button {
                    showFollowing = true
                } label: {
                    VStack(spacing: 2) {
                        Text(formatNumber(profile.followingCount))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        Text("following")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                // Followers (tappable)
                Button {
                    showFollowers = true
                } label: {
                    VStack(spacing: 2) {
                        Text(formatNumber(profile.followerCount))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("followers")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Bio Section (Centered, Expandable)
    
    private func bioSection(_ bio: String) -> some View {
        VStack(spacing: 4) {
            Text(bio)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(viewModel.isBioExpanded ? nil : 2)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isBioExpanded)
            
            // Show "more" button if bio is truncated
            if bio.count > 80 {
                Button {
                    viewModel.isBioExpanded.toggle()
                } label: {
                    Text(viewModel.isBioExpanded ? "less" : "more")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Action Button (Edit Profile or Follow)
    
    private func actionButton(_ profile: UserProfile) -> some View {
        HStack(spacing: 12) {
            if isOwnProfile {
                Button {
                    navigationPath.append("editProfile")
                } label: {
                    Text("Edit Profile")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(GourneyColors.coral)
                        .cornerRadius(6)
                }
            } else {
                Button {
                    viewModel.toggleFollow()
                } label: {
                    Text(viewModel.isFollowing ? "Following" : "Follow")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(
                            viewModel.isFollowing
                            ? Color(.systemGray3)
                            : GourneyColors.coral
                        )
                        .cornerRadius(6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    // MARK: - Tab Picker (Dynamic: 2 tabs for others, 3 tabs for own profile)
    
    private var tabPicker: some View {
        HStack(spacing: isOwnProfile ? 24 : 40) {
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
            .frame(width: 60)
            
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
            .frame(width: 60)
            
            // Saved Tab (own profile only)
            if isOwnProfile {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = 2
                    }
                    // Load saved visits when tab is first selected
                    viewModel.loadSavedVisits()
                } label: {
                    VStack(spacing: 6) {
                        Text("Saved")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(selectedTab == 2 ? GourneyColors.coral : .secondary)
                        
                        Rectangle()
                            .fill(selectedTab == 2 ? GourneyColors.coral : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 60)
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Tab Content (✅ No top padding)
    
    private var tabContent: some View {
        Group {
            if selectedTab == 0 {
                visitsGrid
            } else if selectedTab == 1 {
                profileMapView
            } else if selectedTab == 2 && isOwnProfile {
                savedVisitsGrid
            }
        }
    }
    
    // MARK: - Visits Grid (3 columns, 4:5 ratio) - Instagram Style
    
    @ViewBuilder
    private var visitsGrid: some View {
        if viewModel.isLoadingVisits && viewModel.visits.isEmpty {
            // Initial loading state
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
            VStack(spacing: 0) {
                // Grid content
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2)
                    ],
                    spacing: 2
                ) {
                    // Existing visits
                    ForEach(viewModel.visits) { visit in
                        ProfileVisitCard(visit: visit)
                            .aspectRatio(4/5, contentMode: .fill)
                            .onTapGesture {
                                if let profile = viewModel.profile {
                                    let feedItem = visit.toFeedItem(user: profile)
                                    navigationPath.append(feedItem)
                                }
                            }
                    }
                }
                .padding(.horizontal, 2)
                
                // ✅ FeedView-style: Centered loading spinner during pagination
                if viewModel.isLoadingVisits {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(GourneyColors.coral)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            }
        }
    }
    
    // MARK: - Saved Visits Grid (own profile only)
    
    @ViewBuilder
    private var savedVisitsGrid: some View {
        if viewModel.isLoadingSavedVisits && viewModel.savedVisits.isEmpty {
            // Initial loading state
            CenteredLoadingView()
                .frame(height: 300)
        } else if viewModel.savedVisits.isEmpty {
            // Empty state
            VStack(spacing: 12) {
                Image(systemName: "bookmark")
                    .font(.system(size: 40))
                    .foregroundColor(GourneyColors.coral.opacity(0.5))
                Text("No saved visits")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                Text("Bookmark visits to save them here")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .frame(height: 200)
        } else {
            VStack(spacing: 0) {
                // Grid content - reuse ProfileVisitCard via conversion
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2)
                    ],
                    spacing: 2
                ) {
                    ForEach(viewModel.savedVisits) { savedVisit in
                        ProfileVisitCard(visit: savedVisit.toProfileVisit())
                            .aspectRatio(4/5, contentMode: .fill)
                            .overlay(alignment: .topLeading) {
                                // Small user avatar indicator
                                if let avatarUrl = savedVisit.user?.avatarUrl {
                                    AvatarView(url: avatarUrl, size: 20)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 1.5)
                                        )
                                        .padding(4)
                                }
                            }
                            .onTapGesture {
                                let feedItem = savedVisit.toFeedItem()
                                navigationPath.append(feedItem)
                            }
                    }
                }
                .padding(.horizontal, 2)
                
                // Loading spinner during pagination
                if viewModel.isLoadingSavedVisits {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(GourneyColors.coral)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            }
        }
    }
    
    // MARK: - Map View
    
    private var profileMapView: some View {
        ProfileMapView(visits: viewModel.visits)
            .frame(height: 400)
            .cornerRadius(12)
            .padding(.horizontal, 16)
            // No bottom padding needed - ScrollView contentMargins handles tab bar
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
