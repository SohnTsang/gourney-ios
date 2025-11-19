// Views/Lists/ListDetailView.swift
// ✅ Redesigned with Gourney design system + shared PlaceRowView

import SwiftUI
import PhotosUI
import Combine

struct ListDetailView: View {
    @State var list: RestaurantList
    let onListUpdated: (() -> Void)?
    let isReadOnly: Bool
    let ownerHandle: String?  // Add owner handle for display
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = ListDetailViewModel()
    @StateObject private var locationManager = LocationManager.shared
    @State private var showAddPlace = false
    @State private var showSettings = false
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @State private var showMenu = false
    @State private var isLiked = false
    @State private var likesCount: Int = 0
    @State private var isProcessingLike = false
    @State private var selectedPlace: Place?
    @State private var showPlaceDetail = false
    @State private var showAddVisitFromDetail = false
    @State private var refreshTrigger = UUID()
    @State private var dragOffset: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    
    // Check if this is a default list
    private var isDefaultList: Bool {
        let wantToTryTitle = NSLocalizedString("lists.default.want_to_try", comment: "")
        let favoritesTitle = NSLocalizedString("lists.default.favorites", comment: "")
        return list.title == wantToTryTitle || list.title == favoritesTitle
    }
    
    init(list: RestaurantList, isReadOnly: Bool = false, ownerHandle: String? = nil, onListUpdated: (() -> Void)? = nil) {
        self._list = State(initialValue: list)
        self.isReadOnly = isReadOnly
        self.ownerHandle = ownerHandle
        self.onListUpdated = onListUpdated
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Custom Navigation Bar
                ZStack {
                    // Left Button - X icon
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                        }
                        .padding(.leading, 16)
                        Spacer()
                    }
                    
