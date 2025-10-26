//
//  AddVisitView.swift
//  gourney
//

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
    @Published var isUploading = false
    @Published var isSubmitting = false
    @Published var uploadProgress: Double = 0
    @Published var errorMessage: String?
    @Published var showSuccess = false
    @Published var selectedPlaceResult: PlaceSearchResult?
    @Published var selectedPhotoIndex: Int?
    @Published var showSearchOverlay = false
    
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
        
        for item in selectedPhotos {
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
        guard let user = AuthManager.shared.currentUser else { throw APIError.unauthorized }
        
        isUploading = true
        uploadProgress = 0
        uploadedPhotoURLs.removeAll()
        
        let urls = try await PhotoUploadService.shared.uploadPhotos(
            loadedImages,
            userId: user.id,
            progressHandler: { index, progress in
                Task { @MainActor in
                    self.uploadProgress = (Double(index) + progress) / Double(self.loadedImages.count)
                }
            }
        )
        
        await MainActor.run {
            self.uploadedPhotoURLs = urls
            self.isUploading = false
        }
    }
    
    func submitVisit() async {
        guard isValid else { return }
        isSubmitting = true
        errorMessage = nil
        
        do {
            if !loadedImages.isEmpty && uploadedPhotoURLs.isEmpty {
                try await uploadPhotos()
            }
            
            guard let placeResult = selectedPlaceResult else { return }
            
            var requestBody: [String: Any] = [
                "rating": rating,
                "comment": comment.trimmingCharacters(in: .whitespacesAndNewlines),
                "photo_urls": uploadedPhotoURLs,
                "visibility": visibility.rawValue
            ]
            
            if let dbPlaceId = placeResult.dbPlaceId {
                requestBody["place_id"] = dbPlaceId
            } else if placeResult.source == .google, let googleId = placeResult.googlePlaceId {
                requestBody["google_place_data"] = [
                    "google_place_id": googleId,
                    "name": placeResult.displayName,
                    "address": placeResult.formattedAddress ?? "",
                    "lat": placeResult.lat,
                    "lng": placeResult.lng,
                    "categories": placeResult.categories ?? []
                ]
            } else if placeResult.source == .apple, let appleId = placeResult.applePlaceId {
                requestBody["apple_place_data"] = [
                    "apple_place_id": appleId,
                    "name": placeResult.displayName,
                    "address": placeResult.formattedAddress ?? "",
                    "lat": placeResult.lat,
                    "lng": placeResult.lng
                ]
            }
            
            let _: CreateVisitResponse = try await client.post(
                path: "/functions/v1/visits-create-with-place",
                body: requestBody
            )
            
            await MainActor.run {
                isSubmitting = false
                showSuccess = true
                loadedImages = []
                selectedPhotos = []
            }
        } catch {
            await MainActor.run {
                isSubmitting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct AddVisitView: View {
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
            
            if viewModel.isUploading || viewModel.isSubmitting {
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
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .onDisappear {
            viewModel.loadedImages = []
            viewModel.selectedPhotos = []
        }
    }
    
    private var navigationBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.accent)
                    .frame(width: 32, height: 32)
                    .background(Design.accent.opacity(0.1))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text("Add Visit")
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
            
            Spacer()
            
            Button {
                Task { await viewModel.submitVisit() }
            } label: {
                Text("Post")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 32)
                    .background(viewModel.isValid ? Design.accentGradient : LinearGradient(colors: [Color.gray.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                    .clipShape(Capsule())
            }
            .disabled(!viewModel.isValid)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(colorScheme == .dark ? Color.black : .white)
    }
    
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Photos")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(viewModel.loadedImages.count)/\(viewModel.maxPhotos)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if viewModel.loadedImages.count < viewModel.maxPhotos {
                        PhotosPicker(
                            selection: $viewModel.selectedPhotos,
                            maxSelectionCount: viewModel.maxPhotos - viewModel.loadedImages.count,
                            matching: .images
                        ) {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Design.accent.opacity(0.08))
                                .frame(width: 160, height: 200)
                                .overlay {
                                    VStack(spacing: 8) {
                                        Circle()
                                            .fill(Design.accentGradient)
                                            .frame(width: 44, height: 44)
                                            .overlay {
                                                Image(systemName: "plus")
                                                    .font(.system(size: 20, weight: .semibold))
                                                    .foregroundColor(.white)
                                            }
                                        Text("Add")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Design.accent)
                                    }
                                }
                        }
                        .onChange(of: viewModel.selectedPhotos) { _, _ in
                            Task { await viewModel.loadPhotos() }
                        }
                    }
                    
                    ForEach(Array(viewModel.loadedImages.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .topTrailing) {
                            Button {
                                viewModel.selectedPhotoIndex = index
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 160, height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    viewModel.loadedImages.remove(at: index)
                                    viewModel.selectedPhotos.remove(at: index)
                                }
                            } label: {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                            }
                            .padding(8)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private var placeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where did you visit?")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)
            
            Button {
                viewModel.showSearchOverlay = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Design.accent)
                    
                    if viewModel.hasPlace {
                        HStack {
                            Text(viewModel.displayPlaceName)
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                            Spacer()
                            Button {
                                withAnimation {
                                    viewModel.selectedPlaceResult = nil
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("Search for a place")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .padding(14)
                .background(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            viewModel.hasPlace ? Design.accent.opacity(0.5) : Color.clear,
                            lineWidth: 1.5
                        )
                )
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How was it?")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)
            
            HStack(spacing: 14) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
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
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 8)
                        .frame(width: 70, height: 70)
                    
                    Circle()
                        .trim(from: 0, to: viewModel.isUploading ? viewModel.uploadProgress : 0.7)
                        .stroke(Design.accentGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 70, height: 70)
                        .rotationEffect(.degrees(-90))
                }
                
                VStack(spacing: 6) {
                    Text(viewModel.isUploading ? "Uploading..." : "Posting...")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if viewModel.isUploading {
                        Text("\(Int(viewModel.uploadProgress * 100))%")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .padding(32)
            .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
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
