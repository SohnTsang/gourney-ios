import SwiftUI

enum ListFilter {
    case myLists
    case popular
    case following
}

struct ListsView: View {
    @StateObject private var viewModel = ListsViewModel()
    @State private var showCreateList = false
    @State private var showFilter = false
    @State private var selectedList: RestaurantList?
    @State private var selectedFilter: ListFilter = .myLists
    @State private var refreshTask: Task<Void, Never>?
    
    // Visibility filters
    @State private var showPrivate = true
    @State private var showFriends = true
    @State private var showPublic = true
    
    @Environment(\.colorScheme) private var colorScheme
    
    var filteredLists: [RestaurantList] {
        guard selectedFilter == .myLists else {
            return []
        }
        
        let allLists = viewModel.defaultLists + viewModel.customLists
        return allLists.filter { list in
            switch list.visibility {
            case "private": return showPrivate
            case "friends": return showFriends
            case "public": return showPublic
            default: return true
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom Header: Title + Filter + Plus
                    HStack {
                        Text("Lists")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        // Filter button (only show for My Lists tab)
                        if selectedFilter == .myLists {
                            Button(action: { showFilter = true }) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 28))
                                    .foregroundColor(.primary)
                            }
                            .padding(.trailing, 12)
                        }
                        
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
                    .padding(.bottom, 0)
                    
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
                                    ForEach(filteredLists) { list in
                                        ListGridItem(list: list, showLikes: list.visibility != "private")
                                            .onTapGesture {
                                                selectedList = list
                                            }
                                            .contextMenu {
                                                // Only allow deletion of custom lists
                                                if !viewModel.defaultLists.contains(where: { $0.id == list.id }) {
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
                                } else if selectedFilter == .following {
                                    ForEach(viewModel.followingLists) { followingList in
                                        FollowingListGridItem(item: followingList)
                                    }
                                }
                            }
                            
                            // Empty state
                            if selectedFilter == .myLists && filteredLists.isEmpty && !viewModel.isLoading {
                                if showPrivate || showFriends || showPublic {
                                    EmptyListsView(showCreateList: $showCreateList)
                                        .padding(.top, 100)
                                } else {
                                    VStack(spacing: 16) {
                                        Image(systemName: "line.3.horizontal.decrease.circle")
                                            .font(.system(size: 48))
                                            .foregroundColor(.secondary.opacity(0.5))
                                        Text("No lists match your filters")
                                            .font(.system(size: 16))
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 100)
                                }
                            }
                            
                            // Placeholder for Popular
                            if selectedFilter == .popular {
                                VStack(spacing: 16) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary.opacity(0.5))
                                    Text("Popular Lists")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text("Coming soon")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 100)
                            }
                            
                            // Empty state for Following
                            if selectedFilter == .following && viewModel.followingLists.isEmpty && !viewModel.isLoading {
                                VStack(spacing: 16) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary.opacity(0.5))
                                    Text("No lists from people you follow")
                                        .font(.system(size: 16))
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
                                if selectedFilter == .following {
                                    await viewModel.loadFollowingLists()
                                }
                            }
                            await refreshTask?.value
                        }
                    }
                }
                
                if showCreateList {
                    CreateListSheet(viewModel: viewModel, isPresented: $showCreateList)
                }
                
                if showFilter {
                    FilterSheet(
                        showPrivate: $showPrivate,
                        showFriends: $showFriends,
                        showPublic: $showPublic,
                        isPresented: $showFilter
                    )
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $selectedList) { list in
                ListDetailView(list: list)
            }
            .task {
                await viewModel.loadLists()
            }
            .onChange(of: selectedFilter) { _, newValue in
                if newValue == .following && viewModel.followingLists.isEmpty {
                    Task {
                        await viewModel.loadFollowingLists()
                    }
                }
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

// MARK: - List Grid Item (Own Lists)

struct ListGridItem: View {
    let list: RestaurantList
    let showLikes: Bool
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .aspectRatio(1, contentMode: .fit)
            
            if let coverUrl = list.coverPhotoUrl {
                AsyncImage(url: URL(string: coverUrl)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
            }
            
            // Gradient overlay - more subtle/greyer
            VStack(alignment: .leading, spacing: 4) {
                Text(list.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    // Restaurant count
                    HStack(spacing: 3) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 11))
                        Text("\(list.itemCount ?? 0)")
                            .font(.system(size: 11))
                    }
                    
                    // Likes (only for public/friends)
                    if showLikes {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 11))
                            Text("\(list.likesCount ?? 0)")
                                .font(.system(size: 11))
                        }
                    }
                }
                .foregroundColor(.white.opacity(0.9))
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipShape(Rectangle())
    }
}

// MARK: - Following List Grid Item

struct FollowingListGridItem: View {
    let item: FollowingListItem
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .aspectRatio(1, contentMode: .fit)
            
            if let coverUrl = item.coverPhotoUrl {
                AsyncImage(url: URL(string: coverUrl)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
            }
            
            // Gradient overlay
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    // Restaurant count
                    HStack(spacing: 3) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 11))
                        Text("\(item.itemCount)")
                            .font(.system(size: 11))
                    }
                    
                    // Likes
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                        Text("\(item.likesCount ?? 0)")
                            .font(.system(size: 11))
                    }
                }
                .foregroundColor(.white.opacity(0.9))
                
                // User info
                Text("@\(item.userHandle)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipShape(Rectangle())
    }
}

// MARK: - Filter Sheet

struct FilterSheet: View {
    @Binding var showPrivate: Bool
    @Binding var showFriends: Bool
    @Binding var showPublic: Bool
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Filter Lists")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                Divider()
                
                // Filter options
                VStack(spacing: 0) {
                    FilterToggleRow(
                        icon: "lock.fill",
                        title: "Private",
                        subtitle: "Only visible to you",
                        isOn: $showPrivate
                    )
                    
                    Divider().padding(.leading, 60)
                    
                    FilterToggleRow(
                        icon: "person.2.fill",
                        title: "Friends",
                        subtitle: "Visible to followers",
                        isOn: $showFriends
                    )
                    
                    Divider().padding(.leading, 60)
                    
                    FilterToggleRow(
                        icon: "globe",
                        title: "Public",
                        subtitle: "Visible to everyone",
                        isOn: $showPublic
                    )
                }
                .padding(.vertical, 8)
                
                Spacer()
            }
            .frame(width: 320, height: 280)
            .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.25), radius: 15, y: 8)
        }
    }
}

struct FilterToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .tint(Color(red: 1.0, green: 0.4, blue: 0.4))
        .toggleStyle(SwitchToggleStyle(tint: Color(red: 1.0, green: 0.4, blue: 0.4)))
        .animation(nil, value: isOn)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Empty State

struct EmptyListsView: View {
    @Binding var showCreateList: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 60))
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3))
            
            VStack(spacing: 8) {
                Text("No Lists Yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Create your first list to organize restaurants")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: { showCreateList = true }) {
                Label("Create List", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 180, height: 50)
                    .background(Color(red: 1.0, green: 0.4, blue: 0.4))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ListsView()
}
