//
//  AddVisitView.swift
//  gourney
//
//  Modern Add Visit View with red-pink gradient theme
//

import SwiftUI
import PhotosUI
import Combine

// MARK: - Design System

struct DesignSystem {
    static let primaryGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let primaryColor = Color(red: 1.0, green: 0.4, blue: 0.4)
    static let lightGray = Color(.systemGray6)
    static let cardShadow = Color.black.opacity(0.08)
    static let activeBorderColor = Color(red: 1.0, green: 0.4, blue: 0.4)
}

// MARK: - View Model

@MainActor
class AddVisitViewModel: ObservableObject {
    @Published var selectedPhotos: [PhotosPickerItem] = []
    @Published var loadedImages: [UIImage] = []
    @Published var uploadedPhotoURLs: [String] = []
    @Published var rating: Int = 0
    @Published var comment: String = ""
    @Published var visibility: VisitVisibility = .public
    @Published var searchQuery: String = ""
    @Published var isUploading = false
    @Published var isSubmitting = false
    @Published var uploadProgress: Double = 0
    @Published var errorMessage: String?
    @Published var showSuccess = false
    @Published var selectedPlace: Place?
    @Published var applePlaceData: ApplePlaceData?
    @Published var manualPlaceData: ManualPlaceData?
    
    let maxPhotos = 5
    let maxCommentLength = 1000
    private let client = SupabaseClient.shared
    
    var displayPlaceName: String {
        if let place = selectedPlace { return place.displayName }
        if let appleData = applePlaceData { return appleData.name }
        if let manualData = manualPlaceData { return manualData.name }
        return ""
    }
    
    var hasPlace: Bool {
        selectedPlace != nil || applePlaceData != nil || manualPlaceData != nil
    }
    
