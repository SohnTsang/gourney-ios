// Views/Lists/ListDetailView.swift
// Redesigned with DetailTopBar + slide-up menu for owner actions
// Consistent heart icon design matching FeedCardView

import SwiftUI
import PhotosUI
import Combine

struct ListDetailView: View {
    @State var list: RestaurantList
    let onListUpdated: ((String, Int) -> Void)?
    let isReadOnly: Bool
    let ownerHandle: String?
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = ListDetailViewModel()
    @StateObject private var locationManager = LocationManager.shared
    @State private var showAddPlace = false
    @State private var showSettings = false
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @State private var showMenu = false
    @State private var selectedPlace: Place?
    @State private var showPlaceDetail = false
    @State private var showAddVisitFromDetail = false
    @State private var pendingAddVisit = false
    @State private var refreshTrigger = UUID()
    @State private var selectedCoverPhoto: PhotosPickerItem?
    @State private var isUploadingCover = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDefaultList: Bool {
        let wantToTryTitle = NSLocalizedString("lists.default.want_to_try", comment: "")
        let favoritesTitle = NSLocalizedString("lists.default.favorites", comment: "")
        return list.title == wantToTryTitle || list.title == favoritesTitle
    }
    
    init(list: RestaurantList, isReadOnly: Bool = false, ownerHandle: String? = nil, onListUpdated: ((String, Int) -> Void)? = nil) {
        self._list = State(initialValue: list)
        self.isReadOnly = isReadOnly
        self.ownerHandle = ownerHandle
        self.onListUpdated = onListUpdated
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // DetailTopBar - show 3 dots only for owner
            ListDetailTopBar(
                title: list.title,
                subtitle: isReadOnly ? ownerHandle.map { "@\($0)" } : nil,
                showMenu: !isReadOnly,
                onBack: { dismiss() },
                onMenu: { showMenu = true }
            )
            
            // Content
            ZStack {
                Color(colorScheme == .dark ? .black : .systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Cover Image
                        CoverImageView(
                            coverUrl: list.coverPhotoUrl,
                            isReadOnly: isReadOnly,
                            onUpload: { image in
                                if let newUrl = await viewModel.uploadCover(listId: list.id, image: image) {
                                    onListUpdated?(list.id, list.itemCount ?? 0)
                                    return newUrl
                                }
                                return nil
                            }
                        )
                        
                        // List Info Section
                        VStack(spacing: 12) {
                            // Stats Row - Places on left, Likes/Button on right
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(GourneyColors.coral)
                                    Text("\(viewModel.places.count)")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text("places")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if list.visibility != "private" {
                                    if isReadOnly {
                                        // Visitor: tappable heart button with animation
                                        Button {
                                            viewModel.toggleLike(listId: list.id)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(viewModel.isLiked ? GourneyColors.coral : .primary)
                                                    .scaleEffect(viewModel.likeScale)
                                                
                                                if viewModel.likesCount > 0 {
                                                    Text("\(viewModel.likesCount)")
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .frame(minWidth: 44, minHeight: 44)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        // Owner: always filled heart with count
                                        HStack(spacing: 4) {
                                            Image(systemName: "heart.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(GourneyColors.coral)
                                            
                                            Text("\(viewModel.likesCount)")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.secondary)
                                        }
                                        .frame(minWidth: 44, minHeight: 44)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
                        
                        // Places List
                        if viewModel.places.isEmpty && !viewModel.isLoading {
                            EmptyPlacesView(showAddPlace: $showAddPlace, isReadOnly: isReadOnly)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.places) { item in
                                    if !isReadOnly {
                                        SwipeToDeleteRow(
                                            item: item,
                                            distance: item.place.map { locationManager.formattedDistance(from: $0.coordinate) } ?? nil,
                                            onTap: {
                                                if let place = item.place {
                                                    selectedPlace = place
                                                    showPlaceDetail = true
                                                }
                                            },
                                            onDelete: {
                                                guard let placeId = item.place?.id else { return }
                                                
                                                Task {
                                                    await viewModel.removePlace(
                                                        listId: list.id,
                                                        itemId: item.id,
                                                        placeId: placeId,
                                                        onSuccess: { newCount in
                                                            list.itemCount = newCount
                                                            onListUpdated?(list.id, newCount)
                                                        }
                                                    )
                                                }
                                            }
                                        )
                                        .transition(.asymmetric(
                                            insertion: .opacity,
                                            removal: .move(edge: .leading).combined(with: .opacity)
                                        ))
                                    } else {
                                        PlaceRowView(
                                            item: PlaceRowItem(from: item),
                                            distance: item.place.map { locationManager.formattedDistance(from: $0.coordinate) } ?? nil,
                                            showRemoveButton: false,
                                            onRemove: nil
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if let place = item.place {
                                                selectedPlace = place
                                                showPlaceDetail = true
                                            }
                                        }
                                    }
                                    
                                    if item.id != viewModel.places.last?.id {
                                        Divider()
                                            .padding(.leading, 90)
                                    }
                                }
                            }
                            .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
                            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: viewModel.places.count)
                        }
                    }
                }
                
                if viewModel.isLoading {
                    ProgressView()
                        .tint(GourneyColors.coral)
                }
            }
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        .navigationBarHidden(true)
        .task {
            await viewModel.loadPlaces(listId: list.id)
        }
        .sheet(isPresented: $showAddPlace) {
            AddPlaceToListSheet(listId: list.id, viewModel: viewModel)
        }
        .sheet(isPresented: $showPlaceDetail) {
            if let place = selectedPlace {
                PlaceDetailSheet(
                    placeId: place.id,
                    displayName: place.displayName,
                    lat: place.lat,
                    lng: place.lng,
                    formattedAddress: place.formattedAddress,
                    phoneNumber: place.phone,
                    website: place.website,
                    photoUrls: place.photoUrls,
                    googlePlaceId: place.googlePlaceId,
                    primaryButtonTitle: "Add Visit",
                    primaryButtonAction: {
                        // Set flag and dismiss sheet
                        pendingAddVisit = true
                        showPlaceDetail = false
                    },
                    onDismiss: {
                        showPlaceDetail = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .id(refreshTrigger)
            }
        }
        .onChange(of: showPlaceDetail) { _, newValue in
            // When sheet dismisses and we have pending AddVisit
            if !newValue && pendingAddVisit {
                pendingAddVisit = false
                showAddVisitFromDetail = true
            }
        }
        .fullScreenCover(isPresented: $showAddVisitFromDetail) {
            if let place = selectedPlace {
                AddVisitView(
                    prefilledPlace: PlaceSearchResult(from: place),
                    showBackButton: true,
                    onVisitPosted: { placeId in
                        showAddVisitFromDetail = false
                        Task {
                            await viewModel.loadPlaces(listId: list.id)
                            await MainActor.run {
                                refreshTrigger = UUID()
                            }
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showMenu) {
            ListDetailMenuSheet(
                isDefaultList: isDefaultList,
                onSettings: {
                    showSettings = true
                },
                onDelete: {
                    showDeleteAlert = true
                }
            )
        }
        .overlay {
            if showSettings {
                ListSettingsSheet(
                    list: list,
                    isPresented: $showSettings,
                    onSave: { updatedList in
                        list = updatedList
                        onListUpdated?(list.id, list.itemCount ?? 0)
                    }
                )
            }
        }
        .customDeleteAlert(
            isPresented: $showDeleteAlert,
            title: "Delete List",
            message: "This action cannot be undone.",
            confirmTitle: "Delete"
        ) {
            Task {
                await deleteList()
            }
        }
    }
    
    // MARK: - Delete List
    
    private func deleteList() async {
        isDeleting = true
        
        do {
            await MainActor.run {
                dismiss()
            }
            
            let path = "/functions/v1/lists-delete?list_id=\(list.id)"
            let _: EmptyResponse = try await SupabaseClient.shared.delete(
                path: path,
                requiresAuth: true
            )
            
            await MainActor.run {
                onListUpdated?(list.id, 0)
                isDeleting = false
            }
        } catch {
            print("❌ [ListDetail] Delete error: \(error)")
            await MainActor.run {
                isDeleting = false
            }
        }
    }
    
}

// MARK: - List Detail Top Bar

struct ListDetailTopBar: View {
    let title: String
    let subtitle: String?
    let showMenu: Bool
    let onBack: () -> Void
    let onMenu: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    var body: some View {
        HStack {
            // Left: Back button
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            
            Spacer()
            
            // Center: Title + subtitle
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Right: Menu button or spacer
            if showMenu {
                Button(action: onMenu) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(backgroundColor)
    }
}

// MARK: - List Detail Menu Sheet (Slide up)

struct ListDetailMenuSheet: View {
    let isDefaultList: Bool
    let onSettings: () -> Void
    let onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.systemGray3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 20)
            
            VStack(spacing: 0) {
                // Settings
                menuRow(icon: "gear", title: "Settings") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onSettings() }
                }
                
                // Delete (only for custom lists)
                if !isDefaultList {
                    Divider().padding(.leading, 56)
                    
                    menuRow(icon: "trash", title: "Delete List", isDestructive: true) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDelete() }
                    }
                }
            }
            
            Spacer()
        }
        .presentationDetents([.height(isDefaultList ? 120 : 180)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
    }
    
    private func menuRow(icon: String, title: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isDestructive ? .red : .primary)
                    .frame(width: 32)
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isDestructive ? .red : .primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(.systemGray3))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cover Image View

struct CoverImageView: View {
    let coverUrl: String?
    let isReadOnly: Bool
    let onUpload: (UIImage) async -> String?
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var currentCoverUrl: String?
    
    var body: some View {
        ZStack {
            ZStack(alignment: .bottomTrailing) {
                if let url = currentCoverUrl ?? coverUrl {
                    AsyncImage(url: URL(string: url)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure(_):
                            placeholderView
                        case .empty:
                            placeholderView
                        @unknown default:
                            placeholderView
                        }
                    }
                } else {
                    placeholderView
                }
                
                if !isReadOnly {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                            Text(currentCoverUrl == nil && coverUrl == nil ? "Add" : "Change")
                                .fontWeight(.medium)
                        }
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            LinearGradient(
                                colors: [GourneyColors.coral, GourneyColors.coral.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        .padding(16)
                    }
                    .disabled(isUploading)
                    .opacity(isUploading ? 0 : 1)
                }
            }
            
            if isUploading {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            }
        }
        .frame(height: 200)
        .clipShape(Rectangle())
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    isUploading = true
                    
                    if let newUrl = await onUpload(image) {
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentCoverUrl = newUrl
                            }
                        }
                    }
                    
                    isUploading = false
                    selectedItem = nil
                }
            }
        }
        .onAppear {
            currentCoverUrl = coverUrl
        }
        .onChange(of: coverUrl) { _, newUrl in
            currentCoverUrl = newUrl
        }
    }
    
    private var placeholderView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    GourneyColors.coral.opacity(0.2),
                    GourneyColors.coral.opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: "photo")
                .font(.system(size: 40))
                .foregroundColor(GourneyColors.coral.opacity(0.4))
        }
    }
}

