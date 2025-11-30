// Views/Visit/EditVisitView.swift
// Edit existing visit - same UI as AddVisitView
// Place is locked, can edit: photos, rating, comment, visibility
// FIX: Broadcasts update via VisitUpdateService for seamless UI/UX

import SwiftUI
import PhotosUI
import Combine

@MainActor
class EditVisitViewModel: ObservableObject {
    @Published var selectedPhotos: [PhotosPickerItem] = []
    @Published var loadedImages: [(id: UUID, image: UIImage, pickerItem: PhotosPickerItem?)] = []
    @Published var existingPhotoURLs: [String] = []  // Existing photos - show with AsyncImage
    @Published var uploadedPhotoURLs: [String] = []
    @Published var uploadProgress: [UUID: Double] = [:]
    @Published var isUploadingPhotos = false
    @Published var rating: Int = 0
    @Published var comment: String = ""
    @Published var visibility: VisitVisibility = .public
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var showSuccess = false
    @Published var selectedPhotoIndex: Int?
    @Published var showErrorAlert = false
    
    // Original values to detect changes
    private var originalRating: Int = 0
    private var originalComment: String = ""
    private var originalVisibility: VisitVisibility = .public
    private var originalPhotoUrls: [String] = []
    
    private var tempFileUrls: [UUID: URL] = [:]
    var shouldIgnorePhotoChanges = false
    
    let visitId: String
    let placeName: String
    let placeLocation: String
    let maxPhotos = 5
    let maxCommentLength = 1000
    private let client = SupabaseClient.shared
    
    // Store original FeedItem for place data
    private let originalFeedItem: FeedItem
    
    // Total photo count (existing + new)
    var totalPhotoCount: Int {
        existingPhotoURLs.count + loadedImages.count
    }
    
    var hasChanges: Bool {
        rating != originalRating ||
        comment != originalComment ||
        visibility != originalVisibility ||
        currentPhotoUrls != originalPhotoUrls
    }
    
    // Current photo URLs for comparison
    private var currentPhotoUrls: [String] {
        existingPhotoURLs + uploadedPhotoURLs
    }
    
    var isValid: Bool {
        // Need at least photo OR comment
        (totalPhotoCount > 0 || !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && !isUploadingPhotos
    }
    
    init(feedItem: FeedItem) {
        self.visitId = feedItem.id
        self.placeName = feedItem.place.displayName
        self.placeLocation = feedItem.place.locationString
        self.originalFeedItem = feedItem
        
        // Set current values
        self.rating = feedItem.rating ?? 0
        self.comment = feedItem.comment ?? ""
        self.visibility = VisitVisibility(rawValue: feedItem.visibility) ?? .public
        self.existingPhotoURLs = feedItem.photos  // Just store URLs, no download
        
        // Store originals
        self.originalRating = self.rating
        self.originalComment = self.comment
        self.originalVisibility = self.visibility
        self.originalPhotoUrls = feedItem.photos
    }
    
    // Remove existing photo by index
    func removeExistingPhoto(at index: Int) {
        guard index < existingPhotoURLs.count else { return }
        existingPhotoURLs.remove(at: index)
    }
    
    // Clear all photos (existing + new)
    func clearAllPhotos() {
        existingPhotoURLs.removeAll()
        cleanupAllTempFiles()
        shouldIgnorePhotoChanges = true
        selectedPhotos = []
        loadedImages = []
        uploadedPhotoURLs = []
        
        // Reset flag after clearing
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            await MainActor.run {
                shouldIgnorePhotoChanges = false
            }
        }
    }
    
