// Views/Shared/SharedComponents.swift
// Reusable UI components following Gourney design system
// Coral theme: Color(red: 1.0, green: 0.4, blue: 0.4)

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
}

// MARK: - Avatar View (Matches RankView style)

struct AvatarView: View {
    let url: String?
    let size: CGFloat
    var showBorder: Bool = false
    var borderColor: Color = GourneyColors.coral
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(GourneyColors.coralLight)
                .frame(width: size + 4, height: size + 4)
            
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

// MARK: - Previews

#Preview("Avatar") {
    HStack(spacing: 20) {
        AvatarView(url: nil, size: 40)
        AvatarView(url: nil, size: 40, showBorder: true)
        AvatarView(url: "https://example.com/avatar.jpg", size: 40)
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
