// Views/Profile/ProfileView.swift
// User profile with visits grid and mini-map
// Production-ready with memory optimization
// FIX: Bio centered/truncated, consistent stat font sizes

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
                switch destination {
                case "editProfile":
                    EditProfileView()
                case "settings":
                    SettingsView()
                default:
                    EmptyView()
                }
            }
        }
        .sheet(isPresented: $showListsView) {
            ListsView()
        }
        .onAppear {
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
            // Clear visits when leaving to prevent flash on return
            viewModel.reset()
        }
    }
    
    // MARK: - Top Bar (Fixed at top)
    
    private var topBar: some View {
        VStack(spacing: 0) {
            HStack {
                // Left: Back button (for other profiles only)
                if !isOwnProfile {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.leading, 16)
                } else {
                    Spacer().frame(width: 50)
                }
                
                Spacer()
                
                // Center: Username
                Text(viewModel.profile?.displayNameOrHandle ?? "Profile")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Right: Settings (own profile only)
                if isOwnProfile {
                    Button {
                        navigationPath.append("settings")
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20))
                            .foregroundColor(.primary)
                    }
                    .padding(.trailing, 16)
                } else {
                    Spacer().frame(width: 50)
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
                AvatarView(url: profile.avatarUrl, size: 72)
                    .background(
                        GeometryReader { geo in
                            Color.clear.onAppear {
                                avatarFrame = geo.frame(in: .global)
                            }
                            .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                avatarFrame = newFrame
                            }
                        }
                    )
                    .onLongPressGesture(minimumDuration: 0.3) {
                        if profile.avatarUrl != nil {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                            AvatarPreviewState.shared.show(
                                image: nil,
                                imageUrl: profile.avatarUrl,
                                sourceFrame: avatarFrame
                            )
                        }
                    }
                
                VStack(spacing: 2) {
                    Text(profile.displayNameOrHandle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("@\(profile.handle)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            
            // Right Column: Following (upper), Followers (lower)
            VStack(spacing: 12) {
                Button { showFollowing = true } label: {
                    statItem(value: profile.followingCount, label: "Following")
                }
                .buttonStyle(.plain)
                
                Button { showFollowers = true } label: {
                    statItem(value: profile.followerCount, label: "Followers")
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Stat Item (Consistent font size for all stats)
    
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
    
    // MARK: - Bio Section (Centered, 2-line truncation with "view more")
    
    private func bioSection(_ bio: String) -> some View {
        VStack(spacing: 4) {
            if viewModel.isBioExpanded {
                // Expanded: show full bio
                Text(bio)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Collapsed: 2 lines with "view more" inline
                Text(bio)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.tail)
                
                // Show "view more" if bio is likely truncated (rough heuristic)
                if bio.count > 80 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.isBioExpanded = true
                        }
                    } label: {
                        Text("view more")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(GourneyColors.coral)
                    }
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
                    ForEach(viewModel.visits) { visit in
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
                                viewModel.loadMoreVisitsIfNeeded(currentVisit: visit)
                            }
                    }
                    
                    // Pagination loading - shared skeleton cells
                    if viewModel.isLoadingVisits {
                        ForEach(0..<3, id: \.self) { _ in
                            GridSkeletonCell(aspectRatio: 4/5)
                        }
                    }
                }
                .padding(.horizontal, 2)
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
