// Views/Feed/FeedSearchOverlay.swift
// Instagram-style search overlay for FeedView
// 2 tabs: Users, Places
// Reuses SearchResultRow from SearchPlaceOverlay for Places
// Stores up to 10 recent searches
// ✅ Fixed: Fade transition, proper search bar styling, no auto-search, optimized

import SwiftUI
import Combine

struct FeedSearchOverlay: View {
    @Binding var isPresented: Bool
    
    @StateObject private var viewModel = FeedSearchViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool
    
    // Place detail sheet
    @State private var selectedPlace: PlaceSearchResult?
    @State private var showPlaceDetail = false
    
    // Profile navigation
    @State private var selectedUserId: String?
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                searchBar
                
                Divider()
                
                // Tab Picker (no divider below)
                tabPicker
                
                // Content with top padding
                contentView
                    .padding(.top, 16)
            }
            .background(backgroundColor.ignoresSafeArea())
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedUserId) { userId in
                ProfileView(userId: userId)
            }
        }
        .sheet(isPresented: $showPlaceDetail) {
            if let place = selectedPlace {
                PlaceDetailSheet(
                    placeId: place.dbPlaceId ?? "",
                    displayName: place.displayName,
                    lat: place.lat,
                    lng: place.lng,
                    formattedAddress: place.formattedAddress,
                    phoneNumber: place.appleFullData?.phone,
                    website: place.appleFullData?.website,
                    photoUrls: place.photoUrls,
                    googlePlaceId: place.googlePlaceId,
                    primaryButtonTitle: "Add Visit",
                    primaryButtonAction: {
                        showPlaceDetail = false
                    },
                    onDismiss: {
                        showPlaceDetail = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
    
    // MARK: - Search Bar (Matches SharedComponents SearchTextField exactly)
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            // Back button
            Button {
                isPresented = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            
            // Search field - matches SearchTextField from SharedComponents exactly
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                
                ZStack(alignment: .leading) {
                    if viewModel.searchQuery.isEmpty {
                        Text("Search")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    
                    TextField("", text: $viewModel.searchQuery)
                        .font(.system(size: 15))
                        .focused($isFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit {
                            performSearch()
                        }
                }
                
                Spacer()
                
                // Clear and Search buttons (only show when text exists)
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.clearQuery()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        performSearch()
                    } label: {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(GourneyColors.coral)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(backgroundColor)
    }
    
    private func performSearch() {
        let trimmed = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        
        isFocused = false
        viewModel.addToRecentSearches(query: trimmed)
        viewModel.performSearch()
    }
    
    // MARK: - Tab Picker (Left-aligned, selected text = coral, no divider)
    
    private var tabPicker: some View {
        HStack(spacing: 24) {
            ForEach(FeedSearchTab.allCases) { tab in
                Button {
                    guard viewModel.selectedTab != tab else { return }
                    viewModel.selectedTab = tab
                    
                    // Re-search if query exists
                    let trimmed = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count >= 2 {
                        viewModel.performSearch()
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(tab.rawValue)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(viewModel.selectedTab == tab ? GourneyColors.coral : .secondary)
                        
                        Rectangle()
                            .fill(viewModel.selectedTab == tab ? GourneyColors.coral : Color.clear)
                            .frame(height: 2)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .background(backgroundColor)
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        let hasQuery = !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isLoading = viewModel.selectedTab == .users ? viewModel.isLoadingUsers : viewModel.isLoadingPlaces
        let hasResults = viewModel.selectedTab == .users ? !viewModel.userResults.isEmpty : !viewModel.placeResults.isEmpty
        
        if !hasQuery && !hasResults && !isLoading {
            recentSearchesView
        } else {
            switch viewModel.selectedTab {
            case .users:
                userResultsView
            case .places:
                placeResultsView
            }
        }
    }
    
    // MARK: - Recent Searches View
    
    private var recentSearchesView: some View {
        Group {
            if viewModel.recentSearches.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Search for users or places")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        HStack {
                            Text("Recent")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button {
                                viewModel.clearAllRecentSearches()
                            } label: {
                                Text("Clear All")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(GourneyColors.coral)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        
                        ForEach(viewModel.recentSearches) { item in
                            FeedRecentSearchRow(
                                item: item,
                                onTap: { handleRecentSearchTap(item) },
                                onRemove: { viewModel.removeRecentSearch(item) }
                            )
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
        }
    }
    
    private func handleRecentSearchTap(_ item: RecentSearchData) {
        switch item.type {
        case .query:
            viewModel.searchQuery = item.query
            viewModel.performSearch()
            
        case .user:
            if let userId = item.userId {
                if userId == AuthManager.shared.currentUser?.id {
                    NavigationCoordinator.shared.switchToProfileTab()
                    isPresented = false
                } else {
                    selectedUserId = userId
                }
            }
            
        case .place:
            viewModel.searchQuery = item.query
            viewModel.selectedTab = .places
            viewModel.performSearch()
        }
    }
    
    // MARK: - User Results View
    
    private var userResultsView: some View {
        Group {
            if viewModel.isLoadingUsers {
                loadingView
            } else if let error = viewModel.userSearchError, viewModel.userResults.isEmpty {
                errorView(error)
            } else if viewModel.userResults.isEmpty && !viewModel.searchQuery.isEmpty {
                emptyResultsView(type: "users")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.userResults) { user in
                            UserSearchRow(
                                user: user,
                                onTap: {
                                    viewModel.addToRecentSearches(user: user)
                                    if user.id == AuthManager.shared.currentUser?.id {
                                        NavigationCoordinator.shared.switchToProfileTab()
                                        isPresented = false
                                    } else {
                                        selectedUserId = user.id
                                    }
                                }
                            )
                            
                            if user.id != viewModel.userResults.last?.id {
                                Divider()
                                    .padding(.leading, 76)
                            }
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
        }
    }
    
    // MARK: - Place Results View
    
    private var placeResultsView: some View {
        Group {
            if viewModel.isLoadingPlaces {
                loadingView
            } else if let error = viewModel.placeSearchError, viewModel.placeResults.isEmpty {
                errorView(error)
            } else if viewModel.placeResults.isEmpty && !viewModel.searchQuery.isEmpty {
                emptyResultsView(type: "places")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.placeResults) { place in
                            SearchResultRow(result: place)
                                .onTapGesture {
                                    viewModel.addToRecentSearches(place: place)
                                    selectedPlace = place
                                    showPlaceDetail = true
                                }
                            
                            if place.id != viewModel.placeResults.last?.id {
                                Divider()
                                    .padding(.leading, 76)
                            }
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .tint(GourneyColors.coral)
            Text("Searching...")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    // MARK: - Empty Results View
    
    private func emptyResultsView(type: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No \(type) found")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            Text("Try a different search term")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 48))
                .foregroundColor(GourneyColors.coral.opacity(0.5))
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            Button {
                viewModel.performSearch()
            } label: {
                Text("Try Again")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(GourneyColors.coral)
                    .cornerRadius(8)
            }
            Spacer()
        }
    }
}

// MARK: - User Search Row (No chevron, clean design)

struct UserSearchRow: View {
    let user: UserSearchResult
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AvatarView(url: user.avatarUrl, size: 52)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayNameOrHandle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text("@\(user.handle)")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        if user.isFollowing == true {
                            Text("·")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            
                            Text("Following")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent Search Row

struct FeedRecentSearchRow: View {
    let item: RecentSearchData
    let onTap: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch item.type {
                case .query:
                    Image(systemName: "clock")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                        .frame(width: 40, height: 40)
                    
                case .user:
                    AvatarView(url: item.userAvatarUrl, size: 40)
                    
                case .place:
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(GourneyColors.coral)
                        .frame(width: 40, height: 40)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                switch item.type {
                case .query:
                    Text(item.query)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                case .user:
                    Text(item.userDisplayName ?? item.userHandle ?? item.query)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let handle = item.userHandle {
                        Text("@\(handle)")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                case .place:
                    Text(item.placeName ?? item.query)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let address = item.placeAddress {
                        Text(address)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Preview

#Preview("Feed Search Overlay") {
    FeedSearchOverlay(isPresented: .constant(true))
}
