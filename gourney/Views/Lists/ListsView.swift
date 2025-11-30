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
    @Environment(\.dismiss) private var dismiss
    
    // ✅ Dynamic title based on selected tab
    private var navigationTitle: String {
        switch selectedFilter {
        case .myLists: return "My Lists"
        case .popular: return "Popular Lists"
        case .following: return "Following's Lists"
        }
    }
    
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
            // ✅ Changed to 2 columns with more spacing
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
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
                                if followingList.id == viewModel.followingLists.last?.id {
                                    Task {
                                        await viewModel.loadFollowingLists(loadMore: true)
                                    }
                                }
                            }
                    }
                } else if selectedFilter == .popular {
                    ForEach(viewModel.popularLists) { popularList in
                        PopularListGridItem(
                            item: popularList,
                            onTap: {
                                selectedList = RestaurantList(
                                    id: popularList.id,
                                    title: popularList.title,
                                    description: popularList.description,
                                    visibility: popularList.visibility,
                                    itemCount: popularList.itemCount,
                                    coverPhotoUrl: nil,
                                    createdAt: popularList.createdAt,
                                    likesCount: popularList.likesCount,
                                    viewCount: popularList.viewCount
                                )
                            }
                        )
                        .onAppear {
                            if popularList.id == viewModel.popularLists.last?.id &&
                               !viewModel.isLoadingMore &&
                               viewModel.popularLists.count >= 20 {
                                Task {
                                    await viewModel.loadPopularLists(loadMore: true)
                                }
                            }
                        }
                    }
                }
                
                // Loading indicator at bottom (only during pagination)
                if viewModel.isLoadingMore &&
                   ((selectedFilter == .myLists && !viewModel.customLists.isEmpty) ||
                    (selectedFilter == .following && !viewModel.followingLists.isEmpty) ||
                    (selectedFilter == .popular && !viewModel.popularLists.isEmpty)) {
                    GridRow {
                        ProgressView()
                            .tint(GourneyColors.coral)
                            .gridCellColumns(2)  // ✅ Changed from 3 to 2
                            .padding(.vertical, 20)
                    }
                }
            }
            .padding(.horizontal, 12)  // ✅ Add horizontal padding for grid
            
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
            
            // Empty state for Following
            if selectedFilter == .following && viewModel.followingLists.isEmpty && !viewModel.isLoading && !viewModel.isLoadingMore {
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
            
            // Empty state for Popular
            if selectedFilter == .popular && viewModel.popularLists.isEmpty && !viewModel.isLoading && !viewModel.isLoadingMore {
                VStack(spacing: 16) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Popular Lists Yet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Lists with 3+ likes and 3+ places will appear here")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable {
            refreshTask?.cancel()
            refreshTask = Task {
                await viewModel.loadLists()
                if selectedFilter == .following {
                    await viewModel.loadFollowingLists()
                } else if selectedFilter == .popular {
                    await viewModel.loadPopularLists()
                }
            }
            await refreshTask?.value
        }
    }
    
    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // ✅ Updated top bar with dynamic title
                ListsTopBar(
                    title: navigationTitle,
                    showFilter: selectedFilter == .myLists,
                    onBack: { dismiss() },
                    onFilter: { showFilter = true },
                    onCreate: { showCreateList = true }
                )
                
                // ✅ More padding between top bar and tab bar
                Spacer().frame(height: 12)
                
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
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
                
                // Content
                if viewModel.isLoading && !viewModel.isLoadingMore &&
                   ((selectedFilter == .myLists && viewModel.defaultLists.isEmpty && viewModel.customLists.isEmpty) ||
                    (selectedFilter == .following && viewModel.followingLists.isEmpty) ||
                    (selectedFilter == .popular && viewModel.popularLists.isEmpty)) {
                    Spacer()
                    ProgressView()
                        .tint(GourneyColors.coral)
                    Spacer()
                } else {
                    mainContent
                        .id(selectedFilter)
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
                        
                        // Only show delete for custom lists
                        let wantToTryTitle = NSLocalizedString("lists.default.want_to_try", comment: "")
                        let favoritesTitle = NSLocalizedString("lists.default.favorites", comment: "")
                        let isDefaultList = list.title == wantToTryTitle || list.title == favoritesTitle
                        
                        if !isDefaultList {
                            items.append(
                                ContextMenuItem(
                                    icon: "trash",
                                    title: "Delete",
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
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: Binding(
            get: { selectedList != nil },
            set: { if !$0 { selectedList = nil } }
        )) {
            if let list = selectedList {
                ListDetailView(
                    list: list,
                    isReadOnly: false,
                    onListUpdated: { listId, newCount in
                        if let index = viewModel.defaultLists.firstIndex(where: { $0.id == listId }) {
                            viewModel.defaultLists[index].itemCount = newCount
                        } else if let index = viewModel.customLists.firstIndex(where: { $0.id == listId }) {
                            viewModel.customLists[index].itemCount = newCount
                        }
                    }
                )
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedFollowingList != nil },
            set: { if !$0 { selectedFollowingList = nil } }
        )) {
            if let followingList = selectedFollowingList {
                ListDetailView(
                    list: RestaurantList(
                        id: followingList.id,
                        title: followingList.title,
                        description: nil,
                        visibility: followingList.visibility,
                        itemCount: followingList.itemCount,
                        coverPhotoUrl: followingList.coverPhotoUrl,
                        createdAt: followingList.createdAt,
                        likesCount: followingList.likesCount,
                        viewCount: nil
                    ),
                    isReadOnly: true,
                    ownerHandle: followingList.userHandle
                )
            }
        }
        .customDeleteAlert(
            isPresented: $showDeleteAlert,
            title: "Delete List",
            message: "Are you sure you want to delete this list? This cannot be undone.",
            confirmTitle: "Delete",
            onConfirm: {
                if let list = listToDelete {
                    Task {
                        _ = await viewModel.deleteList(listId: list.id)
                        listToDelete = nil
                    }
                }
            }
        )
        .onAppear {
            Task {
                await viewModel.loadLists()
            }
        }
        .onChange(of: selectedFilter) { _, newFilter in
            Task {
                switch newFilter {
                case .myLists:
                    if viewModel.defaultLists.isEmpty && viewModel.customLists.isEmpty {
                        await viewModel.loadLists()
                    }
                case .following:
                    if viewModel.followingLists.isEmpty {
                        await viewModel.loadFollowingLists()
                    }
                case .popular:
                    if viewModel.popularLists.isEmpty {
                        await viewModel.loadPopularLists()
                    }
                }
            }
        }
    }
}

