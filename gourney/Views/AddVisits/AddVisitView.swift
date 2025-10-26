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
    @Published var loadedImages: [UIImage] = []
    @Published var uploadedPhotoURLs: [String] = []
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
        hasPlace && rating > 0 && (!uploadedPhotoURLs.isEmpty || !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    
    func loadPhotos() async {
        guard !selectedPhotos.isEmpty else { return }
        var newImages: [UIImage] = []
        
        for (index, item) in selectedPhotos.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let resized = resizeImageForPreview(image)
                newImages.append(resized)
            }
        }
        
        await MainActor.run { self.loadedImages = newImages }
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
        
        // ✅ NO PROGRESS LOGGING - Silent upload
        let urls = try await PhotoUploadService.shared.uploadPhotos(
            loadedImages,
            userId: user.id,
            progressHandler: { _, _ in }  // ✅ EMPTY - No progress updates
        )
        
        await MainActor.run {
            self.uploadedPhotoURLs = urls
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
            // Upload photos silently
            if !loadedImages.isEmpty && uploadedPhotoURLs.isEmpty {
                try await uploadPhotos()
            }
            
            var requestBody: [String: Any] = [
                "rating": rating,
                "comment": comment.trimmingCharacters(in: .whitespacesAndNewlines),
                "photo_urls": uploadedPhotoURLs,
                "visibility": visibility.rawValue
            ]
            
            if let dbPlaceId = placeResult.dbPlaceId {
                requestBody["place_id"] = dbPlaceId
            } else if placeResult.source == .apple, let appleId = placeResult.applePlaceId {
                // ✅ FIXED: Match RPC parameter order exactly
                var applePlaceData: [String: Any] = [
                    "apple_place_id": appleId,
                    "name": placeResult.displayName,
                    "lat": placeResult.lat,
                    "lng": placeResult.lng,
                    "city": placeResult.appleFullData?.city ?? "",  // ✅ REQUIRED
                ]
                
                // Optional fields
                if let address = placeResult.formattedAddress, !address.isEmpty {
                    applePlaceData["address"] = address
                }
                if let ward = placeResult.appleFullData?.ward {
                    applePlaceData["ward"] = ward
                }
                if let phone = placeResult.appleFullData?.phone {
                    applePlaceData["phone"] = phone
                }
                if let website = placeResult.appleFullData?.website {
                    applePlaceData["website"] = website
                }
                if let categories = placeResult.appleFullData?.categories, !categories.isEmpty {
                    applePlaceData["categories"] = categories
                }
                
                requestBody["apple_place_data"] = applePlaceData
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
            
            await MainActor.run {
                isSubmitting = false
                showSuccess = true
                loadedImages = []
                selectedPhotos = []
                uploadedPhotoURLs = []
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
    var prefilledPlace: PlaceSearchResult? = nil  // ✅ ADD THIS LINE

    @StateObject private var viewModel = AddVisitViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color(white: 0.97))
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
        .alert("Posted!", isPresented: $viewModel.showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your visit has been shared!")
        }
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong")
        }
        .onAppear {
            // ✅ ADD THIS BLOCK
            if let prefilled = prefilledPlace {
                viewModel.selectedPlaceResult = prefilled
                print("✅ [AddVisit] Pre-filled place: \(prefilled.displayName)")
            }
        }
        .onChange(of: viewModel.selectedPhotos) { _, _ in
            Task { await viewModel.loadPhotos() }
        }
    }
    private var navigationBar: some View {
        HStack(spacing: 16) {
            
            Spacer()
            
            Text("Add Visit")
                .font(.system(size: 18, weight: .bold))
            
            Spacer()
            
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
                        viewModel.selectedPhotos = []
                        viewModel.loadedImages = []
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
                    .frame(height: 180)  // ✅ BIGGER
                    .background(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(viewModel.loadedImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 160, height: 213)  // ✅ 3:4 ratio (iPhone photos)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .onTapGesture {
                                        viewModel.selectedPhotoIndex = index
                                    }
                                
                                Button {
                                    viewModel.loadedImages.remove(at: index)
                                    if index < viewModel.selectedPhotos.count {
                                        viewModel.selectedPhotos.remove(at: index)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 24))  // ✅ BIGGER
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                }
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
                ForEach(Array(viewModel.loadedImages.enumerated()), id: \.offset) { i, image in
                    Image(uiImage: image)
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
