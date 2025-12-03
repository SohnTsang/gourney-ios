// Views/Shared/SharedComponents.swift
// Reusable UI components following Gourney design system
// Coral theme: Color(red: 1.0, green: 0.4, blue: 0.4)
// ✅ FIX: Tapping own avatar switches to Profile tab instead of no response

import SwiftUI


// MARK: - Gourney Colors

struct GourneyColors {
    static let coral = Color(red: 1.0, green: 0.4, blue: 0.4)
    static let coralLight = Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.15)
    static let coralGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.3)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let coralDark = Color(red: 0.95, green: 0.3, blue: 0.3)
}

// MARK: - Avatar View (Matches RankView style)
// ✅ FIX: Tapping own avatar now switches to Profile tab

struct AvatarView: View {
    let url: String?
    let size: CGFloat
    var userId: String? = nil  // Optional: Pass userId to enable tap-to-profile navigation
    var showBorder: Bool = false
    var borderColor: Color = GourneyColors.coral
    
    // Access the shared navigation coordinator
    @ObservedObject private var navigator = NavigationCoordinator.shared
    
    // ✅ Updated: Check if tap should be enabled (now includes current user)
    private var isTappable: Bool {
        guard let userId = userId else { return false }
        return navigator.canNavigateToProfile(userId: userId)
    }
    
    var body: some View {
        ZStack {
            // Border if enabled
            if showBorder {
                Circle()
                    .stroke(borderColor, lineWidth: 2)
                    .frame(width: size + 4, height: size + 4)
            }
            
            // Avatar content
            if let urlString = url, let imageUrl = URL(string: urlString) {
                AsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                            .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    case .failure:
                        placeholderView
                    case .empty:
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: size, height: size)
                            .overlay(
                                ProgressView()
                                    .tint(GourneyColors.coral.opacity(0.5))
                                    .scaleEffect(0.5)
                            )
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .contentShape(Circle())
        .onTapGesture {
            if let userId = userId, isTappable {
                // ✅ This now handles both current user (tab switch) and other users (push)
                navigator.showProfile(userId: userId)
            }
        }
        .allowsHitTesting(isTappable)
    }
    
    private var placeholderView: some View {
        Circle()
            .fill(GourneyColors.coralLight)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundColor(GourneyColors.coral)
            )
    }
}

// MARK: - Context Menu Button (Square touch area)

struct ContextMenuButton: View {
    let action: () -> Void
    var icon: String = "ellipsis"
    var size: CGFloat = 44
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dropdown Menu Overlay (Matches RankView LocationDropdown)

struct DropdownMenuOverlay<Content: View>: View {
    @Binding var isPresented: Bool
    let alignment: Alignment
    let content: Content
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        isPresented: Binding<Bool>,
        alignment: Alignment = .topTrailing,
        @ViewBuilder content: () -> Content
    ) {
        self._isPresented = isPresented
        self.alignment = alignment
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isPresented = false
                    }
                }
            
            // Menu content
            VStack(spacing: 0) {
                content
            }
            .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .transition(.scale(scale: 0.9, anchor: alignment == .topTrailing ? .topTrailing : .topLeading).combined(with: .opacity))
        }
    }
}

// MARK: - Menu Option (Matches RankView LocationOption style)

struct MenuOption: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var isDestructive: Bool = false
    var isSelected: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isDestructive ? .red : .primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(GourneyColors.coral)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var iconColor: Color {
        if isDestructive { return .red }
        if isSelected { return GourneyColors.coral }
        return .secondary
    }
}

// MARK: - Rating Stars View

struct RatingStarsView: View {
    let rating: Int
    var size: CGFloat = 14
    var spacing: CGFloat = 2
    var filledColor: Color = .yellow
    var emptyColor: Color = Color(.systemGray4)
    
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<5) { index in
                Image(systemName: index < rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundColor(index < rating ? filledColor : emptyColor)
            }
        }
    }
}

// MARK: - Action Button (Like, Comment, Save, Share)

struct FeedActionButton: View {
    let icon: String
    var filledIcon: String? = nil
    var label: String? = nil
    var count: Int? = nil
    var isActive: Bool = false
    var activeColor: Color = GourneyColors.coral
    let action: () -> Void
    
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        Button {
            if filledIcon != nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    scale = 1.2
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        scale = 1.0
                    }
                }
            }
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isActive ? (filledIcon ?? icon) : icon)
                    .font(.system(size: 20))
                    .foregroundColor(isActive ? activeColor : .primary)
                    .scaleEffect(scale)
                
                if let count = count, count > 0 {
                    Text(formatCount(count))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                if let label = label {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1000000)
        } else if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000)
        }
        return "\(count)"
    }
}

// MARK: - Tappable User View (For username labels that navigate to profile)
// ✅ Updated: Now also handles current user (switches to Profile tab)