// MARK: - Lists Top Bar (Custom for Lists with filter + plus icons)

struct ListsTopBar: View {
    let title: String  // ✅ Now accepts dynamic title
    let showFilter: Bool
    let onBack: () -> Void
    let onFilter: () -> Void
    let onCreate: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    var body: some View {
        ZStack {
            // Center: Title (always perfectly centered)
            Text(title)  // ✅ Use dynamic title
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
            
            // Left and Right buttons
            HStack {
                // Left: Back button
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                
                Spacer()
                
                // Right: Filter + Plus icons
                HStack(spacing: 0) {
                    if showFilter {
                        Button(action: onFilter) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 22))
                                .foregroundColor(.primary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    }
                    
                    Button(action: onCreate) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(GourneyColors.coral)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(backgroundColor)
    }
}

// MARK: - Filter Tab

struct FilterTab: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? GourneyColors.coral : .secondary)
                    .frame(height: 24) // Fixed height for consistent alignment
                
                Spacer()
                    .frame(height: 8)
                
                Rectangle()
                    .fill(isSelected ? GourneyColors.coral : Color.clear)
                    .frame(height: 2)
            }
            .frame(height: 34) // Fixed total height
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Long Press List Item

struct LongPressListItem: View {
    let list: RestaurantList
    let showLikes: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ListGridItem(list: list, showLikes: showLikes)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .onTapGesture {
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }, perform: {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                onLongPress()
            })
    }
}

// MARK: - List Grid Item

