// Views/Feed/FeedView.swift
// "For You" feed with Gourney branding, search, and infinite scroll
// NavigationStack with push to FeedDetailView on comment tap
// Profile navigation via NavigationCoordinator (standard NavigationStack push like ListsView)
// ✅ Search overlay with Instagram-style fade transition

import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @ObservedObject private var navigator = NavigationCoordinator.shared
    @State private var showSearch = false
    @State private var showSaveToList = false
    @State private var selectedItem: FeedItem?
    @State private var selectedPlaceItem: FeedItem?
    @State private var showAddVisitFromPlace = false
    @State private var placeForAddVisit: FeedItem?
    @State private var showMenuForId: String?
    @State private var navigateToDetail: FeedItem?
    
    // Edit/Delete states
    @State private var itemToEdit: FeedItem?
    @State private var showDeleteVisitAlert = false
    @State private var itemToDelete: FeedItem?
    @State private var isDeletingVisit = false
    
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
        ZStack {
            // Main Feed Content
            mainContent
            
            // Search Overlay with fade transition
            if showSearch {
                FeedSearchOverlay(isPresented: $showSearch)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSearch)
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
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
            .navigationDestination(item: $navigator.navigateToProfileUserId) { userId in
                ProfileView(userId: userId)
            }
            .navigationDestination(item: $itemToEdit) { item in
                EditVisitView(feedItem: item) { updatedItem in
                    viewModel.updateItem(updatedItem)
                }
            }
        }
        .onAppear {
            viewModel.loadFeed()
        }
        // ✅ Pop to root when same tab is tapped
        .onReceive(navigator.$popToRootTab) { tabIndex in
            if tabIndex == 0 {
                navigateToDetail = nil
                itemToEdit = nil
                showSearch = false
            }
        }
        .sheet(isPresented: showMenuSheet) {
            if let item = menuItem {
                FeedMenuSheet(
                    item: item,
                    onViewPlace: {
                        selectedPlaceItem = item
                    },
                    onSaveToList: {
                        selectedItem = item
                        showSaveToList = true
                    },
                    onReport: { },
                    onEdit: {
                        itemToEdit = item
                    },
                    onDelete: {
                        itemToDelete = item
                        showDeleteVisitAlert = true
                    }
                )
            }
        }
        .sheet(isPresented: $showSaveToList) {
            if let item = selectedItem {
                SaveToListSheet(placeId: item.place.id, placeName: item.place.displayName)
            }
        }
        .sheet(item: $selectedPlaceItem) { item in
            PlaceDetailSheet(
                placeId: item.place.id,
                displayName: item.place.displayName,
                lat: 0,
                lng: 0,
                formattedAddress: nil,
                phoneNumber: nil,
                website: nil,
                photoUrls: nil,
                googlePlaceId: nil,
                primaryButtonTitle: "Add Visit",
                primaryButtonAction: {
                    placeForAddVisit = item
                    selectedPlaceItem = nil
                },
                onDismiss: {
                    selectedPlaceItem = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .onChange(of: selectedPlaceItem) { oldValue, newValue in
            if newValue == nil && placeForAddVisit != nil {
                showAddVisitFromPlace = true
            }
        }
        .fullScreenCover(isPresented: $showAddVisitFromPlace) {
            if let item = placeForAddVisit {
                AddVisitView(
                    prefilledPlace: PlaceSearchResult(
                        source: .google,
                        googlePlaceId: nil,
                        applePlaceId: nil,
                        nameEn: item.place.nameEn,
                        nameJa: item.place.nameJa,
                        nameZh: item.place.nameZh,
                        lat: 0,
                        lng: 0,
                        formattedAddress: nil,
                        categories: item.place.categories,
                        photoUrls: nil,
                        existsInDb: true,
                        dbPlaceId: item.place.id,
                        appleFullData: nil
                    ),
                    showBackButton: true,
                    onVisitPosted: { _ in
                        showAddVisitFromPlace = false
                        placeForAddVisit = nil
                        Task { await viewModel.refresh() }
                    }
                )
            }
        }
        .onChange(of: showAddVisitFromPlace) { _, newValue in
            if !newValue {
                placeForAddVisit = nil
            }
        }
        .customDeleteAlert(
            isPresented: $showDeleteVisitAlert,
            title: "Delete Visit",
            message: "Are you sure you want to delete this visit? This cannot be undone.",
            confirmTitle: "Delete",
            onConfirm: {
                if let item = itemToDelete {
                    deleteVisit(item)
                }
            }
        )
        .loadingOverlay(isShowing: isDeletingVisit, message: "Deleting...")
    }
    
    // MARK: - Delete Visit
    
    private func deleteVisit(_ item: FeedItem) {
        isDeletingVisit = true
        
        Task { @MainActor in
            do {
                let path = "/functions/v1/visits-delete?visit_id=\(item.id)"
                print("🗑️ [Visit] Deleting: \(item.id)")
                
                let _: EmptyResponse = try await SupabaseClient.shared.delete(
                    path: path,
                    requiresAuth: true
                )
                
                print("✅ [Visit] Deleted successfully")
                
                VisitUpdateService.shared.notifyVisitDeleted(visitId: item.id)
                viewModel.removeVisit(id: item.id)
                
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                
                itemToDelete = nil
                isDeletingVisit = false
                
            } catch {
                print("❌ [Visit] Delete error: \(error)")
                isDeletingVisit = false
                itemToDelete = nil
                
                UINotificationFeedbackGenerator().notificationOccurred(.error)
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
        SearchBarButton(placeholder: "Search places, users") {
            showSearch = true
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                        onPlaceTap: {
                            selectedPlaceItem = item
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
        ) {
            showSearch = true
        }
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
