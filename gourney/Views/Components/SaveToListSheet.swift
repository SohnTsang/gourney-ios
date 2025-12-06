// Views/Components/SaveToListSheet.swift
// ✅ Instagram-style "Save to Collection" sheet
// ✅ Optimistic updates with auto-recovery
// ✅ Syncs with ListsViewModel for seamless state updates

import SwiftUI

// MARK: - Save Status Model

struct ListSaveStatus: Identifiable {
    let id: String
    let title: String
    let coverPhotoUrl: String?
    var itemCount: Int
    var isSaved: Bool
    var isLoading: Bool = false
}

// MARK: - Save to List Sheet

struct SaveToListSheet: View {
    let placeId: String
    let placeName: String
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var lists: [ListSaveStatus] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pendingChanges: [String: Bool] = [:] // listId: shouldBeSaved
    
    // ✅ For syncing back to parent views
    @StateObject private var syncViewModel = ListsViewModel()
    
    private let client = SupabaseClient.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(.systemBackground) : Color.white)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    headerView
                    
                    Divider()
                    
                    if isLoading {
                        loadingView
                    } else if let error = errorMessage {
                        errorView(error)
                    } else if lists.isEmpty {
                        emptyView
                    } else {
                        listContent
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await loadListsWithSaveStatus()
        }
        .onDisappear {
            Task {
                await syncViewModel.loadLists()
            }
        }
    }
    
    // MARK: - Show CreateList Overlay (separate UIWindow)
    
    private func showCreateListOverlay() {
        CreateListWindowManager.shared.show(
            viewModel: syncViewModel,
            onListCreated: { newList in
                let newStatus = ListSaveStatus(
                    id: newList.id,
                    title: newList.title,
                    coverPhotoUrl: newList.coverPhotoUrl,
                    itemCount: 0,
                    isSaved: false
                )
                lists.insert(newStatus, at: 0)
                
                NotificationCenter.default.post(
                    name: .listItemsDidChange,
                    object: nil,
                    userInfo: ["action": "listCreated", "list": newList]
                )
            }
        )
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    // ✅ Fix 2: No background on X button
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                Text("Save to List")
                    .font(.system(size: 17, weight: .semibold))
                
                Text(placeName)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Balance the close button
            Color.clear
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16) // ✅ Fix 1: More padding below drag indicator
        .padding(.bottom, 12)
    }
    
    // MARK: - List Content
    
    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // ✅ Create New List button at top
                createNewListButton
                    .padding(.top, 8)
                
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                // List rows
                ForEach($lists) { $listItem in
                    SaveToListRow(
                        listItem: $listItem,
                        onToggle: {
                            toggleSave(for: listItem)
                        }
                    )
                }
            }
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Create New List Button
    
    private var createNewListButton: some View {
        Button {
            showCreateListOverlay()
        } label: {
            HStack(spacing: 12) {
                // Plus icon in circle
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text("Create New List")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Loading/Error/Empty Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .tint(GourneyColors.coral)
            Text("Loading your lists...")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(GourneyColors.coral.opacity(0.6))
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                Task { await loadListsWithSaveStatus() }
            } label: {
                Text("Try Again")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(GourneyColors.coral)
                    .cornerRadius(20)
            }
            
            Spacer()
        }
        .padding(.horizontal, 40)
    }
    
    private var emptyView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "bookmark.circle")
                .font(.system(size: 56))
                .foregroundColor(GourneyColors.coral.opacity(0.4))
            
            Text("No lists yet")
                .font(.system(size: 18, weight: .semibold))
            
            Text("Create your first list to start saving places")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                showCreateListOverlay()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Create List")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(24)
            }
            
            Spacer()
        }
        .padding(.horizontal, 40)
    }
    
    // MARK: - Toggle Save (Optimistic Update)
    
    private func toggleSave(for listItem: ListSaveStatus) {
        guard let index = lists.firstIndex(where: { $0.id == listItem.id }) else { return }
        
        let wasAlreadySaved = lists[index].isSaved
        let newSaveState = !wasAlreadySaved
        
        // ✅ Optimistic update
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            lists[index].isSaved = newSaveState
            lists[index].itemCount += newSaveState ? 1 : -1
            lists[index].isLoading = true
        }
        
        // ✅ Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        // ✅ API call
        Task {
            let success: Bool
            if newSaveState {
                success = await addToList(listId: listItem.id)
            } else {
                success = await removeFromList(listId: listItem.id)
            }
            
            await MainActor.run {
                // Find current index (might have changed)
                guard let currentIndex = lists.firstIndex(where: { $0.id == listItem.id }) else { return }
                
                lists[currentIndex].isLoading = false
                
                if !success {
                    // ✅ Rollback on failure
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        lists[currentIndex].isSaved = wasAlreadySaved
                        lists[currentIndex].itemCount += wasAlreadySaved ? 1 : -1
                    }
                    
                    // Error haptic
                    let errorGenerator = UINotificationFeedbackGenerator()
                    errorGenerator.notificationOccurred(.error)
                }
            }
        }
    }
    
    // MARK: - API Calls
    
    private func loadListsWithSaveStatus() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Fetch user's lists
            let body: [String: Any] = [:]
            let response: ListsGetResponse = try await client.post(
                path: "/functions/v1/lists-get",
                body: body,
                requiresAuth: true
            )
            
            // Fetch which lists contain this place
            let savedInLists: [String] = await fetchSavedInLists()
            
            let savedSet = Set(savedInLists)
            
            await MainActor.run {
                lists = response.lists.map { list in
                    ListSaveStatus(
                        id: list.id,
                        title: list.title,
                        coverPhotoUrl: list.coverPhotoUrl,
                        itemCount: list.itemCount ?? 0,
                        isSaved: savedSet.contains(list.id)
                    )
                }
                isLoading = false
            }
            
            print("✅ [SaveToList] Loaded \(lists.count) lists, \(savedInLists.count) saved")
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load lists"
                isLoading = false
            }
            print("❌ [SaveToList] Load error: \(error)")
        }
    }
    
    private func fetchSavedInLists() async -> [String] {
        do {
            let url = "\(Config.supabaseURL)/functions/v1/lists-check-place"
            guard let requestURL = URL(string: url) else { return [] }
            
            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue(Config.apiVersion, forHTTPHeaderField: "X-API-Version")
            
            if let token = client.getAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            let body: [String: Any] = ["place_id": placeId]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return []
            }
            
            struct SavedInResponse: Codable {
                let listIds: [String]
            }
            
            let decoder = JSONDecoder()
            let result = try decoder.decode(SavedInResponse.self, from: data)
            return result.listIds
            
        } catch {
            print("⚠️ [SaveToList] Check place error: \(error)")
            return []
        }
    }
    
    private func addToList(listId: String) async -> Bool {
        do {
            // ✅ Your API uses query param for list_id, body for place_id
            let url = "\(Config.supabaseURL)/functions/v1/lists-add-item?list_id=\(listId)"
            guard let requestURL = URL(string: url) else { return false }
            
            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue(Config.apiVersion, forHTTPHeaderField: "X-API-Version")
            
            if let token = client.getAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            let body: [String: Any] = ["place_id": placeId]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            
            // ✅ 201 = created, 409 = already exists (both are success for our UI)
            if httpResponse.statusCode == 201 || httpResponse.statusCode == 409 {
                print("✅ [SaveToList] Added to list: \(listId) (status: \(httpResponse.statusCode))")
                
                // Post notification for other views to sync
                NotificationCenter.default.post(
                    name: .listItemsDidChange,
                    object: nil,
                    userInfo: ["listId": listId, "action": "add", "placeId": placeId]
                )
                
                return true
            }
            
            print("❌ [SaveToList] Add failed with status: \(httpResponse.statusCode)")
            return false
            
        } catch {
            print("❌ [SaveToList] Add error: \(error)")
            return false
        }
    }
    
    private func removeFromList(listId: String) async -> Bool {
        do {
            var components = URLComponents(url: URL(string: Config.supabaseURL)!.appendingPathComponent("/functions/v1/lists-remove-item"), resolvingAgainstBaseURL: true)!
            components.queryItems = [
                URLQueryItem(name: "list_id", value: listId),
                URLQueryItem(name: "place_id", value: placeId)
            ]
            
            guard let url = components.url else { return false }
            
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue(Config.apiVersion, forHTTPHeaderField: "X-API-Version")
            
            if let token = client.getAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
                return false
            }
            
            print("✅ [SaveToList] Removed from list: \(listId)")
            
            // ✅ Post notification for other views to sync
            NotificationCenter.default.post(
                name: .listItemsDidChange,
                object: nil,
                userInfo: ["listId": listId, "action": "remove", "placeId": placeId]
            )
            
            return true
        } catch {
            print("❌ [SaveToList] Remove error: \(error)")
            return false
        }
    }
}