struct ListGridItem: View {
    let list: RestaurantList
    let showLikes: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background/Placeholder
                if list.coverPhotoUrl == nil {
                    // Elegant placeholder design
                    ZStack {
                        LinearGradient(
                            colors: [
                                GourneyColors.coral.opacity(0.2),
                                GourneyColors.coral.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        VStack(spacing: 8) {
                            Image(systemName: "list.bullet.rectangle.portrait")
                                .font(.system(size: 32))
                                .foregroundColor(GourneyColors.coral.opacity(0.5))
                        }
                    }
                } else {
                    AsyncImage(url: URL(string: list.coverPhotoUrl!)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                        case .failure(_):
                            placeholderWithError
                        case .empty:
                            placeholderWithLoading
                        @unknown default:
                            placeholderWithLoading
                        }
                    }
                }
                
                // Title overlay (bottom) with place count and like count
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    
                    Text(list.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    // ✅ Bottom row: place count (left) and like count (right)
                    HStack {
                        // Place count with icon
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 10))
                            Text("\(list.itemCount ?? 0)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.9))
                        
                        Spacer()
                        
                        // ✅ Like count (bottom right) - no background
                        if showLikes {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 10))
                                Text("\(list.likesCount ?? 0)")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.9))
                        }
                    }
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
        }
        .aspectRatio(4/5, contentMode: .fit)  // ✅ Slightly taller aspect ratio for 2-column
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12))  // ✅ Add rounded corners for 2-column grid
    }
    
    private var placeholderWithLoading: some View {
        ZStack {
            Color.gray.opacity(0.15)
            ProgressView()
                .tint(GourneyColors.coral.opacity(0.6))
                .scaleEffect(0.8)
        }
    }
    
    private var placeholderWithError: some View {
        ZStack {
            LinearGradient(
                colors: [
                    GourneyColors.coral.opacity(0.2),
                    GourneyColors.coral.opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 32))
                .foregroundColor(GourneyColors.coral.opacity(0.5))
        }
    }
}

// MARK: - Following List Grid Item

struct FollowingListGridItem: View {
    let item: FollowingListItem
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Cover image or placeholder
            Group {
                if let coverUrl = item.coverPhotoUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure, .empty:
                            placeholderView
                        @unknown default:
                            placeholderView
                        }
                    }
                } else {
                    placeholderView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            
            // Title + Owner overlay
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                // ✅ Bottom row: handle (left) and like count (right)
                HStack {
                    Text("@\(item.userHandle)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Spacer()
                    
                    // ✅ Like count (bottom right) - no background
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                        Text("\(item.likesCount ?? 0)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.9))
                }
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
        .aspectRatio(4/5, contentMode: .fit)  // ✅ Match aspect ratio
        .clipShape(RoundedRectangle(cornerRadius: 12))  // ✅ Add rounded corners
    }
    
    private var placeholderView: some View {
        ZStack {
            // ✅ Consistent coral gradient placeholder like other tabs
            LinearGradient(
                colors: [
                    GourneyColors.coral.opacity(0.2),
                    GourneyColors.coral.opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: "person.2.fill")
                .font(.system(size: 32))
                .foregroundColor(GourneyColors.coral.opacity(0.5))
        }
    }
}

// MARK: - Popular List Grid Item

struct PopularListGridItem: View {
    let item: PopularList
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Placeholder design (no cover photos in lists table)
                ZStack {
                    LinearGradient(
                        colors: [
                            GourneyColors.coral.opacity(0.2),
                            GourneyColors.coral.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    VStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 32))
                            .foregroundColor(GourneyColors.coral.opacity(0.5))
                    }
                }
                
                // Title overlay (bottom) with item count and like count
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    // ✅ Bottom row: place count (left) and like count (right)
                    HStack {
                        // Place count with icon
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 10))
                            Text("\(item.itemCount)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.9))
                        
                        Spacer()
                        
                        // ✅ Like count (bottom right) - no background
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                            Text("\(item.likesCount)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.9))
                    }
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
            .aspectRatio(4/5, contentMode: .fit)  // ✅ Match aspect ratio
            .clipShape(RoundedRectangle(cornerRadius: 12))  // ✅ Add rounded corners
        }
        .buttonStyle(PlainButtonStyle())
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
        .tint(GourneyColors.coral)
        .toggleStyle(SwitchToggleStyle(tint: GourneyColors.coral))
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
                .foregroundColor(GourneyColors.coral.opacity(0.3))
            
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
                    .background(GourneyColors.coral)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        ListsView()
    }
}
