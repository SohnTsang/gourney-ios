import SwiftUI

enum ListFilter {
    case myLists
    case popular
    case following
}

struct ListsView: View {
    @StateObject private var viewModel = ListsViewModel()
    @State private var showCreateList = false
    @State private var selectedList: RestaurantList?
    @State private var selectedFilter: ListFilter = .myLists
    @State private var refreshTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom Header: Title + Plus inline
                    HStack {
                        Text("Lists")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Button(action: { showCreateList = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    
                    // 3-Tab Filter
                    HStack(spacing: 0) {
                        FilterTab(
                            icon: "list.bullet",
                            isSelected: selectedFilter == .myLists,
                            action: { selectedFilter = .myLists }
                        )
                        
                        FilterTab(
                            icon: "flame.fill",
                            isSelected: selectedFilter == .popular,
                            action: { selectedFilter = .popular }
                        )
                        
                        FilterTab(
                            icon: "person.2.fill",
                            isSelected: selectedFilter == .following,
                            action: { selectedFilter = .following }
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    
                    // Content
                    if viewModel.isLoading && viewModel.defaultLists.isEmpty && viewModel.customLists.isEmpty {
                        Spacer()
                        ProgressView()
                            .tint(Color(red: 1.0, green: 0.4, blue: 0.4))
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 2),
                                GridItem(.flexible(), spacing: 2),
                                GridItem(.flexible(), spacing: 2)
                            ], spacing: 2) {
                                if selectedFilter == .myLists {
                                    // Default Lists first
                                    ForEach(viewModel.defaultLists) { list in
                                        ListGridItem(list: list)
                                            .onTapGesture {
                                                selectedList = list
                                            }
                                    }
                                    
                                    // Custom Lists
                                    ForEach(viewModel.customLists) { list in
                                        ListGridItem(list: list)
                                            .onTapGesture {
                                                selectedList = list
                                            }
                                            .contextMenu {
                                                Button(role: .destructive) {
                                                    Task {
                                                        _ = await viewModel.deleteList(listId: list.id)
                                                    }
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                    }
                                }
                            }
                            
                            // Empty state
                            if selectedFilter == .myLists && viewModel.defaultLists.isEmpty && viewModel.customLists.isEmpty {
                                EmptyListsView(showCreateList: $showCreateList)
                                    .padding(.top, 100)
                            }
                            
                            // Placeholder for Popular/Following
                            if selectedFilter != .myLists {
                                VStack(spacing: 16) {
                                    Image(systemName: selectedFilter == .popular ? "flame.fill" : "person.2.fill")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary.opacity(0.5))
                                    Text(selectedFilter == .popular ? "Popular Lists" : "Following's Lists")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text("Coming soon")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 100)
                            }
                        }
                        .refreshable {
                            refreshTask?.cancel()
                            refreshTask = Task {
                                await viewModel.loadLists()
                            }
                            await refreshTask?.value
                        }
                    }
                }
                
                if showCreateList {
                    CreateListSheet(viewModel: viewModel, isPresented: $showCreateList)
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $selectedList) { list in
                ListDetailView(list: list)
            }
            .task {
                await viewModel.loadLists()
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }
}

struct FilterTab: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? Color(red: 1.0, green: 0.4, blue: 0.4) : .secondary)
                
                Rectangle()
                    .fill(isSelected ? Color(red: 1.0, green: 0.4, blue: 0.4) : Color.clear)
                    .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ListGridItem: View {
    let list: RestaurantList
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Cover Image or Placeholder
            if let coverUrl = list.coverPhotoUrl {
                AsyncImage(url: URL(string: coverUrl)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.2)
                }
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3), Color(red: 0.95, green: 0.3, blue: 0.35).opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "photo.stack")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            // Item count badge (top right)
            Text("\(list.itemCount ?? 0)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
                .padding(6)
            
            // Title overlay (bottom)
            VStack {
                Spacer()
                HStack {
                    Text(list.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .padding(8)
                    Spacer()
                }
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(Rectangle())
    }
}

struct EmptyListsView: View {
    @Binding var showCreateList: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 60))
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3))
            
            VStack(spacing: 8) {
                Text("Create Your First List")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Organize your favorite spots")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { showCreateList = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("New List")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(width: 140, height: 44)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ListsView()
}