struct TappableUsername: View {
    let username: String
    let userId: String
    var font: Font = .system(size: 14, weight: .semibold)
    var color: Color = .primary
    
    @ObservedObject private var navigator = NavigationCoordinator.shared
    
    private var isTappable: Bool {
        navigator.canNavigateToProfile(userId: userId)
    }
    
    var body: some View {
        Text(username)
            .font(font)
            .foregroundColor(color)
            .contentShape(Rectangle())
            .onTapGesture {
                if isTappable {
                    // ✅ This now handles both current user (tab switch) and other users (push)
                    navigator.showProfile(userId: userId)
                }
            }
            .allowsHitTesting(isTappable)
    }
}

// MARK: - Time Ago Helper

func timeAgoString(from dateString: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    
    guard let date = formatter.date(from: dateString) else {
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: dateString) else {
            return ""
        }
        return formatTimeAgo(date)
    }
    return formatTimeAgo(date)
}

private func formatTimeAgo(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    
    if interval < 60 { return "now" }
    if interval < 3600 { return "\(Int(interval / 60))m" }
    if interval < 86400 { return "\(Int(interval / 3600))h" }
    if interval < 604800 { return "\(Int(interval / 86400))d" }
    return "\(Int(interval / 604800))w"
}

// MARK: - ═══════════════════════════════════════════════════════════════════
// MARK: - SEARCH COMPONENTS (Instagram-style)
// MARK: - ═══════════════════════════════════════════════════════════════════

// MARK: - Search Tab Configuration

struct SearchTab: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String?
    
    init(id: String, title: String, icon: String? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
    }
    
    // Common presets
    static let users = SearchTab(id: "users", title: "Users", icon: "person")
    static let places = SearchTab(id: "places", title: "Places", icon: "mappin")
    static let posts = SearchTab(id: "posts", title: "Posts", icon: "square.grid.2x2")
    static let tags = SearchTab(id: "tags", title: "Tags", icon: "number")
    static let top = SearchTab(id: "top", title: "Top", icon: nil)
}

// MARK: - Search Bar Button (Tappable placeholder - triggers full search)

struct SearchBarButton: View {
    let placeholder: String
    var icon: String = "magnifyingglass"
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                
                Text(placeholder)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Text Field (Inline search - for lists, filters)
// Matches SearchBarButton styling exactly

struct SearchTextField: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var icon: String = "magnifyingglass"
    var showClearButton: Bool = true
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            
            ZStack(alignment: .leading) {
                // Custom placeholder to match SearchBarButton color exactly
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                
                TextField("", text: $text)
                    .font(.system(size: 15))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            
            Spacer()
            
            if showClearButton && !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Search Overlay View (Full-screen Instagram-style search)

struct SearchOverlayView<Content: View>: View {
    @Binding var isPresented: Bool
    @Binding var searchText: String
    let placeholder: String
    let tabs: [SearchTab]?
    @Binding var selectedTabId: String?
    @ViewBuilder let content: () -> Content
    
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFocused: Bool
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    init(
        isPresented: Binding<Bool>,
        searchText: Binding<String>,
        placeholder: String = "Search",
        tabs: [SearchTab]? = nil,
        selectedTabId: Binding<String?> = .constant(nil),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isPresented = isPresented
        self._searchText = searchText
        self.placeholder = placeholder
        self.tabs = tabs
        self._selectedTabId = selectedTabId
        self.content = content
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Header
            searchHeader
            
            // Tab Picker (if multiple tabs provided)
            if let tabs = tabs, tabs.count > 1 {
                tabPicker(tabs)
            }
            
            // Divider
            Divider()
            
            // Content (results, recent searches, etc.)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(backgroundColor.ignoresSafeArea())
        .onAppear {
            // Auto-focus search field with slight delay for animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
    }
    
    // MARK: - Search Header
    
    private var searchHeader: some View {
        HStack(spacing: 12) {
            // Search Field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                
                TextField(placeholder, text: $searchText)
                    .font(.system(size: 15))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            // Cancel Button
            Button {
                isSearchFocused = false
                searchText = ""
                withAnimation(.easeOut(duration: 0.25)) {
                    isPresented = false
                }
            } label: {
                Text("Cancel")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(backgroundColor)
    }
    
    // MARK: - Tab Picker (Instagram-style underline)
    
    private func tabPicker(_ tabs: [SearchTab]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    tabButton(tab, isSelected: selectedTabId == tab.id)
                }
            }
            .padding(.horizontal, 8)
        }
        .background(backgroundColor)
    }
    
    private func tabButton(_ tab: SearchTab, isSelected: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTabId = tab.id
            }
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    if let icon = tab.icon {
                        Image(systemName: icon)
                            .font(.system(size: 13))
                    }
                    Text(tab.title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                }
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(Color.primary)
                        .frame(height: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Generic Search Row (Reusable row for search results)
// Note: Named GenericSearchRow to avoid conflict with SearchPlaceOverlay's SearchResultRow

struct GenericSearchRow: View {
    let imageUrl: String?
    let title: String
    var subtitle: String? = nil
    var trailingText: String? = nil
    var imageSize: CGFloat = 44
    var showChevron: Bool = false
    var isPlaceholder: Bool = false  // For user avatar placeholder
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Image/Avatar
                if isPlaceholder {
                    AvatarView(url: imageUrl, size: imageSize)
                } else if let url = imageUrl {
                    AsyncImage(url: URL(string: url)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: imageSize, height: imageSize)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        case .failure, .empty:
                            placeholderImage
                        @unknown default:
                            placeholderImage
                        }
                    }
                } else {
                    placeholderImage
                }
                
                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Trailing
                if let trailing = trailingText {
                    Text(trailing)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(.systemGray3))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.systemGray5))
            .frame(width: imageSize, height: imageSize)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: imageSize * 0.4))
                    .foregroundColor(.secondary)
            )
    }
}

