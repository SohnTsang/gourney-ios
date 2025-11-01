//
//  AddVisitView.swift
//  gourney
//
//  ✅ FIXED: No upload progress, no upload overlay, bigger photos, proper blocking

import SwiftUI
import PhotosUI
import Combine

struct Design {
    static let accent = Color(red: 1.0, green: 0.45, blue: 0.45)
    static let accentGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.45, blue: 0.45), Color(red: 0.95, green: 0.35, blue: 0.4)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

@MainActor
class AddVisitViewModel: ObservableObject {
    @Published var selectedPhotos: [PhotosPickerItem] = []
    @Published var loadedImages: [(id: UUID, image: UIImage, pickerItem: PhotosPickerItem)] = []
    @Published var uploadedPhotoURLs: [String] = []
    @Published var uploadProgress: [UUID: Double] = [:]
    @Published var isUploadingPhotos = false
    @Published var rating: Int = 0
    @Published var comment: String = ""
    @Published var visibility: VisitVisibility = .public
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var showSuccess = false
    @Published var selectedPlaceResult: PlaceSearchResult?
    @Published var selectedPhotoIndex: Int?
    @Published var showSearchOverlay = false
    @Published var showErrorAlert = false
    
    private var tempFileUrls: [UUID: URL] = [:]
    var shouldIgnorePhotoChanges = false  // Internal for View access
    var onVisitPosted: ((String) -> Void)?  // ✅ Callback for place refresh
    
    let maxPhotos = 5
    let maxCommentLength = 1000
    private let client = SupabaseClient.shared
    
    var displayPlaceName: String {
        selectedPlaceResult?.displayName ?? ""
    }
    
    var hasPlace: Bool {
        selectedPlaceResult != nil
    }
    
    var isValid: Bool {
        // Only require: place + (photo OR comment)
        // Rating is OPTIONAL
        hasPlace && (!uploadedPhotoURLs.isEmpty || !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && !isUploadingPhotos
    }
    
    func loadPhotos() async {
        guard !selectedPhotos.isEmpty else {
            // ✅ FIX 1: Reset flag when selectedPhotos is empty
            shouldIgnorePhotoChanges = false
            return
        }
        guard !shouldIgnorePhotoChanges else {
            print("🚫 Ignoring photo change (programmatic removal)")
            shouldIgnorePhotoChanges = false
            return
        }
        
        await MainActor.run {
            isUploadingPhotos = true
            uploadProgress = [:]
        }
        
        var newImages: [(id: UUID, image: UIImage, pickerItem: PhotosPickerItem)] = []
        
        for item in selectedPhotos {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let resized = resizeImageForPreview(image)
                let id = UUID()
                
                // Save to temp disk immediately for memory efficiency
                let tempUrl = await saveTempFile(resized, id: id)
                if let tempUrl = tempUrl {
                    await MainActor.run {
                        self.tempFileUrls[id] = tempUrl
                    }
                }
                
                newImages.append((id: id, image: resized, pickerItem: item))
                
                await MainActor.run {
                    self.loadedImages = newImages
                    self.uploadProgress[id] = 0.0
                }
            }
        }
        
        // Upload photos immediately after loading
        do {
            try await uploadPhotos()
        } catch {
            print("❌ [AddVisit] Photo upload failed: \(error)")
            await MainActor.run {
                self.errorMessage = "Failed to upload photos"
                self.showErrorAlert = true
                self.isUploadingPhotos = false
            }
        }
    }
    