// MARK: - Empty Places View

struct EmptyPlacesView: View {
    @Binding var showAddPlace: Bool
    let isReadOnly: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mappin.circle")
                .font(.system(size: 60))
                .foregroundColor(GourneyColors.coral.opacity(0.3))
            
            VStack(spacing: 8) {
                Text("No Places Yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(isReadOnly ? "This list is empty" : "Add your first restaurant to this list")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if !isReadOnly {
                Button(action: { showAddPlace = true }) {
                    Label("Add Place", systemImage: "plus")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 160, height: 44)
                        .background(GourneyColors.coral)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, 40)
    }
}

// MARK: - Add Place Sheet

struct AddPlaceToListSheet: View {
    let listId: String
    @ObservedObject var viewModel: ListDetailViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 60))
                    .foregroundColor(GourneyColors.coral.opacity(0.3))
                
                Text("Search Places")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Coming soon")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Add Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(GourneyColors.coral)
                }
            }
        }
    }
}

// MARK: - Swipe to Delete Row

struct SwipeToDeleteRow: View {
    let item: ListItem
    let distance: String?
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var offset: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    
    private let deleteButtonWidth: CGFloat = 80
    private let deleteThreshold: CGFloat = 60
    
    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: {
                onDelete()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 20, weight: .medium))
                    Text("Delete")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(width: deleteButtonWidth)
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(Color.red)
            
            PlaceRowView(
                item: PlaceRowItem(from: item),
                distance: distance,
                showRemoveButton: false,
                onRemove: nil
            )
            .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let translation = value.translation.width
                        if translation < 0 {
                            offset = max(translation, -deleteButtonWidth)
                        } else if offset < 0 {
                            offset = min(0, offset + translation)
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3)) {
                            if offset < -deleteThreshold {
                                offset = -deleteButtonWidth
                            } else {
                                offset = 0
                            }
                        }
                    }
            )
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        if offset < 0 {
                            withAnimation(.spring(response: 0.3)) {
                                offset = 0
                            }
                        } else {
                            onTap()
                        }
                    }
            )
        }
        .frame(height: 90)
        .clipped()
    }
}

