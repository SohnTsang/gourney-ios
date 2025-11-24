// Views/Lists/ListDetailView.swift
// ✅ Redesigned with Gourney design system + shared PlaceRowView

import SwiftUI
import PhotosUI
import Combine

struct ListDetailView: View {
    @State var list: RestaurantList
    let onListUpdated: ((String, Int) -> Void)?  // (listId, newCount)
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
    @State private var selectedCoverPhoto: PhotosPickerItem?
    @State private var isUploadingCover = false
    @Environment(\.colorScheme) private var colorScheme
    
    // Check if this is a default list
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
                                    // Upload and get new URL
                                    if let newUrl = await viewModel.uploadCover(listId: list.id, image: image) {
                                        // Trigger parent to refresh this list
                                        // Parent will reload and get updated cover from API
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
                                                                print("🔄 [ListDetail] Received newCount: \(newCount)")
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
                            onListUpdated?(list.id, list.itemCount ?? 0)
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
            // Optimistic UI - dismiss immediately for smooth UX
            await MainActor.run {
                dismiss()
            }
            
            // Background delete - build URL with query parameter
            let path = "/functions/v1/lists-delete?list_id=\(list.id)"
            let _: EmptyResponse = try await SupabaseClient.shared.delete(
                path: path,
                requiresAuth: true
            )
            
            print("✅ [ListDetail] List deleted: \(list.title)")
            
            // Update parent view
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
                onListUpdated?(list.id, list.itemCount ?? 0)
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
    let onUpload: (UIImage) async -> String?  // Returns new URL
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var currentCoverUrl: String?
    
    var body: some View {
        ZStack {
            // Cover photo or placeholder
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
                    .opacity(isUploading ? 0 : 1)
                }
            }
            
            // Loading overlay
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
    
    func removePlace(listId: String, itemId: String, placeId: String, onSuccess: @escaping (Int) -> Void) async {
        print("🗑️ [RemovePlace] Starting delete - listId: \(listId), itemId: \(itemId), placeId: \(placeId)")
        
        // Store original state for rollback if needed
        let originalPlaces = places
        
        // OPTIMISTIC UPDATE: Remove from UI immediately
        await MainActor.run {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                places.removeAll { $0.id == itemId }
            }
        }
        
        let newCount = places.count
        print("⚡ [RemovePlace] Optimistic removal, new count: \(newCount)")
        
        // Trigger parent refresh with NEW count
        await MainActor.run {
            onSuccess(newCount)
        }
        
        // Background API call
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
            
            // ROLLBACK: Restore original list
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    places = originalPlaces
                }
                errorMessage = "Failed to remove item. Please try again."
                // Trigger parent refresh to restore count
                onSuccess(originalPlaces.count)
            }
        }
    }
    
    func uploadCover(listId: String, image: UIImage) async -> String? {
        do {
            // Get user ID
            guard let userId = client.getCurrentUserId() else {
                throw CoverPhotoError.notAuthenticated
            }
            
            // Upload photo (optimized, memory-efficient)
            let coverUrl = try await ListCoverPhotoUploader.shared.uploadCoverPhoto(
                image,
                userId: userId,
                listId: listId
            )
            
            // Update list via edge function
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
            // Delete button background - always visible behind
            Button(action: {
                print("🗑️ [Delete] Button tapped")
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
            
            // Main content - slides over delete button
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
                            // Close swipe if open
                            withAnimation(.spring(response: 0.3)) {
                                offset = 0
                            }
                        } else {
                            // Normal tap
                            onTap()
                        }
                    }
            )
        }
        .frame(height: 90)
        .clipped()
    }
}
