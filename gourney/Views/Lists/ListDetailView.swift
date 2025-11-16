import SwiftUI
import PhotosUI
import Combine

struct ListDetailView: View {
    let list: RestaurantList
    
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = ListDetailViewModel()
    @State private var showAddPlace = false
    @State private var showSettings = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Cover Image
                        CoverImageView(
                            coverUrl: list.coverPhotoUrl,
                            onUpload: { image in
                                await viewModel.uploadCover(listId: list.id, image: image)
                            }
                        )
                        
                        // Content
                        VStack(spacing: 16) {
                            if viewModel.places.isEmpty && !viewModel.isLoading {
                                EmptyPlacesView(showAddPlace: $showAddPlace)
                            } else {
                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: 1),
                                    GridItem(.flexible(), spacing: 1),
                                    GridItem(.flexible(), spacing: 1)
                                ], spacing: 1) {
                                    ForEach(viewModel.places) { item in
                                        PlaceGridItem(item: item)
                                            .contextMenu {
                                                Button(role: .destructive) {
                                                    Task {
                                                        await viewModel.removePlace(listId: list.id, itemId: item.id)
                                                    }
                                                } label: {
                                                    Label("Remove", systemImage: "trash")
                                                }
                                            }
                                    }
                                }
                            }
                        }
                        .padding(.top, 16)
                    }
                }
                
                if viewModel.isLoading {
                    ProgressView()
                }
            }
            .navigationTitle(list.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
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
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAddPlace) {
                AddPlaceToListSheet(listId: list.id, viewModel: viewModel)
            }
            .sheet(isPresented: $showSettings) {
                ListSettingsSheet(list: list)
            }
            .task {
                await viewModel.loadPlaces(listId: list.id)
            }
        }
    }
}

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
                    Color.gray.opacity(0.2)
                }
            } else {
                ZStack {
                    Color.blue.opacity(0.1)
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 40))
                            .foregroundColor(.blue.opacity(0.5))
                        Text("Add Cover Photo")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            PhotosPicker(selection: $selectedItem, matching: .images) {
                HStack(spacing: 6) {
                    Image(systemName: isUploading ? "arrow.triangle.2.circlepath" : "camera.fill")
                    Text(coverUrl == nil ? "Add" : "Change")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
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
}

struct PlaceGridItem: View {
    let item: ListItem
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(1, contentMode: .fit)
            
            if let place = item.place {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.nameEn ?? "Unknown")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .foregroundColor(.white)
            }
        }
    }
}

struct EmptyPlacesView: View {
    @Binding var showAddPlace: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 60))
                .foregroundColor(.blue.opacity(0.3))
            
            VStack(spacing: 8) {
                Text("No Places Yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Add places from Discover or your visits")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { showAddPlace = true }) {
                Label("Add Places", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 180, height: 50)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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
    @Environment(\.dismiss) var dismiss
    
    @State private var title: String
    @State private var description: String
    @State private var isPublic: Bool
    @State private var isSaving = false
    
    init(list: RestaurantList) {
        self.list = list
        _title = State(initialValue: list.title)
        _description = State(initialValue: list.description ?? "")
        _isPublic = State(initialValue: list.visibility == "public")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("List name", text: $title)
                }
                
                Section("Description") {
                    TextEditor(text: $description)
                        .frame(height: 100)
                }
                
                Section {
                    Toggle(isOn: $isPublic) {
                        HStack {
                            Image(systemName: isPublic ? "globe" : "lock.fill")
                                .foregroundColor(isPublic ? .blue : .secondary)
                            VStack(alignment: .leading) {
                                Text("Public")
                                Text(isPublic ? "Anyone can view" : "Only you can view")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSettings()
                    }
                    .disabled(isSaving || title.isEmpty)
                }
            }
        }
    }
    
    private func saveSettings() {
        Task {
            isSaving = true
            // Implement save via lists-update endpoint
            isSaving = false
            dismiss()
        }
    }
}

struct AddPlaceToListSheet: View {
    let listId: String
    @ObservedObject var viewModel: ListDetailViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Search places - Coming soon")
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Add Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