#Preview {
    NavigationStack {
        ListDetailView(
            list: RestaurantList(
                id: "preview",
                title: "My Favorites",
                description: "Best restaurants",
                visibility: "public",
                itemCount: 5,
                coverPhotoUrl: nil,
                createdAt: "",
                likesCount: 10,
                viewCount: nil
            ),
            isReadOnly: false
        )
    }
}

// MARK: - ViewModel

@MainActor
class ListDetailViewModel: ObservableObject {
    @Published var places: [ListItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var likeStatus: (hasLiked: Bool, likesCount: Int)?
    
    // Like state (moved from View)
    @Published var isLiked = false
    @Published var likesCount: Int = 0
    @Published var likeScale: CGFloat = 1.0
    
    private let client = SupabaseClient.shared
    private var loadTask: Task<Void, Never>?
    private var pendingLikeTask: Task<Void, Never>?
    
    deinit {
        loadTask?.cancel()
        pendingLikeTask?.cancel()
        print("🧹 [ListDetailVM] Cleaning up")
    }
    
    // MARK: - Toggle Like (Instagram-style - final state always wins)
    
    func toggleLike(listId: String) {
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        // Animate scale
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            likeScale = 1.3
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                self.likeScale = 1.0
            }
        }
        
        // Optimistic UI update
        isLiked.toggle()
        likesCount += isLiked ? 1 : -1
        likesCount = max(0, likesCount)
        