                    // Centered Title
                    VStack(spacing: 4) {
                        Text(list.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        // Show username for read-only lists
                        if isReadOnly, let handle = ownerHandle {
                            Text("@\(handle)")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Right Button
                    HStack {
                        Spacer()
                        if !isReadOnly {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showMenu = true
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                            }
                            .padding(.trailing, 16)
                        }
                    }
                }
                .frame(height: 56)
                .frame(maxWidth: .infinity)
                .padding(.top, geometry.safeAreaInsets.top > 0 ? geometry.safeAreaInsets.top : 50)
                .background(colorScheme == .dark ? Color.black : Color.white)
                
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
                                    await viewModel.uploadCover(listId: list.id, image: image)
                                }
                            )
                            
                            // List Info Section
                            VStack(spacing: 12) {
                                // Stats Row - Places on left, Likes/Button on right
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
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
                                            // Like button for other users' lists
                                            Button {
                                                Task {
                                                    await toggleLike()
                                                }
                                            } label: {
                                                HStack(spacing: 8) {
                                                    Image(systemName: isLiked ? "heart.fill" : "heart")
                                                        .font(.system(size: 24, weight: .medium))
                                                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                                                        .scaleEffect(isProcessingLike ? 1.2 : 1.0)
                                                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isProcessingLike)
                                                    
                                                    Text("\(likesCount)")
                                                        .font(.system(size: 16, weight: .semibold))
                                                        .foregroundColor(.primary)
                                                        .onAppear {
                                                            print("❤️ [UI] Heart icon rendered: isLiked=\(isLiked), likesCount=\(likesCount)")
                                                        }
                                                        .onChange(of: likesCount) { oldValue, newValue in
                                                            print("❤️ [UI] likesCount changed: \(oldValue) → \(newValue)")
                                                        }
                                                }
                                            }
                                            .disabled(isProcessingLike)
                                        } else {
                                            // Like count display for own lists
                                            HStack(spacing: 6) {
                                                Image(systemName: "heart.fill")
                                                    .font(.system(size: 16))
                                                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                                                Text("\(likesCount)")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(.primary)
                                                Text("likes")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.secondary)
                                            }
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
                                        PlaceRowView(
                                            item: PlaceRowItem(from: item),
                                            distance: item.place.map { locationManager.formattedDistance(from: $0.coordinate) } ?? nil,
                                            showRemoveButton: !isReadOnly,
                                            onRemove: {
                                                Task {
                                                    await viewModel.removePlace(listId: list.id, itemId: item.id)
                                                }
                                            }
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if let place = item.place {
                                                selectedPlace = place
                                                showPlaceDetail = true
                                            }
                                        }
                                        
                                        if item.id != viewModel.places.last?.id {
                                            Divider()
                                                .padding(.leading, 90)
                                        }
                                    }
                                }
                                .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
                            }
                        }
                    }
                    
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(Color(red: 1.0, green: 0.4, blue: 0.4))
                    }
                }
            }
            .task {
                // Load places and get like status via completion
                await viewModel.loadPlaces(listId: list.id) { hasLiked, count in
                    isLiked = hasLiked
                    likesCount = count
                    print("🔵 [ListDetail] Set initial like state: liked=\(hasLiked), count=\(count)")
                }
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
                            showAddVisitFromDetail = true
                        },
                        onDismiss: nil
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .id(refreshTrigger)
                }
            }
            .fullScreenCover(isPresented: $showAddVisitFromDetail) {
                if let place = selectedPlace {
                    AddVisitView(
                        prefilledPlace: PlaceSearchResult(from: place),
                        showBackButton: true,
                        onVisitPosted: { placeId in
                            // Refresh the list and reload place detail
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
            .overlay {
                if showSettings {
                    ListSettingsSheet(
                        list: list,
                        isPresented: $showSettings,
                        onSave: { updatedList in
                            list = updatedList
                            onListUpdated?()
                        }
                    )
                }
            }
            .overlay {
                if showMenu {
                    CustomContextMenu(
                        items: {
                            var items = [
                                ContextMenuItem(
                                    icon: "gear",
                                    title: "Settings",
                                    isDestructive: false,
                                    action: {
                                        showSettings = true
                                    }
                                )
                            ]
                            if !isDefaultList {
                                items.append(
                                    ContextMenuItem(
                                        icon: "trash",
                                        title: "Delete List",
                                        isDestructive: true,
                                        action: {
                                            showDeleteAlert = true
                                        }
                                    )
                                )
                            }
                            return items
                        }(),
                        isPresented: $showMenu,
                        alignment: .topTrailing,
                        offset: CGSize(width: -12, height: 60)
                    )
                }
            }
            .alert("Delete List", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteList()
                    }
                }
            } message: {
                Text("Are you sure you want to delete \"\(list.title)\"? This action cannot be undone.")
            }
            .interactiveDismissDisabled(showSettings || showDeleteAlert || isDeleting)
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Delete List
    
    private func deleteList() async {
        isDeleting = true
        
        do {
            let _: EmptyResponse = try await SupabaseClient.shared.delete(
                path: "/functions/v1/lists-delete/\(list.id)",
                requiresAuth: true
            )
            
            print("✅ [ListDetail] List deleted: \(list.title)")
            
            // Navigate back after successful delete
            await MainActor.run {
                isDeleting = false
                onListUpdated?()
                dismiss()
            }
        } catch {
            print("❌ [ListDetail] Delete error: \(error)")
            await MainActor.run {
                isDeleting = false
            }
        }
    }
    
    // MARK: - Like Functions
    
    private func toggleLike() async {
        isProcessingLike = true
        
        // Optimistic UI update with haptic feedback
        if #available(iOS 17.0, *) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isLiked.toggle()
            likesCount += isLiked ? 1 : -1
        }
        
        do {
            // Call backend edge function - consistent with likes-toggle for visits
            let body: [String: String] = ["list_id": list.id]
            let client = SupabaseClient.shared
            
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
            
            // Update with actual server response
            await MainActor.run {
                isLiked = response.liked
                likesCount = response.likeCount
                
                // Update the parent list object
                list.likesCount = response.likeCount
                
                // Notify parent view to refresh if needed
                onListUpdated?()
            }
            
            print("✅ [List] Like toggled: \(response.liked ? "Liked" : "Unliked")")
            
        } catch {
            // Revert on error
            await MainActor.run {
                withAnimation {
                    isLiked.toggle()
                    likesCount += isLiked ? 1 : -1
                }
                
                // Show error feedback
                if #available(iOS 17.0, *) {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
            print("❌ [List] Like toggle error: \(error)")
        }
        
        isProcessingLike = false
    }
}

// MARK: - Cover Image View

struct CoverImageView: View {
    let coverUrl: String?
    let isReadOnly: Bool
    let onUpload: (UIImage) async -> Void
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var isUploading = false
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let coverUrl = coverUrl {
                AsyncImage(url: URL(string: coverUrl)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholderView
                }
            } else {
                placeholderView
            }
            
            if !isReadOnly {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: isUploading ? "arrow.triangle.2.circlepath" : "camera.fill")
                        Text(coverUrl == nil ? "Add" : "Change")
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    .padding(16)
                }
                .disabled(isUploading)
            }
        }
        .frame(height: 200)
        .clipShape(Rectangle())
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    isUploading = true
                    await onUpload(image)
                    isUploading = false
                }
            }
        }
    }
    
    private var placeholderView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.2),
                    Color(red: 1.0, green: 0.5, blue: 0.5).opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 40))
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.5))
                Text("Add Cover Photo")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Empty State