    private func saveTempFile(_ image: UIImage, id: UUID) async -> URL? {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("gourney_photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let fileUrl = tempDir.appendingPathComponent("\(id.uuidString).jpg")
        
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        
        do {
            try data.write(to: fileUrl)
            print("💾 Saved temp file: \(fileUrl.lastPathComponent)")
            return fileUrl
        } catch {
            print("❌ Failed to save temp file: \(error)")
            return nil
        }
    }
    
    func removePhoto(withId id: UUID) {
        // Delete temp file from disk
        if let tempUrl = tempFileUrls[id] {
            try? FileManager.default.removeItem(at: tempUrl)
            tempFileUrls.removeValue(forKey: id)
            print("🗑️ Deleted temp file for photo \(id)")
        }
        
        // Find the index in loadedImages
        guard let index = loadedImages.firstIndex(where: { $0.id == id }) else { return }
        
        // Remove from loadedImages
        loadedImages.remove(at: index)
        
        // Set flag to prevent onChange from triggering reload
        shouldIgnorePhotoChanges = true
        
        // Remove from selectedPhotos at the same index to untick
        if index < selectedPhotos.count {
            selectedPhotos.remove(at: index)
            print("✅ Unticked photo in picker at index \(index)")
        }
        
        // Remove from uploaded URLs at the same index
        if index < uploadedPhotoURLs.count {
            uploadedPhotoURLs.remove(at: index)
        }
        
        // Remove progress
        uploadProgress.removeValue(forKey: id)
        
        // ✅ FIX 1: Reset flag after short delay if all photos removed
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            await MainActor.run {
                if self.loadedImages.isEmpty && self.selectedPhotos.isEmpty {
                    self.shouldIgnorePhotoChanges = false
                    print("✅ Flag reset: Ready for new photos")
                }
            }
        }
    }
    
    func cleanupAllTempFiles() {
        for (_, url) in tempFileUrls {
            try? FileManager.default.removeItem(at: url)
        }
        tempFileUrls.removeAll()
        print("🗑️ Cleaned up all temp files")
    }
    
    func resetForm() {
        // Clean up temp files
        cleanupAllTempFiles()
        
        // Reset all state
        shouldIgnorePhotoChanges = true
        selectedPhotos = []
        loadedImages = []
        uploadedPhotoURLs = []
        uploadProgress = [:]
        isUploadingPhotos = false
        rating = 0
        comment = ""
        visibility = .public
        selectedPlaceResult = nil
        isSubmitting = false
        errorMessage = nil
        selectedPhotoIndex = nil
        
        // Reset flag after clearing
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            await MainActor.run {
                self.shouldIgnorePhotoChanges = false
                print("✅ Form reset complete - ready for new visit")
            }
        }
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
    
    func uploadPhotos() async throws {
        guard !loadedImages.isEmpty else { return }
        guard let user = AuthManager.shared.currentUser else {
            throw APIError.unauthorized
        }
        
        await MainActor.run {
            isUploadingPhotos = true
        }
        
        let images = loadedImages.map { $0.image }
        let ids = loadedImages.map { $0.id }
        
        let urls = try await PhotoUploadService.shared.uploadPhotos(
            images,
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
            self.uploadedPhotoURLs = urls
            self.isUploadingPhotos = false
            self.uploadProgress = [:]
        }
    }
    