        // Cancel any pending API call
        pendingLikeTask?.cancel()
        
        // Capture the final desired state AFTER the toggle
        let finalDesiredState = isLiked
        
        // Debounce: wait 300ms before making API call
        pendingLikeTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            
            guard !Task.isCancelled else { return }
            
            await syncLikeWithServer(listId: listId, desiredState: finalDesiredState)
        }
    }
    
    private func syncLikeWithServer(listId: String, desiredState: Bool) async {
        // If UI state changed since we scheduled this call, don't proceed
        guard isLiked == desiredState else { return }
        
        do {
            let body: [String: String] = ["list_id": listId]
            
            struct ListLikeToggleResponse: Codable {
                let listId: String?
                let liked: Bool
                let likeCount: Int
                let createdAt: String?
            }
            
            let response: ListLikeToggleResponse = try await client.post(
                path: "/functions/v1/lists-like-toggle",
                body: body,
                requiresAuth: true
            )
            
            guard !Task.isCancelled else { return }
            
            // Check if UI state still matches what we wanted
            let currentState = isLiked
            
            // If server state matches desired state, sync the count
            if response.liked == desiredState {
                likesCount = response.likeCount
                likeStatus = (hasLiked: response.liked, likesCount: response.likeCount)
            } else if currentState == desiredState {
                // Server disagrees but UI shows what user wants - call API again to fix
                print("⚠️ [ListLike] Server mismatch, retrying to sync...")
                await syncLikeWithServer(listId: listId, desiredState: desiredState)
                return
            }
            
            print("✅ [ListLike] Synced - liked: \(response.liked), count: \(response.likeCount)")
            
        } catch {
            guard !Task.isCancelled else { return }
            print("❌ [ListLike] Error: \(error)")
            // Don't revert - keep UI state as user intended
        }
    }
    
    func loadPlaces(listId: String, completion: ((Bool, Int) -> Void)? = nil) async {
        loadTask?.cancel()
        
        isLoading = true
        errorMessage = nil
        
        await withTaskCancellationHandler {
            await Task {
                do {
                    let body = ["list_id": listId]
                    let response: ListDetailResponse = try await client.post(
                        path: "/functions/v1/lists-get-detail",
                        body: body,
                        requiresAuth: true
                    )
                    
                    if Task.isCancelled { return }
                    
                    await MainActor.run {
                        places = response.items
                        isLoading = false
                        
                        // Set like state
                        isLiked = response.list.hasLiked
                        likesCount = response.list.likesCount
                        likeStatus = (hasLiked: response.list.hasLiked, likesCount: response.list.likesCount)
                        
                        completion?(response.list.hasLiked, response.list.likesCount)
                    }
                    
                    print("✅ [ListDetail] Loaded \(response.items.count) places")
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            errorMessage = error.localizedDescription
                            isLoading = false
                            isLiked = false
                            likesCount = 0
                            likeStatus = (hasLiked: false, likesCount: 0)
                            completion?(false, 0)
                        }
                        print("❌ [ListDetail] Load error: \(error)")
                    }
                }
            }.value
        } onCancel: { }
    }
    
    func removePlace(listId: String, itemId: String, placeId: String, onSuccess: @escaping (Int) -> Void) async {
        let originalPlaces = places
        
        await MainActor.run {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                places.removeAll { $0.id == itemId }
            }
        }
        
        let newCount = places.count
        
        await MainActor.run {
            onSuccess(newCount)
        }
        
        do {
            var components = URLComponents(url: URL(string: Config.supabaseURL)!.appendingPathComponent("/functions/v1/lists-remove-item"), resolvingAgainstBaseURL: true)!
            components.queryItems = [
                URLQueryItem(name: "list_id", value: listId),
                URLQueryItem(name: "place_id", value: placeId)
            ]
            
            guard let url = components.url else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue(Config.apiVersion, forHTTPHeaderField: "X-API-Version")
            
            if let token = client.getAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            if httpResponse.statusCode == 204 {
                print("✅ [RemovePlace] API confirmed delete")
            } else if httpResponse.statusCode >= 400 {
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Delete failed"])
            }
        } catch {
            print("❌ [RemovePlace] API failed, rolling back: \(error)")
            
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    places = originalPlaces
                }
                errorMessage = "Failed to remove item. Please try again."
                onSuccess(originalPlaces.count)
            }
        }
    }
    
    func uploadCover(listId: String, image: UIImage) async -> String? {
        do {
            guard let userId = client.getCurrentUserId() else {
                throw CoverPhotoError.notAuthenticated
            }
            
            let coverUrl = try await ListCoverPhotoUploader.shared.uploadCoverPhoto(
                image,
                userId: userId,
                listId: listId
            )
            
            let path = "/functions/v1/lists-update?list_id=\(listId)"
            let body: [String: Any] = ["cover_photo_url": coverUrl]
            
            let _: RestaurantList = try await client.patch(
                path: path,
                body: body,
                requiresAuth: true
            )
            
            print("✅ [ListDetail] Cover photo updated")
            return coverUrl
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
            print("❌ [ListDetail] Cover upload error: \(error)")
            return nil
        }
    }
}
