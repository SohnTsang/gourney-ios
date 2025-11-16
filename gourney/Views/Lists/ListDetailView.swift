// Views/Lists/ListDetailView.swift
// ✅ Redesigned with Gourney design system + shared PlaceRowView

import SwiftUI
import PhotosUI
import Combine

struct ListDetailView: View {
    let list: RestaurantList
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = ListDetailViewModel()
    @StateObject private var locationManager = LocationManager.shared
    @State private var showAddPlace = false
    @State private var showSettings = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(colorScheme == .dark ? .black : .systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Cover Image
                        CoverImageView(
                            coverUrl: list.coverPhotoUrl,
                            onUpload: { image in
                                await viewModel.uploadCover(listId: list.id, image: image)
                            }
                        )
                        
                        // List Info Section
                        VStack(spacing: 12) {
                            // Stats Row - Places on left, Likes on right
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
                                    HStack(spacing: 6) {
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                                        Text("\(list.likesCount ?? 0)")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.primary)
                                        Text("likes")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
                        
                        // Places List
                        if viewModel.places.isEmpty && !viewModel.isLoading {
                            EmptyPlacesView(showAddPlace: $showAddPlace)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.places) { item in
                                    PlaceRowView(
                                        item: PlaceRowItem(from: item),
                                        distance: item.place.map { locationManager.formattedDistance(from: $0.coordinate) } ?? nil,
                                        showRemoveButton: true,
                                        onRemove: {
                                            Task {
                                                await viewModel.removePlace(listId: list.id, itemId: item.id)
                                            }
                                        }
                                    )
                                    .contentShape(Rectangle())
                                    
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
            .navigationTitle(list.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    }
                    .simultaneousGesture(LongPressGesture().onEnded { _ in
                        showAddPlace = true
                    })
                    .contextMenu {
                        Button {
                            showAddPlace = true
                        } label: {
                            Label("Add Places", systemImage: "plus")
                        }
                        
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddPlace) {
                AddPlaceToListSheet(listId: list.id, viewModel: viewModel)
            }
            .overlay {
                if showSettings {
                    ListSettingsSheet(list: list, isPresented: $showSettings)
                }
            }
            .task {
                await viewModel.loadPlaces(listId: list.id)
            }
        }
    }
}

// MARK: - Cover Image View

struct CoverImageView: View {
    let coverUrl: String?
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
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 60))
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3))
            
            VStack(spacing: 8) {
                Text("No Places Yet")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Add places from Discover or your visits")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
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
    
    private let client = SupabaseClient.shared
    
    func loadPlaces(listId: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let body: [String: String] = ["list_id": listId]
            let response: ListDetailResponse = try await client.post(
                path: "/functions/v1/lists-get-detail",
                body: body,
                requiresAuth: true
            )
            
            places = response.items
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
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

// MARK: - Settings Sheet

struct ListSettingsSheet: View {
    let list: RestaurantList
    @Binding var isPresented: Bool
    
    @State private var title: String
    @State private var description: String
    @State private var selectedVisibility: String
    @State private var isSaving = false
    @Environment(\.colorScheme) private var colorScheme
    
    // Check if this is a default list
    private var isDefaultList: Bool {
        let wantToTryTitle = NSLocalizedString("lists.default.want_to_try", comment: "")
        let favoritesTitle = NSLocalizedString("lists.default.favorites", comment: "")
        return list.title == wantToTryTitle || list.title == favoritesTitle
    }
    
    init(list: RestaurantList, isPresented: Binding<Bool>) {
        self.list = list
        self._isPresented = isPresented
        _title = State(initialValue: list.title)
        _description = State(initialValue: list.description ?? "")
        _selectedVisibility = State(initialValue: list.visibility)
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isSaving {
                        isPresented = false
                    }
                }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("Settings")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button("Save") {
                        saveSettings()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(title.isEmpty ? .secondary : Color(red: 1.0, green: 0.4, blue: 0.4))
                    .disabled(isSaving || title.isEmpty || isDefaultList)
                    .opacity(isDefaultList ? 0 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                Divider()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            TextField("List name", text: $title)
                                .textFieldStyle(.plain)
                                .font(.system(size: 16))
                                .foregroundColor(isDefaultList ? .secondary : .primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(isDefaultList ? Color(.systemGray5) : (colorScheme == .dark ? Color(.systemGray6) : Color.white))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(isDefaultList ? Color.clear : Color(.systemGray4), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .disabled(isDefaultList)
                        }
                        
                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            ZStack(alignment: .topLeading) {
                                if description.isEmpty && !isDefaultList {
                                    Text("Add a description (optional)")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary.opacity(0.5))
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 16)
                                }
                                
                                TextEditor(text: $description)
                                    .font(.system(size: 16))
                                    .foregroundColor(isDefaultList ? .secondary : .primary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(height: 100)
                                    .scrollContentBackground(.hidden)
                                    .background(isDefaultList ? Color(.systemGray5) : (colorScheme == .dark ? Color(.systemGray6) : Color.white))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isDefaultList ? Color.clear : Color(.systemGray4), lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .disabled(isDefaultList)
                            }
                        }
                        
                        // Visibility
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Visibility")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            VStack(spacing: 0) {
                                VisibilityOption(
                                    icon: "globe",
                                    title: "Public",
                                    subtitle: "Anyone can view",
                                    isSelected: selectedVisibility == "public",
                                    action: { selectedVisibility = "public" }
                                )
                                
                                Divider()
                                    .padding(.leading, 50)
                                
                                VisibilityOption(
                                    icon: "person.2.fill",
                                    title: "Friends",
                                    subtitle: "Only followers can view",
                                    isSelected: selectedVisibility == "friends",
                                    action: { selectedVisibility = "friends" }
                                )
                                
                                Divider()
                                    .padding(.leading, 50)
                                
                                VisibilityOption(
                                    icon: "lock.fill",
                                    title: "Private",
                                    subtitle: "Only you can view",
                                    isSelected: selectedVisibility == "private",
                                    action: { selectedVisibility = "private" }
                                )
                            }
                            .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(20)
                }
            }
            .frame(width: min(UIScreen.main.bounds.width - 40, 400))
            .frame(maxHeight: 600)
            .background(colorScheme == .dark ? Color(.systemBackground) : Color(.systemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
    }
    
    private func saveSettings() {
        Task {
            isSaving = true
            // Implement save via lists-update endpoint
            isSaving = false
            isPresented = false
        }
    }
}

struct VisibilityOption: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? Color(red: 1.0, green: 0.4, blue: 0.4) : .secondary)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