    func submitVisit() async {
        guard isValid else { return }
        
        // ✅ CLIENT VALIDATION - Before any network activity
        if loadedImages.count > maxPhotos {
            await MainActor.run {
                errorMessage = "Maximum \(maxPhotos) photos allowed"
                showErrorAlert = true
            }
            return
        }
        
        guard let placeResult = selectedPlaceResult else {
            await MainActor.run {
                errorMessage = "Please select a place"
                showErrorAlert = true
            }
            return
        }
        
        print("🚀 [AddVisit] Submitting visit for: \(placeResult.displayName)")
        
        isSubmitting = true
        errorMessage = nil
        
        do {
            // Photos already uploaded in loadPhotos()
            
            var requestBody: [String: Any] = [
                "comment": comment.trimmingCharacters(in: .whitespacesAndNewlines),
                "photo_urls": uploadedPhotoURLs,
                "visibility": visibility.rawValue
            ]
            
            // ✅ Only include rating if user selected one (rating is optional)
            if rating > 0 {
                requestBody["rating"] = rating
            }
            
            if let dbPlaceId = placeResult.dbPlaceId {
                requestBody["place_id"] = dbPlaceId
            } else if placeResult.source == .apple, let appleId = placeResult.applePlaceId {
                // ✅ FIXED: Send ALL Apple place fields to edge function
                var applePlaceData: [String: Any] = [
                    "apple_place_id": appleId,
                    "name": placeResult.displayName,
                    "lat": placeResult.lat,
                    "lng": placeResult.lng,
                    "city": placeResult.appleFullData?.city ?? "",  // ✅ REQUIRED
                ]
                
                // ✅ Address fields
                if let address = placeResult.formattedAddress, !address.isEmpty {
                    applePlaceData["address"] = address
                }
                if let ward = placeResult.appleFullData?.ward {
                    applePlaceData["ward"] = ward
                }
                if let postalCode = placeResult.appleFullData?.postalCode {
                    applePlaceData["postal_code"] = postalCode
                }
                if let country = placeResult.appleFullData?.country {
                    applePlaceData["country"] = country
                }
                if let countryCode = placeResult.appleFullData?.countryCode {
                    applePlaceData["country_code"] = countryCode
                }
                
                // ✅ Contact info
                if let phone = placeResult.appleFullData?.phone {
                    applePlaceData["phone"] = phone
                }
                if let website = placeResult.appleFullData?.website {
                    applePlaceData["website"] = website
                }
                
                // ✅ Categories
                if let categories = placeResult.appleFullData?.categories, !categories.isEmpty {
                    applePlaceData["categories"] = categories
                }
                
                // ✅ Multilingual names (if available)
                if let nameJa = placeResult.appleFullData?.nameJa {
                    applePlaceData["name_ja"] = nameJa
                }
                if let nameZh = placeResult.appleFullData?.nameZh {
                    applePlaceData["name_zh"] = nameZh
                }
                
                // ✅ Time zone (already a String, no need for .identifier)
                if let timeZone = placeResult.appleFullData?.timeZone {
                    applePlaceData["time_zone"] = timeZone
                }
                
                requestBody["apple_place_data"] = applePlaceData
                
                print("📦 [AddVisit] Sending Apple place data with \(applePlaceData.count) fields")
            } else if placeResult.source == .google, let googleId = placeResult.googlePlaceId {
                requestBody["google_place_data"] = [
                    "google_place_id": googleId,
                    "name": placeResult.displayName,
                    "address": placeResult.formattedAddress ?? "",
                    "lat": placeResult.lat,
                    "lng": placeResult.lng,
                    "categories": placeResult.categories ?? []
                ]
            }
            
            let response: CreateVisitResponse = try await client.post(
                path: "/functions/v1/visits-create-with-place",
                body: requestBody
            )
            
            print("✅ [AddVisit] Success! Visit ID: \(response.visitId)")
            
            // ✅ Notify parent view to refresh only this place
            onVisitPosted?(response.placeId)
            
            await MainActor.run {
                isSubmitting = false
                // ✅ Show toast instead of alert
                ToastManager.shared.showSuccess("Visit posted!")
            }
            
            // ✅ Small delay then dismiss and reset
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            
            await MainActor.run {
                self.showSuccess = true  // Trigger dismiss
                self.resetForm()
            }
        } catch let error as APIError {
            let userMessage: String
            switch error {
            case .unauthorized:
                userMessage = NSLocalizedString("error.unauthorized", comment: "")
            case .badRequest(let message):
                userMessage = message
            case .rateLimitExceeded:
                userMessage = NSLocalizedString("error.rate_limit", comment: "")
            case .serverError:
                userMessage = "Server error. Please try again or contact support."
            case .invalidResponse:
                userMessage = NSLocalizedString("error.network", comment: "")
            case .decodingFailed:
                userMessage = NSLocalizedString("error.decode", comment: "")
            case .unknown:
                userMessage = NSLocalizedString("error.unknown", comment: "")
            }
            
            print("❌ [AddVisit] Error: \(error)")
            
            await MainActor.run {
                isSubmitting = false
                errorMessage = userMessage
                showErrorAlert = true
            }
        } catch {
            print("❌ [AddVisit] Unexpected error: \(error)")
            
            await MainActor.run {
                isSubmitting = false
                errorMessage = error.localizedDescription
                showErrorAlert = true
            }
        }
    }
}

struct AddVisitView: View {
    var prefilledPlace: PlaceSearchResult? = nil
    var showBackButton: Bool = false
    var onVisitPosted: ((String) -> Void)? = nil  // ✅ Callback with placeId
    
