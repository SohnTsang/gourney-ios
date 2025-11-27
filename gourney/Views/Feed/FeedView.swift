// Views/Feed/FeedView.swift
// "For You" feed with Gourney branding, search, and infinite scroll
// NavigationStack with push to FeedDetailView on comment tap

import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var showSearch = false
    @State private var showSaveToList = false
    @State private var selectedItem: FeedItem?
    @State private var showUserProfile = false
    @State private var selectedUserId: String?
    @State private var showPlaceDetail = false
    @State private var selectedPlaceId: String?
    @State private var showMenuForId: String?
    @State private var navigateToDetail: FeedItem?
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var showMenuSheet: Binding<Bool> {
        Binding(
            get: { showMenuForId != nil },
            set: { if !$0 { showMenuForId = nil } }
        )
    }
    
    private var menuItem: FeedItem? {
        guard let id = showMenuForId else { return nil }
        return viewModel.items.first { $0.id == id }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerView
                searchBarButton
                
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { _ in
                                FeedCardSkeleton()
                                    .padding(.bottom, 8)
                            }
                        }
                    }
                } else if let error = viewModel.error, viewModel.items.isEmpty {
                    ErrorStateView(message: error) {
                        Task { await viewModel.refresh() }
                    }
                } else if viewModel.items.isEmpty {
                    emptyStateView
                } else {
                    feedScrollView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
            .navigationDestination(item: $navigateToDetail) { item in
                FeedDetailView(feedItem: item, feedViewModel: viewModel)
            }
        }
        .onAppear {
            viewModel.loadFeed()
        }
        .sheet(isPresented: showMenuSheet) {
            if let item = menuItem {
                FeedMenuSheet(
                    item: item,
                    onViewProfile: {
                        selectedUserId = item.user.id
                        showUserProfile = true
                    },
                    onViewPlace: {
                        selectedPlaceId = item.place.id
                        showPlaceDetail = true
                    },
                    onSaveToList: {
                        selectedItem = item
                        showSaveToList = true
                    },
                    onReport: { }
                )
            }
        }
        .sheet(isPresented: $showSaveToList) {
            if let item = selectedItem {
                SaveToListSheet(placeId: item.place.id, placeName: item.place.displayName)
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Spacer()
            
            VStack(spacing: 0) {
                Text("Gourney")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("For You")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .overlay(alignment: .trailing) {
            Button { } label: {
                Image(systemName: "bell")
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
            }
            .padding(.trailing, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
    
    // MARK: - Search Bar Button
    
    private var searchBarButton: some View {
        Button {
            showSearch = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                
                Text("Search places, users...")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
    
    // MARK: - Feed Scroll View
    
    private var feedScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.items) { item in
                    FeedCardView(
                        item: item,
                        onLikeTap: { viewModel.toggleLike(for: item) },
                        onCommentTap: { navigateToDetail = item },
                        onSaveTap: {
                            selectedItem = item
                            showSaveToList = true
                        },
                        onShareTap: { shareItem(item) },
                        onUserTap: {
                            selectedUserId = item.user.id
                            showUserProfile = true
                        },
                        onPlaceTap: {
                            selectedPlaceId = item.place.id
                            showPlaceDetail = true
                        },
                        showMenuForId: $showMenuForId
                    )
                    .onAppear {
                        viewModel.loadMoreIfNeeded(currentItem: item)
                    }
                }
                
                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView().tint(GourneyColors.coral)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
                
                if viewModel.showAllCaughtUp {
                    AllCaughtUpView()
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
        EmptyStateView(
            icon: "fork.knife.circle",
            title: "Welcome to Gourney!",
            message: "Follow friends to see their restaurant visits, or discover new places from the community.",
            actionTitle: "Find Friends"
        ) { }
    }
    
    // MARK: - Share
    
    private func shareItem(_ item: FeedItem) {
        let text = "\(item.user.displayNameOrHandle) visited \(item.place.displayName)"
        let url = URL(string: "https://gourney.app/visit/\(item.id)")
        
        var items: [Any] = [text]
        if let url = url { items.append(url) }
        
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Save To List Sheet

struct SaveToListSheet: View {
    let placeId: String
    let placeName: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Text("Save \(placeName) to list")
                .navigationTitle("Save to List")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .foregroundColor(GourneyColors.coral)
                    }
                }
        }
    }
}

#Preview {
    FeedView()
}