    var isValid: Bool {
        rating > 0 && (!uploadedPhotoURLs.isEmpty || !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    
    func loadPhotos() async {
        guard !selectedPhotos.isEmpty else { return }
        var newImages: [UIImage] = []
        for item in selectedPhotos {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                newImages.append(image)
            }
        }
        await MainActor.run { self.loadedImages = newImages }
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
            
            var requestBody: [String: Any] = [
                "rating": rating,
                "comment": comment.trimmingCharacters(in: .whitespacesAndNewlines),
                "photo_urls": uploadedPhotoURLs,
                "visibility": visibility.rawValue
            ]
            
            if let placeId = selectedPlace?.id {
                requestBody["place_id"] = placeId
            } else if let appleData = applePlaceData {
                requestBody["apple_place_data"] = [
                    "apple_place_id": appleData.applePlaceId,
                    "name": appleData.name,
                    "address": appleData.address,
                    "city": appleData.city,
                    "lat": appleData.lat,
                    "lng": appleData.lng
                ]
            } else if let manualData = manualPlaceData {
                requestBody["manual_place"] = [
                    "name": manualData.name,
                    "lat": manualData.lat,
                    "lng": manualData.lng
                ]
            }
            
            let _: CreateVisitResponse = try await client.post(
                path: "/functions/v1/visits-create-with-place",
                body: requestBody
            )
            
            await MainActor.run {
                isSubmitting = false
                showSuccess = true
            }
        } catch {
            await MainActor.run {
                isSubmitting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Main View

struct AddVisitView: View {
    @StateObject private var viewModel = AddVisitViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color.black : Color(.systemGroupedBackground))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        photosSection
                        placeSearchSection
                        ratingSection
                        commentSection
                        visibilitySection
                        Spacer(minLength: 100)
                    }
                    .padding(.top, 16)
                }
                
                if viewModel.isUploading || viewModel.isSubmitting {
                    loadingOverlay
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DesignSystem.primaryColor)
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .principal) {
                    Text("Add New Visit")
                        .font(.system(size: 20, weight: .bold))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Post") {
                        Task { await viewModel.submitVisit() }
                    }
                    .foregroundStyle(viewModel.isValid ? DesignSystem.primaryColor : Color.gray)
                    .fontWeight(.bold)
                    .disabled(!viewModel.isValid)
                }
            }
            .alert("Success! ✨", isPresented: $viewModel.showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your visit has been posted!")
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "photo.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignSystem.primaryGradient)
                Text("Photos")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Text("\(viewModel.loadedImages.count)/\(viewModel.maxPhotos)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if viewModel.loadedImages.count < viewModel.maxPhotos {
                        PhotosPicker(
                            selection: $viewModel.selectedPhotos,
                            maxSelectionCount: viewModel.maxPhotos - viewModel.loadedImages.count,
                            matching: .images
                        ) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(DesignSystem.lightGray)
                                    .frame(width: 120, height: 120)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                                            .foregroundStyle(DesignSystem.primaryGradient)
                                    )
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(DesignSystem.primaryGradient)
                                        .frame(width: 44, height: 44)
                                        .overlay {
                                            Image(systemName: "plus")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                    Text("Add Photos")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(DesignSystem.primaryGradient)
                                }
                            }
                        }
                        .onChange(of: viewModel.selectedPhotos) { _, _ in
                            Task { await viewModel.loadPhotos() }
                        }
                    }
                    
                    ForEach(Array(viewModel.loadedImages.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .shadow(color: DesignSystem.cardShadow, radius: 8, x: 0, y: 4)
                            
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    viewModel.loadedImages.remove(at: index)
                                    viewModel.selectedPhotos.remove(at: index)
                                }
                            } label: {
                                Circle()
                                    .fill(Color.black.opacity(0.7))
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                            }
                            .padding(8)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    private var placeSearchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "location.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignSystem.primaryGradient)
                Text("Where did you visit?")
                    .font(.system(size: 18, weight: .bold))
            }
            .padding(.horizontal, 20)
            
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignSystem.primaryGradient)
                    .font(.system(size: 16, weight: .semibold))
                
                if viewModel.hasPlace {
                    HStack {
                        Text(viewModel.displayPlaceName)
                            .font(.system(size: 15))
                        Spacer()
                        Button {
                            withAnimation {
                                viewModel.selectedPlace = nil
                                viewModel.applePlaceData = nil
                                viewModel.manualPlaceData = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    TextField("Search for a place...", text: $viewModel.searchQuery)
                        .font(.system(size: 15))
                        .autocorrectionDisabled()
                }
                
                Image(systemName: "location.circle.fill")
                    .foregroundStyle(DesignSystem.primaryGradient)
                    .font(.system(size: 20))
            }
            .padding(16)
            .background(DesignSystem.lightGray)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        viewModel.searchQuery.isEmpty && !viewModel.hasPlace ? Color.clear : DesignSystem.activeBorderColor,
                        lineWidth: 2
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: DesignSystem.cardShadow, radius: 6, x: 0, y: 3)
            .padding(.horizontal, 20)
        }
    }
    
    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "star.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignSystem.primaryGradient)
                Text("How was it?")
                    .font(.system(size: 18, weight: .bold))
            }
            .padding(.horizontal, 20)
            
            HStack(spacing: 16) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            viewModel.rating = star
                        }
                    } label: {
                        Image(systemName: star <= viewModel.rating ? "star.fill" : "star")
                            .font(.system(size: 40))
                            .foregroundStyle(DesignSystem.primaryGradient)
                            .shadow(
                                color: star <= viewModel.rating ? DesignSystem.primaryColor.opacity(0.5) : .clear,
                                radius: 8, x: 0, y: 4
                            )
                            .scaleEffect(star <= viewModel.rating ? 1.1 : 1.0)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignSystem.primaryGradient)
                Text("Share your thoughts")
                    .font(.system(size: 18, weight: .bold))
            }
            .padding(.horizontal, 20)
            
            VStack(alignment: .trailing, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if viewModel.comment.isEmpty {
                        Text("Share your experience...")
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(.top, 12)
                            .padding(.leading, 16)
                    }
                    TextEditor(text: $viewModel.comment)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .onChange(of: viewModel.comment) { _, newValue in
                            if newValue.count > viewModel.maxCommentLength {
                                viewModel.comment = String(newValue.prefix(viewModel.maxCommentLength))
                            }
                        }
                }
                .background(DesignSystem.lightGray)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            viewModel.comment.isEmpty ? Color.clear : DesignSystem.activeBorderColor,
                            lineWidth: 2
                        )
                )
                .shadow(color: DesignSystem.cardShadow, radius: 6, x: 0, y: 3)
                
                Text("\(viewModel.comment.count)/\(viewModel.maxCommentLength)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(
                        viewModel.comment.count >= viewModel.maxCommentLength * 9 / 10 ?
                        DesignSystem.primaryColor : .secondary
                    )
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "eye.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DesignSystem.primaryGradient)
                Text("Who can see this?")
                    .font(.system(size: 18, weight: .bold))
            }
            .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                ForEach(VisitVisibility.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.visibility = option
                        }
                    } label: {
                        HStack(spacing: 16) {
                            Circle()
                                .fill(viewModel.visibility == option ? DesignSystem.primaryColor : DesignSystem.lightGray)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Image(systemName: option.icon)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(viewModel.visibility == option ? .white : .secondary)
                                }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text(option.description)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if viewModel.visibility == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(DesignSystem.primaryGradient)
                            }
                        }
                        .padding(16)
                        .background(viewModel.visibility == option ? DesignSystem.primaryColor.opacity(0.08) : Color.clear)
                    }
                    
                    if option != VisitVisibility.allCases.last {
                        Divider().padding(.leading, 76)
                    }
                }
            }
            .background(DesignSystem.lightGray)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: DesignSystem.cardShadow, radius: 6, x: 0, y: 3)
            .padding(.horizontal, 20)
        }
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 8)
                        .frame(width: 80, height: 80)
                    Circle()
                        .trim(from: 0, to: viewModel.isUploading ? viewModel.uploadProgress : 0.7)
                        .stroke(DesignSystem.primaryGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 8) {
                    Text(viewModel.isUploading ? "Uploading photos..." : "Posting visit...")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    if viewModel.isUploading {
                        Text("\(Int(viewModel.uploadProgress * 100))%")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black.opacity(0.85))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
        }
    }
}

enum VisitVisibility: String, CaseIterable, Codable {
    case `public` = "public", friends = "friends", `private` = "private"
    
    var title: String {
        switch self {
        case .public: return "Public"
        case .friends: return "Friends Only"
        case .private: return "Private"
        }
    }
    var description: String {
        switch self {
        case .public: return "Visible to everyone"
        case .friends: return "Visible only to friends"
        case .private: return "Visible only to you"
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

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview { AddVisitView() }