    @StateObject private var viewModel = AddVisitViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(white: 0.97)
    }
    
    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                navigationBar
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        photosSection
                        placeSection
                        ratingSection
                        commentSection
                        visibilitySection
                        Spacer(minLength: 60)
                    }
                    .padding(.top, 16)
                }
            }
            // ✅ BLOCK EVERYTHING when submitting OR search overlay is up
            .disabled(viewModel.isSubmitting || viewModel.showSearchOverlay)
            
            // ✅ SIMPLE LOADING - No progress, just spinner
            if viewModel.isSubmitting {
                loadingOverlay
            }
            
            if let index = viewModel.selectedPhotoIndex {
                fullscreenPhotoViewer(index: index)
            }
            
            if viewModel.showSearchOverlay {
                SearchPlaceOverlay(
                    isPresented: $viewModel.showSearchOverlay,
                    onPlaceSelected: { result in
                        viewModel.selectedPlaceResult = result
                    }
                )
            }
        }
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong")
        }
        .onChange(of: viewModel.showSuccess) { _, isSuccess in
            if isSuccess {
                dismiss()  // ✅ Auto-dismiss when success
            }
        }
        .onAppear {
            // ✅ Pass callback to ViewModel
            viewModel.onVisitPosted = onVisitPosted
            
            // ✅ Pre-fill place if provided
            if let prefilled = prefilledPlace {
                viewModel.selectedPlaceResult = prefilled
                print("✅ [AddVisit] Pre-filled place: \(prefilled.displayName)")
            }
        }
        .onChange(of: viewModel.selectedPhotos) { _, _ in
            Task { await viewModel.loadPhotos() }
        }
        .onDisappear {
            viewModel.cleanupAllTempFiles()
        }
    }
    private var navigationBar: some View {
        HStack(spacing: 16) {
            // ✅ Left side
            if showBackButton {
                Button(action: {
                    dismiss()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 16))
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                }
            }
            
            Spacer()
            
            // ✅ Right side - Post button
            Button {
                Task { await viewModel.submitVisit() }
            } label: {
                Text("Post")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if viewModel.isValid {
                                Design.accentGradient
                            } else {
                                Color.gray.opacity(0.5)
                            }
                        }
                    )
                    .cornerRadius(20)
            }
            .disabled(!viewModel.isValid || viewModel.isSubmitting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color.black : Color.white)
        .overlay {
            // ✅ Centered title
            Text("Add Visit")
                .font(.system(size: 18, weight: .bold))
        }
    }
    
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photos")
                    .font(.system(size: 15, weight: .semibold))
                
                Text("\(viewModel.loadedImages.count)/\(viewModel.maxPhotos)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !viewModel.loadedImages.isEmpty {
                    Button {
                        viewModel.cleanupAllTempFiles()
                        viewModel.shouldIgnorePhotoChanges = true  // Prevent reload
                        viewModel.selectedPhotos = []
                        viewModel.loadedImages = []
                        viewModel.uploadedPhotoURLs = []
                        
                        // ✅ FIX 1: Reset flag after clearing all
                        Task {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            await MainActor.run {
                                viewModel.shouldIgnorePhotoChanges = false
                                print("✅ Flag reset after Clear All")
                            }
                        }
                    } label: {
                        Text("Clear All")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Design.accent)
                    }
                }
            }
            .padding(.horizontal, 16)
            
            if viewModel.loadedImages.isEmpty {
                PhotosPicker(
                    selection: $viewModel.selectedPhotos,
                    maxSelectionCount: viewModel.maxPhotos,
                    matching: .images
                ) {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 40))
                            .foregroundColor(Design.accent.opacity(0.6))
                        
                        Text("Add Photos")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text("Up to \(viewModel.maxPhotos) photos")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 213)  // CHANGED: Match image height
                    .background(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.loadedImages, id: \.id) { item in  // CHANGED: Use UUID as id
                            ZStack(alignment: .topTrailing) {
                                // ✅ FIX 2: Image with tap gesture
                                ZStack {
                                    Image(uiImage: item.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 160, height: 213)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    
                                    // Progress overlay
                                    if let progress = viewModel.uploadProgress[item.id], progress < 1.0 {
                                        ZStack {
                                            Color.black.opacity(0.5)
                                            
                                            VStack(spacing: 8) {
                                                ProgressView(value: progress)
                                                    .progressViewStyle(LinearProgressViewStyle(tint: .white))
                                                    .frame(width: 100)
                                                
                                                Text("\(Int(progress * 100))%")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                                .onTapGesture {
                                    if viewModel.uploadProgress[item.id] == nil || viewModel.uploadProgress[item.id] == 1.0 {
                                        if let index = viewModel.loadedImages.firstIndex(where: { $0.id == item.id }) {
                                            viewModel.selectedPhotoIndex = index
                                        }
                                    }
                                }
                                
                                // ✅ Remove button - white stroke only
                                Button {
                                    viewModel.removePhoto(withId: item.id)
                                } label: {
                                    ZStack {
                                        // Larger tap target (invisible)
                                        Circle()
                                            .fill(.clear)
                                            .frame(width: 44, height: 44)
                                        
                                        // Visual: white stroke X only
                                        Image(systemName: "xmark")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 0)
                                    }
                                }
                                .buttonStyle(.plain)
                                .zIndex(10)
                                .disabled(viewModel.uploadProgress[item.id] != nil && viewModel.uploadProgress[item.id] != 1.0)
                                .opacity((viewModel.uploadProgress[item.id] != nil && viewModel.uploadProgress[item.id] != 1.0) ? 0.3 : 1.0)
                                .padding(8)
                            }
                        }
                        
                        if viewModel.loadedImages.count < viewModel.maxPhotos {
                            PhotosPicker(
                                selection: $viewModel.selectedPhotos,
                                maxSelectionCount: viewModel.maxPhotos,
                                matching: .images
                            ) {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Design.accent.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                                    .frame(width: 160, height: 213)  // ✅ BIGGER
                                    .overlay {
                                        Image(systemName: "plus")
                                            .font(.system(size: 32, weight: .medium))  // ✅ BIGGER
                                            .foregroundColor(Design.accent.opacity(0.7))
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private var placeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)
            
            Button {
                viewModel.showSearchOverlay = true
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(viewModel.hasPlace ? Design.accent : Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.hasPlace ? viewModel.displayPlaceName : "Select a place")
                            .font(.system(size: 15, weight: viewModel.hasPlace ? .semibold : .regular))
                            .foregroundColor(viewModel.hasPlace ? .primary : .secondary)
                        
                        if !viewModel.hasPlace {
                            Text("Required")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rating")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)
            
            HStack(spacing: 16) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.rating = star
                        }
                    } label: {
                        Image(systemName: star <= viewModel.rating ? "star.fill" : "star")
                            .font(.system(size: 28))
                            .foregroundColor(star <= viewModel.rating ? Design.accent : Design.accent.opacity(0.3))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Share your thoughts")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)
            
            VStack(alignment: .trailing, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if viewModel.comment.isEmpty {
                        Text("Share your experience...")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.top, 12)
                            .padding(.leading, 14)
                    }
                    
                    TextEditor(text: $viewModel.comment)
                        .font(.system(size: 15))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(8)
                        .onChange(of: viewModel.comment) { _, newValue in
                            if newValue.count > viewModel.maxCommentLength {
                                viewModel.comment = String(newValue.prefix(viewModel.maxCommentLength))
                            }
                        }
                }
                .background(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            viewModel.comment.isEmpty ? Color.clear : Design.accent.opacity(0.5),
                            lineWidth: 1.5
                        )
                )
                
                Text("\(viewModel.comment.count)/\(viewModel.maxCommentLength)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(viewModel.comment.count >= 900 ? Design.accent : .secondary)
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who can see this?")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)
            
            VStack(spacing: 0) {
                ForEach(VisitVisibility.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.visibility = option
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(viewModel.visibility == option ? Design.accent : Color.gray.opacity(0.3))
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: option.icon)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(viewModel.visibility == option ? .white : .secondary)
                                }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text(option.description)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if viewModel.visibility == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(Design.accent)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(viewModel.visibility == option ? Design.accent.opacity(0.06) : Color.clear)
                    }
                    
                    if option != VisitVisibility.allCases.last {
                        Divider().padding(.leading, 66)
                    }
                }
            }
            .background(colorScheme == .dark ? Color(white: 0.12) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }
    
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
    
    // ✅ SIMPLE LOADING - Just a spinner, no progress
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text("Posting your visit...")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

enum VisitVisibility: String, CaseIterable, Codable {
    case `public` = "public", friends = "friends", `private` = "private"
    
    var title: String {
        switch self {
        case .public: return "Public"
        case .friends: return "Friends"
        case .private: return "Private"
        }
    }
    var description: String {
        switch self {
        case .public: return "Everyone can see"
        case .friends: return "Only friends"
        case .private: return "Only you"
        }
    }
    var icon: String {
        switch self {
        case .public: return "globe.americas.fill"
        case .friends: return "person.2.fill"
        case .private: return "lock.fill"
        }
    }
}

#Preview { AddVisitView() }