struct EmptyPlacesView: View {
    @Binding var showAddPlace: Bool
    var isReadOnly: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 60))
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3))
            
            VStack(spacing: 8) {
                Text("No Places Yet")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                if isReadOnly {
                    Text("This list doesn't have any places")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Add places from Discover or your visits")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            if !isReadOnly {
                Button(action: { showAddPlace = true }) {
                    Label("Add Places", systemImage: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 180, height: 48)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3), radius: 8, y: 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

// MARK: - ViewModel

@MainActor
class ListDetailViewModel: ObservableObject {
    @Published var places: [ListItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var likeStatus: (hasLiked: Bool, likesCount: Int)?
    
    private let client = SupabaseClient.shared
    private var loadTask: Task<Void, Never>?
    
    deinit {
        // Cancel any ongoing tasks
        loadTask?.cancel()
        // Note: Can't directly mutate @Published properties here
        print("🧹 [ListDetailVM] Cleaning up")
    }
    
    func loadPlaces(listId: String, completion: ((Bool, Int) -> Void)? = nil) async {
        // Cancel previous load task
        loadTask?.cancel()
        
        isLoading = true
        errorMessage = nil
        
        // Create task and AWAIT it
        await withTaskCancellationHandler {
            await Task {
                do {
                    // Use proper request format for lists-get-detail
                    let body = ["list_id": listId]
                    let response: ListDetailResponse = try await client.post(
                        path: "/functions/v1/lists-get-detail",
                        body: body,
                        requiresAuth: true
                    )
                    
                    // Check if task was cancelled
                    if Task.isCancelled { return }
                    
                    await MainActor.run {
                        places = response.items
                        isLoading = false
                        
                        // Store like status
                        likeStatus = (hasLiked: response.list.hasLiked, likesCount: response.list.likesCount)
                        
                        // Also call completion for backward compatibility
                        completion?(response.list.hasLiked, response.list.likesCount)
                        
                        print("📊 [ListDetail] Stored like status: hasLiked=\(response.list.hasLiked), likesCount=\(response.list.likesCount)")
                    }
                    
                    print("✅ [ListDetail] Loaded \(response.items.count) places, liked: \(response.list.hasLiked), count: \(response.list.likesCount)")
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            errorMessage = error.localizedDescription
                            isLoading = false
                            likeStatus = (hasLiked: false, likesCount: 0)
                            completion?(false, 0)
                        }
                        print("❌ [ListDetail] Load error: \(error)")
                    }
                }
            }.value
        } onCancel: { }
    }
    
    func removePlace(listId: String, itemId: String) async {
        do {
            let _: EmptyResponse = try await client.delete(
                path: "/functions/v1/lists-remove-item?list_id=\(listId)&item_id=\(itemId)",
                requiresAuth: true
            )
            
            places.removeAll { $0.id == itemId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func uploadCover(listId: String, image: UIImage) async {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { return }
        
        do {
            isLoading = true
            
            // Upload to storage (implement storage upload logic)
            // For now, placeholder
            let coverUrl = "uploaded_url"
            
            // Update list
            let body: [String: Any] = [
                "list_id": listId,
                "cover_photo_url": coverUrl
            ]
            
            let _: EmptyResponse = try await client.post(
                path: "/functions/v1/lists-update",
                body: body,
                requiresAuth: true
            )
            
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
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
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3))
                
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
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                }
            }
        }
    }
}