// MARK: - Save to List Row

struct SaveToListRow: View {
    @Binding var listItem: ListSaveStatus
    let onToggle: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Cover image
                coverImage
                
                // Title and count
                VStack(alignment: .leading, spacing: 3) {
                    Text(listItem.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(listItem.itemCount) place\(listItem.itemCount == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Checkbox indicator
                checkboxIndicator
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(listItem.isLoading)
    }
    
    private var coverImage: some View {
        Group {
            if let coverUrl = listItem.coverPhotoUrl, !coverUrl.isEmpty {
                AsyncImage(url: URL(string: coverUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        placeholderCover
                    @unknown default:
                        placeholderCover
                    }
                }
            } else {
                placeholderCover
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var placeholderCover: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3),
                    Color(red: 1.0, green: 0.5, blue: 0.5).opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: "bookmark.fill")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    private var checkboxIndicator: some View {
        ZStack {
            if listItem.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(GourneyColors.coral)
            } else if listItem.isSaved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(GourneyColors.coral)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .strokeBorder(Color(.systemGray3), lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 30, height: 30)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: listItem.isSaved)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let listItemsDidChange = Notification.Name("listItemsDidChange")
}

// MARK: - CreateList Window Manager (optimized - reuses window)

final class CreateListWindowManager {
    static let shared = CreateListWindowManager()
    private var overlayWindow: UIWindow?
    private var hostingController: UIHostingController<CreateListWindowContent>?
    
    private init() {}
    
    func show(viewModel: ListsViewModel, onListCreated: @escaping (RestaurantList) -> Void) {
        // Ensure on main thread
        DispatchQueue.main.async { [weak self] in
            self?.showInternal(viewModel: viewModel, onListCreated: onListCreated)
        }
    }
    
    private func showInternal(viewModel: ListsViewModel, onListCreated: @escaping (RestaurantList) -> Void) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        
        // Reuse or create window
        let window: UIWindow
        if let existing = overlayWindow {
            window = existing
        } else {
            window = UIWindow(windowScene: windowScene)
            window.windowLevel = .alert + 1
            window.backgroundColor = .clear
            overlayWindow = window
        }
        
        let content = CreateListWindowContent(
            viewModel: viewModel,
            onListCreated: onListCreated,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        
        let hc = UIHostingController(rootView: content)
        hc.view.backgroundColor = .clear
        hostingController = hc
        
        window.rootViewController = hc
        window.isHidden = false
        window.makeKeyAndVisible()
    }
    
    func dismiss() {
        DispatchQueue.main.async { [weak self] in
            self?.overlayWindow?.isHidden = true
            self?.overlayWindow?.resignKey()
            self?.hostingController = nil
            // Keep window for reuse, just hide it
        }
    }
}

// MARK: - CreateList Window Content

struct CreateListWindowContent: View {
    @ObservedObject var viewModel: ListsViewModel
    var onListCreated: ((RestaurantList) -> Void)?
    var onDismiss: (() -> Void)?
    
    @State private var title = ""
    @State private var isCreating = false
    @State private var showError = false
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    private let maxCharacters = 50
    
    private var isValid: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && title.count <= maxCharacters
    }
    
    private var characterCountColor: Color {
        if title.count > maxCharacters {
            return Color(red: 1.0, green: 0.4, blue: 0.4)
        } else if title.count > maxCharacters - 10 {
            return .orange
        }
        return .secondary
    }
    
    var body: some View {
        ZStack {
            // Dimmed background - tap to dismiss
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isCreating {
                        onDismiss?()
                    }
                }
            
            // Modal card - centered
            VStack(spacing: 0) {
                // Header
                Text("New List")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.top, 28)
                    .padding(.bottom, 20)
                
                // Input section
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        TextField("List name", text: $title)
                            .font(.system(size: 16))
                            .textFieldStyle(.plain)
                            .focused($isFocused)
                            .disabled(isCreating)
                            .submitLabel(.done)
                            .onSubmit {
                                if isValid { createList() }
                            }
                        
                        if !title.isEmpty && !isCreating {
                            Button {
                                title = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray6))
                    )
                    
                    HStack {
                        if showError {
                            Label("Failed to create list", systemImage: "exclamationmark.circle")
                                .font(.system(size: 12))
                                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                        }
                        
                        Spacer()
                        
                        Text("\(title.count)/\(maxCharacters)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(characterCountColor)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                
                // Buttons
                HStack(spacing: 12) {
                    Button {
                        onDismiss?()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .disabled(isCreating)
                    .opacity(isCreating ? 0.6 : 1)
                    
                    Button {
                        createList()
                    } label: {
                        ZStack {
                            if isCreating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Create")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    isValid ?
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ) :
                                    LinearGradient(
                                        colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.5)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                    .disabled(!isValid || isCreating)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(width: min(UIScreen.main.bounds.width - 48, 340))
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
            )
        }
        .onAppear {
            // Focus keyboard immediately
            isFocused = true
        }
    }
    
    private func createList() {
        showError = false
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        isFocused = false
        
        Task {
            isCreating = true
            
            let success = await viewModel.createList(
                title: trimmedTitle,
                description: nil,
                visibility: "private"
            )
            
            await MainActor.run {
                isCreating = false
                
                if success {
                    if let newList = viewModel.customLists.first(where: { $0.title == trimmedTitle }) {
                        onListCreated?(newList)
                    }
                    
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onDismiss?()
                } else {
                    showError = true
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}