// MARK: - Recent Search Item

struct RecentSearchItem: View {
    let icon: String
    let text: String
    let onTap: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            // Text
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Search Empty State

struct SearchEmptyState: View {
    var icon: String = "magnifyingglass"
    var title: String = "No Results"
    var message: String = "Try searching for something else"
    
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
}

// MARK: - Search Section Header

struct SearchSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            
            Spacer()
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(GourneyColors.coral)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Previews

#Preview("Avatar") {
    HStack(spacing: 20) {
        AvatarView(url: nil, size: 40)
        AvatarView(url: nil, size: 40, showBorder: true)
        AvatarView(url: "https://example.com/avatar.jpg", size: 40)
        AvatarView(url: nil, size: 40, userId: "test-user-id") // Tappable
    }
    .padding()
}

#Preview("Menu Options") {
    VStack(spacing: 0) {
        MenuOption(icon: "person", title: "View Profile", action: {})
        Divider().padding(.leading, 52)
        MenuOption(icon: "bookmark", title: "Save to List", action: {})
        Divider().padding(.leading, 52)
        MenuOption(icon: "flag", title: "Report", isDestructive: true, action: {})
    }
    .frame(width: 220)
    .background(Color(.systemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .shadow(radius: 10)
    .padding()
}

#Preview("Rating Stars") {
    VStack(spacing: 12) {
        RatingStarsView(rating: 5)
        RatingStarsView(rating: 3)
        RatingStarsView(rating: 0)
    }
}

#Preview("Action Buttons") {
    HStack(spacing: 8) {
        FeedActionButton(icon: "heart", filledIcon: "heart.fill", count: 24, isActive: false, action: {})
        FeedActionButton(icon: "heart", filledIcon: "heart.fill", count: 24, isActive: true, action: {})
        FeedActionButton(icon: "bubble.right", count: 5, action: {})
        FeedActionButton(icon: "bookmark", filledIcon: "bookmark.fill", action: {})
    }
}

#Preview("Tappable Username") {
    TappableUsername(username: "foodie_lover", userId: "user-123")
        .padding()
}

#Preview("Search Bar Button") {
    VStack(spacing: 16) {
        SearchBarButton(placeholder: "Search places, users") { }
        SearchBarButton(placeholder: "Search", icon: "magnifyingglass") { }
    }
    .padding()
}

#Preview("Search Text Field") {
    struct PreviewWrapper: View {
        @State private var text = ""
        var body: some View {
            VStack(spacing: 16) {
                SearchTextField(text: $text, placeholder: "Search users...")
                SearchTextField(text: .constant("ramen"), placeholder: "Search")
            }
            .padding()
        }
    }
    return PreviewWrapper()
}

#Preview("Generic Search Row") {
    VStack(spacing: 0) {
        GenericSearchRow(
            imageUrl: nil,
            title: "foodie_lover",
            subtitle: "John Smith • 45 visits",
            isPlaceholder: true
        ) { }
        Divider().padding(.leading, 72)
        GenericSearchRow(
            imageUrl: nil,
            title: "AFURI Harajuku",
            subtitle: "Ramen • Shibuya, Tokyo",
            trailingText: "4.5★",
            showChevron: true
        ) { }
    }
}

#Preview("Recent Searches") {
    VStack(spacing: 0) {
        SearchSectionHeader(title: "Recent", actionTitle: "Clear All") { }
        RecentSearchItem(icon: "clock", text: "Ramen in Shibuya", onTap: { }, onRemove: { })
        RecentSearchItem(icon: "person", text: "@foodie_lover", onTap: { }, onRemove: { })
        RecentSearchItem(icon: "mappin", text: "AFURI Harajuku", onTap: { }, onRemove: { })
    }
}

#Preview("Search Empty State") {
    SearchEmptyState(
        icon: "magnifyingglass",
        title: "No Results",
        message: "Try searching for something else"
    )
}
