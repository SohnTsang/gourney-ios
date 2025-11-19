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
    @State private var listToEdit: RestaurantList?
    @State private var showSettings = false
    @State private var showDeleteAlert = false
    @State private var listToDelete: RestaurantList?
    @State private var showContextMenu = false
    @State private var contextMenuList: RestaurantList?
    @State private var selectedFollowingList: FollowingListItem?
    
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
    
    @ViewBuilder
    private var mainContent: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2)
            ], spacing: 2) {
                if selectedFilter == .myLists {
                    ForEach(filteredLists) { list in
                        LongPressListItem(
                            list: list,
                            showLikes: list.visibility != "private",
                            onTap: {
                                selectedList = list
                            },
                            onLongPress: {
                                contextMenuList = list
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showContextMenu = true
                                }
                            }
                        )
                            .onAppear {
                                if list.id == filteredLists.last?.id {
                                    Task {
                                        await viewModel.loadLists(loadMore: true)
                                    }
                                }
                            }
                    }
                } else if selectedFilter == .following {
                    ForEach(viewModel.followingLists) { followingList in
                        FollowingListGridItem(item: followingList)
                            .onTapGesture {
                                selectedFollowingList = followingList
                            }
                            .onAppear {
                                // Load more when reaching last item
                                if followingList.id == viewModel.followingLists.last?.id {
                                    Task {
                                        await viewModel.loadFollowingLists(loadMore: true)
                                    }
                                }
                            }
                    }
                }
                
                // Loading indicator at bottom
                if viewModel.isLoadingMore {
                    GridRow {
                        ProgressView()
                            .tint(Color(red: 1.0, green: 0.4, blue: 0.4))
                            .gridCellColumns(3)
                            .padding(.vertical, 20)
                    }
                }
            }
            
            // Empty states
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
                    if viewModel.isLoading &&
                       ((selectedFilter == .myLists && viewModel.defaultLists.isEmpty && viewModel.customLists.isEmpty) ||
                        (selectedFilter == .following && viewModel.followingLists.isEmpty)) {
                        Spacer()
                        ProgressView()
                            .tint(Color(red: 1.0, green: 0.4, blue: 0.4))
                        Spacer()
                    } else {
                        mainContent
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
                
                if showSettings, let list = listToEdit {
                    ListSettingsSheet(
                        list: list,
                        isPresented: $showSettings,
                        onSave: { updatedList in
                            if let index = viewModel.defaultLists.firstIndex(where: { $0.id == updatedList.id }) {
                                viewModel.defaultLists[index] = updatedList
                            } else if let index = viewModel.customLists.firstIndex(where: { $0.id == updatedList.id }) {
                                viewModel.customLists[index] = updatedList
                            }
                            listToEdit = nil
                        }
                    )
                }
                
                if showContextMenu, let list = contextMenuList {
                    ListPreviewMenu(
                        list: list,
                        items: {
                            var items = [
                                ContextMenuItem(
                                    icon: "gear",
                                    title: "Settings",
                                    isDestructive: false,
                                    action: {
                                        listToEdit = list
                                        showSettings = true
                                    }
                                )
                            ]
                            if !viewModel.defaultLists.contains(where: { $0.id == list.id }) {
                                items.append(
                                    ContextMenuItem(
                                        icon: "trash",
                                        title: "Delete List",
                                        isDestructive: true,
                                        action: {
                                            listToDelete = list
                                            showDeleteAlert = true
                                        }
                                    )
                                )
                            }
                            return items
                        }(),
                        isPresented: $showContextMenu
                    )
                    .transition(.opacity)
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(item: $selectedList) { list in
                ListDetailView(list: list) {
                    Task {
                        await viewModel.loadLists()
                    }
                }
            }
            .fullScreenCover(item: $selectedFollowingList) { followingItem in
                ListDetailView(
                    list: RestaurantList(
                        id: followingItem.id,
                        title: followingItem.title,
                        description: nil,  // Following lists don't include description
                        visibility: followingItem.visibility,
                        itemCount: followingItem.itemCount,
                        coverPhotoUrl: followingItem.coverPhotoUrl,
                        createdAt: followingItem.createdAt,
                        likesCount: followingItem.likesCount
                    ),
                    isReadOnly: true,
                    ownerHandle: followingItem.userHandle,
                    onListUpdated: {
                        // Refresh following lists when like status changes
                        Task {
                            await viewModel.loadFollowingLists()
                        }
                    }
                )
            }
            .alert("Delete List", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    listToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let list = listToDelete {
                        Task {
                            _ = await viewModel.deleteList(listId: list.id)
                            listToDelete = nil
                        }
                    }
                }
            } message: {
                if let list = listToDelete {
                    Text("Are you sure you want to delete \"\(list.title)\"? This action cannot be undone.")
                }
            }
            .task {
                await viewModel.loadLists()
            }
            .onAppear {
                // Reload if data was cleared
                if viewModel.defaultLists.isEmpty && viewModel.customLists.isEmpty {
                    Task {
                        await viewModel.loadLists()
                    }
                }
                if selectedFilter == .following && viewModel.followingLists.isEmpty {
                    Task {
                        await viewModel.loadFollowingLists()
                    }
                }
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
            VStack(spacing: 8) {
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

struct LongPressListItem: View {
    let list: RestaurantList
    let showLikes: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        ListGridItem(list: list, showLikes: showLikes)
            .scaleEffect(isPressed ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .onTapGesture {
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.4, pressing: { pressing in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = pressing
                }
            }) {
                onLongPress()
            }
    }
}

struct ListGridItem: View {
    let list: RestaurantList
    let showLikes: Bool
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background/Placeholder
            if list.coverPhotoUrl == nil {
                // Elegant placeholder design
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.2),
                            Color(red: 1.0, green: 0.5, blue: 0.5).opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .font(.system(size: 32))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.5))
                    }
                }
            } else {
                AsyncImage(url: URL(string: list.coverPhotoUrl!)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
            }
            
            // Like count (top right)
            if showLikes {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("\(list.likesCount ?? 0)")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    Color.black.opacity(0.75)
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                .padding(6)
            }
            
            // Title overlay (bottom)
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                
                Text(list.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)  // ✅ 2 lines
                    .multilineTextAlignment(.leading)
                
                // Restaurant count
                HStack(spacing: 3) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 11))
                    Text("\(list.itemCount ?? 0)")
                        .font(.system(size: 11))
                }
                .foregroundColor(.white.opacity(0.9))
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
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(Rectangle())
    }
}

// MARK: - Following List Grid Item

struct FollowingListGridItem: View {
    let item: FollowingListItem
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background/Placeholder
            if item.coverPhotoUrl == nil {
                // Elegant placeholder design
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.2),
                            Color(red: 1.0, green: 0.5, blue: 0.5).opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .font(.system(size: 32))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.5))
                    }
                }
            } else {
                AsyncImage(url: URL(string: item.coverPhotoUrl!)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
            }
            
            // Like count (top right)
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("\(item.likesCount ?? 0)")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Color.black.opacity(0.75)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .padding(6)
            
            // Title overlay (bottom)
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)  // ✅ 2 lines
                    .multilineTextAlignment(.leading)
                
                // Restaurant count
                HStack(spacing: 3) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 11))
                    Text("\(item.itemCount)")
                        .font(.system(size: 11))
                }
                .foregroundColor(.white.opacity(0.9))
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
        }
        .aspectRatio(1, contentMode: .fill)
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