    func loadPhotos() async {
        guard !selectedPhotos.isEmpty else {
            shouldIgnorePhotoChanges = false
            return
        }
        guard !shouldIgnorePhotoChanges else {
            shouldIgnorePhotoChanges = false
            return
        }
        
        await MainActor.run {
            isUploadingPhotos = true
            uploadProgress = [:]
        }
        
        var newImages: [(id: UUID, image: UIImage, pickerItem: PhotosPickerItem?)] = []
        
        for item in selectedPhotos {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let resized = resizeImageForPreview(image)
                let id = UUID()
                
                let tempUrl = await saveTempFile(resized, id: id)
                if let tempUrl = tempUrl {
                    await MainActor.run {
                        self.tempFileUrls[id] = tempUrl
                    }
                }
                
                newImages.append((id: id, image: resized, pickerItem: item))
                
                await MainActor.run {
                    // Append to existing loaded images
                    self.loadedImages.append((id: id, image: resized, pickerItem: item))
                    self.uploadProgress[id] = 0.0
                }
            }
        }
        
        // Upload new photos
        do {
            try await uploadNewPhotos(newImages)
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to upload photos"
                self.showErrorAlert = true
                self.isUploadingPhotos = false
            }
        }
    }
    
    private func uploadNewPhotos(_ images: [(id: UUID, image: UIImage, pickerItem: PhotosPickerItem?)]) async throws {
        guard !images.isEmpty else {
            await MainActor.run { isUploadingPhotos = false }
            return
        }
        guard let user = AuthManager.shared.currentUser else {
            throw APIError.unauthorized
        }
        
        let uiImages = images.map { $0.image }
        let ids = images.map { $0.id }
        
        let urls = try await PhotoUploadService.shared.uploadPhotos(
            uiImages,
            userId: user.id,
            progressHandler: { index, progress in
                Task { @MainActor in
                    if index < ids.count {
                        self.uploadProgress[ids[index]] = progress
                    }
                }
            }
        )
        
        await MainActor.run {
            self.uploadedPhotoURLs.append(contentsOf: urls)
            self.isUploadingPhotos = false
            self.uploadProgress = [:]
            self.selectedPhotos = [] // Clear picker selection
        }
    }
    
    private func saveTempFile(_ image: UIImage, id: UUID) async -> URL? {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("gourney_photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let fileUrl = tempDir.appendingPathComponent("\(id.uuidString).jpg")
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        
        do {
            try data.write(to: fileUrl)
            return fileUrl
        } catch {
            return nil
        }
    }
    
    func removePhoto(at index: Int) {
        // This is for removing NEW photos only (from loadedImages)
        guard index < loadedImages.count else { return }
        
        let item = loadedImages[index]
        
        // Delete temp file if exists
        if let tempUrl = tempFileUrls[item.id] {
            try? FileManager.default.removeItem(at: tempUrl)
            tempFileUrls.removeValue(forKey: item.id)
        }
        
        loadedImages.remove(at: index)
        
        // Also remove from uploaded URLs if already uploaded
        if index < uploadedPhotoURLs.count {
            uploadedPhotoURLs.remove(at: index)
        }
        
        // Remove from picker selection if it was a new photo
        if let pickerItem = item.pickerItem,
           let pickerIndex = selectedPhotos.firstIndex(of: pickerItem) {
            shouldIgnorePhotoChanges = true
            selectedPhotos.remove(at: pickerIndex)
        }
    }
    
    func removePhotoById(_ id: UUID) {
        guard let index = loadedImages.firstIndex(where: { $0.id == id }) else { return }
        removePhoto(at: index)
    }
    
    func cleanupAllTempFiles() {
        for (_, url) in tempFileUrls {
            try? FileManager.default.removeItem(at: url)
        }
        tempFileUrls.removeAll()
    }
    
    private func resizeImageForPreview(_ image: UIImage) -> UIImage {
        let maxSize: CGFloat = 1024
        let originalWidth = image.size.width
        let originalHeight = image.size.height
        
        if originalWidth <= maxSize && originalHeight <= maxSize {
            return image
        }
        
        let scale = min(maxSize / originalWidth, maxSize / originalHeight)
        let newSize = CGSize(width: originalWidth * scale, height: originalHeight * scale)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    func saveChanges() async {
        guard hasChanges else { return }
        
        isSaving = true
        errorMessage = nil
        
        do {
            var requestBody: [String: Any] = [:]
            
            // Only include changed fields
            if rating != originalRating {
                requestBody["rating"] = rating > 0 ? rating : NSNull()
            }
            
            if comment != originalComment {
                requestBody["comment"] = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            if visibility != originalVisibility {
                requestBody["visibility"] = visibility.rawValue
            }
            
            // Combine existing + new uploaded URLs
            let allPhotoUrls = existingPhotoURLs + uploadedPhotoURLs
            if allPhotoUrls != originalPhotoUrls {
                requestBody["photo_urls"] = allPhotoUrls
            }
            
            // Get full response to broadcast update
            let response: VisitUpdateResponse = try await client.put(
                path: "/functions/v1/visits-update?visit_id=\(visitId)",
                body: requestBody,
                requiresAuth: true
            )
            
            // Broadcast update to all listening views
            let updateData = VisitUpdateData(
                id: response.id,
                userId: response.userId,
                placeId: response.placeId,
                rating: response.rating,
                comment: response.comment,
                photoUrls: response.photoUrls,
                visibility: response.visibility,
                visitedAt: response.visitedAt,
                createdAt: response.createdAt,
                deletedAt: response.deletedAt,
                place: response.place.map { p in
                    VisitUpdatePlace(
                        id: p.id,
                        nameEn: p.nameEn,
                        nameJa: p.nameJa,
                        city: p.city,
                        ward: p.ward,
                        categories: p.categories,
                        lat: p.lat,
                        lng: p.lng
                    )
                }
            )
            
            VisitUpdateService.shared.notifyVisitUpdated(visitId: visitId, data: updateData)
            
            await MainActor.run {
                isSaving = false
                ToastManager.shared.showSuccess("Visit updated!")
            }
            
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            await MainActor.run {
                self.showSuccess = true
            }
            
        } catch let error as APIError {
            await MainActor.run {
                isSaving = false
                switch error {
                case .badRequest(let message):
                    errorMessage = message
                default:
                    errorMessage = "Failed to save changes"
                }
                showErrorAlert = true
            }
        } catch {
            await MainActor.run {
                isSaving = false
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}

// MARK: - Visit Update Response (Full response from edge function)

struct VisitUpdateResponse: Codable {
    let id: String
    let userId: String
    let placeId: String
    let rating: Int?
    let comment: String?
    let photoUrls: [String]?
    let visibility: String
    let visitedAt: String
    let createdAt: String
    let deletedAt: String?
    let place: VisitUpdateResponsePlace?
}

struct VisitUpdateResponsePlace: Codable {
    let id: String
    let nameEn: String?
    let nameJa: String?
    let city: String?
    let ward: String?
    let categories: [String]?
    let lat: Double?
    let lng: Double?
}

// MARK: - Edit Visit View

struct EditVisitView: View {
    let feedItem: FeedItem
    var onVisitUpdated: ((FeedItem) -> Void)?
    
    @StateObject private var viewModel: EditVisitViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    init(feedItem: FeedItem, onVisitUpdated: ((FeedItem) -> Void)? = nil) {
        self.feedItem = feedItem
        self.onVisitUpdated = onVisitUpdated
        self._viewModel = StateObject(wrappedValue: EditVisitViewModel(feedItem: feedItem))
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(white: 0.97)
    }
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top bar using DetailTopBar
                DetailTopBar(
                    title: "Edit Visit",
                    rightButtonTitle: "Save",
                    rightButtonDisabled: !viewModel.hasChanges || !viewModel.isValid,
                    rightButtonLoading: viewModel.isSaving,
                    showRightButton: true,
                    onBack: {
                        if viewModel.hasChanges {
                            // Could show discard alert here
                            dismiss()
                        } else {
                            dismiss()
                        }
                    },
                    onRightAction: {
                        Task { await viewModel.saveChanges() }
                    }
                )
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        photosSection
                        placeSection  // Read-only
                        ratingSection
                        commentSection
                        visibilitySection
                        Spacer(minLength: 60)
                    }
                    .padding(.top, 16)
                }
            }
            .disabled(viewModel.isSaving)
            
            if viewModel.isSaving {
                LoadingOverlay(message: "Saving changes...")
            }
            
            if let index = viewModel.selectedPhotoIndex {
                fullscreenPhotoViewer(index: index)
            }
        }
        .navigationBarHidden(true)
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong")
        }
        .onChange(of: viewModel.showSuccess) { _, isSuccess in
            if isSuccess {
                // Create updated FeedItem with new values
                let updatedItem = FeedItem(
                    id: feedItem.id,
                    rating: viewModel.rating > 0 ? viewModel.rating : nil,
                    comment: viewModel.comment.isEmpty ? nil : viewModel.comment,
                    photoUrls: viewModel.existingPhotoURLs + viewModel.uploadedPhotoURLs,
                    visibility: viewModel.visibility.rawValue,
                    createdAt: feedItem.createdAt,
                    visitedAt: feedItem.visitedAt,
                    likeCount: feedItem.likeCount,
                    commentCount: feedItem.commentCount,
                    isLiked: feedItem.isLiked,
                    isFollowing: feedItem.isFollowing,
                    user: feedItem.user,
                    place: feedItem.place
                )
                onVisitUpdated?(updatedItem)
                dismiss()
            }
        }
        .onChange(of: viewModel.selectedPhotos) { _, _ in
            Task { await viewModel.loadPhotos() }
        }
        .onDisappear {
            viewModel.cleanupAllTempFiles()
        }
    }
    
    // MARK: - Photos Section
    
    private var photosSection: some View {
        VisitPhotosSection(
            existingPhotoURLs: viewModel.existingPhotoURLs,
            loadedImages: viewModel.loadedImages.map { (id: $0.id, image: $0.image) },
            maxPhotos: viewModel.maxPhotos,
            uploadProgress: viewModel.uploadProgress,
            selectedPhotos: $viewModel.selectedPhotos,
            onRemoveExisting: { index in
                viewModel.removeExistingPhoto(at: index)
            },
            onRemoveNew: { id in
                viewModel.removePhotoById(id)
            },
            onPhotoTap: nil,  // EditVisit doesn't need fullscreen photo tap
            onClearAll: {
                viewModel.clearAllPhotos()
            }
        )
    }
    
    // MARK: - Place Section (Read-only)
    
    private var placeSection: some View {
        VisitPlaceReadOnlySection(
            placeName: viewModel.placeName,
            placeLocation: viewModel.placeLocation
        )
    }
    
    // MARK: - Rating Section
    
    private var ratingSection: some View {
        VisitRatingSection(rating: $viewModel.rating, allowDeselect: true)
    }
    
    // MARK: - Comment Section
    
    private var commentSection: some View {
        VisitCommentSection(comment: $viewModel.comment, maxLength: viewModel.maxCommentLength)
    }
    
    // MARK: - Visibility Section
    
    private var visibilitySection: some View {
        VisitVisibilitySection(visibility: $viewModel.visibility)
    }
    
    // MARK: - Fullscreen Photo Viewer
    
    private func fullscreenPhotoViewer(index: Int) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            TabView(selection: $viewModel.selectedPhotoIndex) {
                ForEach(Array(viewModel.loadedImages.enumerated()), id: \.offset) { i, item in
                    Image(uiImage: item.image)
                        .resizable()
                        .scaledToFit()
                        .tag(i as Int?)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            
            VStack {
                HStack {
                    Spacer()
                    Button {
                        viewModel.selectedPhotoIndex = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(16)
                }
                Spacer()
            }
        }
    }
}

#Preview {
    NavigationStack {
        EditVisitView(feedItem: .preview)
    }
}
