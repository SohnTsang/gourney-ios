// Views/Lists/ListSharedComponents.swift
// Shared components for Lists feature

import SwiftUI
import PhotosUI

// MARK: - Custom Context Menu

struct CustomContextMenu: View {
    let items: [ContextMenuItem]
    @Binding var isPresented: Bool
    let alignment: Alignment // .topTrailing for button menus, .center for long press
    let offset: CGSize // Offset from alignment point
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack(alignment: alignment) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isPresented = false
                    }
                }
            
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            item.action()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(item.isDestructive ? .red : Color(red: 1.0, green: 0.4, blue: 0.4))
                                .frame(width: 24)
                            
                            Text(item.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(item.isDestructive ? .red : .primary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .frame(width: 240)
            .offset(offset)
            .transition(.scale(scale: 0.9, anchor: alignment == .topTrailing ? .topTrailing : .center).combined(with: .opacity))
        }
    }
}

struct ContextMenuItem {
    let icon: String
    let title: String
    let isDestructive: Bool
    let action: () -> Void
}

// MARK: - Instagram-style Long Press Preview

struct ListPreviewMenu: View {
    let list: RestaurantList
    let items: [ContextMenuItem]
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }
            
            VStack(spacing: 12) {
                // Enlarged preview with native bubble effect
                ZStack {
                    if let coverUrl = list.coverPhotoUrl, !coverUrl.isEmpty {
                        AsyncImage(url: URL(string: coverUrl)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .empty, .failure:
                                placeholderView
                            @unknown default:
                                placeholderView
                            }
                        }
                    } else {
                        placeholderView
                    }
                }
                .frame(width: 280, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                .scaleEffect(isPresented ? 1.0 : 0.85)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isPresented)
                
                // Context menu below
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                item.action()
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(item.isDestructive ? .red : Color(red: 1.0, green: 0.4, blue: 0.4))
                                    .frame(width: 24)
                                
                                Text(item.title)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(item.isDestructive ? .red : .primary)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        if index < items.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .frame(width: 280)
                .scaleEffect(isPresented ? 1.0 : 0.9)
                .opacity(isPresented ? 1.0 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.75).delay(0.05), value: isPresented)
            }
        }
    }
    
    private var placeholderView: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3),
                    Color(red: 1.0, green: 0.5, blue: 0.5).opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Icon in center
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.white.opacity(0.8))
                
                Text(list.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - List Settings Sheet

struct ListSettingsSheet: View {
    let list: RestaurantList
    @Binding var isPresented: Bool
    let onSave: (RestaurantList) -> Void
    
    @State private var title: String
    @State private var description: String
    @State private var selectedVisibility: String
    @State private var isSaving = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDefaultList: Bool {
        let wantToTryTitle = NSLocalizedString("lists.default.want_to_try", comment: "")
        let favoritesTitle = NSLocalizedString("lists.default.favorites", comment: "")
        return list.title == wantToTryTitle || list.title == favoritesTitle
    }
    
    init(list: RestaurantList, isPresented: Binding<Bool>, onSave: @escaping (RestaurantList) -> Void) {
        self.list = list
        self._isPresented = isPresented
        self.onSave = onSave
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
                    .foregroundColor((title.isEmpty && !isDefaultList) ? .secondary : Color(red: 1.0, green: 0.4, blue: 0.4))
                    .disabled(isSaving || (title.isEmpty && !isDefaultList))
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
                                    icon: "globe.americas.fill",
                                    title: "Public",
                                    subtitle: "Anyone can view",
                                    isSelected: selectedVisibility == "public",
                                    action: { selectedVisibility = "public" }
                                )
                                
                                Divider()
                                    .padding(.leading, 66)
                                
                                VisibilityOption(
                                    icon: "person.2.fill",
                                    title: "Friends",
                                    subtitle: "Only followers can view",
                                    isSelected: selectedVisibility == "friends",
                                    action: { selectedVisibility = "friends" }
                                )
                                
                                Divider()
                                    .padding(.leading, 66)
                                
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
            .disabled(isSaving)  // ← ADD THIS LINE
            
            if isSaving {
                LoadingOverlay(message: "Saving changes...")
            }
        }
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text("Posting your visit...")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
        }
    }
    
    private func saveSettings() {
        Task {
            isSaving = true
            
            do {
                let body: [String: Any] = [
                    "title": title,
                    "description": description.isEmpty ? "" : description,
                    "visibility": selectedVisibility
                ]
                
                let queryItems = [URLQueryItem(name: "list_id", value: list.id)]
                
                let _: EmptyResponse = try await SupabaseClient.shared.patch(
                    path: "/functions/v1/lists-update",
                    body: body,
                    queryItems: queryItems,
                    requiresAuth: true
                )
                
                let updatedList = RestaurantList(
                    id: list.id,
                    title: title,
                    description: description.isEmpty ? nil : description,
                    visibility: selectedVisibility,
                    itemCount: list.itemCount,
                    coverPhotoUrl: list.coverPhotoUrl,
                    createdAt: list.createdAt,
                    likesCount: list.likesCount
                )
                
                print("✅ [Settings] List updated: \(title)")
                
                await MainActor.run {
                    onSave(updatedList)
                    isSaving = false
                    isPresented = false
                }
            } catch {
                print("❌ [Settings] Update error: \(error)")
                await MainActor.run {
                    isSaving = false
                }
            }
        }
    }
}

struct VisibilityOption: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(isSelected ? Color(red: 1.0, green: 0.4, blue: 0.4) : Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isSelected ? .white : .secondary)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
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
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
