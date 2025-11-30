// Views/Profile/EditProfileView.swift
// Edit profile screen with avatar, name, handle, bio editing
// Uses shared DetailTopBar component

import SwiftUI
import PhotosUI
import Combine

struct EditProfileView: View {
    @StateObject private var viewModel = EditProfileViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showDiscardAlert = false
    @State private var avatarFrame: CGRect = .zero
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Spacer for top bar
                Color.clear.frame(height: 44)
                
                // Content
                ScrollView {
                    VStack(spacing: 0) {
                        // Avatar Section
                        avatarSection
                        
                        // Form Fields
                        formFields
                            .padding(.top, 16)
                            .padding(.horizontal, 16)
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            
            // Fixed Top Bar
            DetailTopBar(
                title: "Edit Profile",
                rightButtonTitle: "Save",
                rightButtonDisabled: !viewModel.hasChanges,
                rightButtonLoading: viewModel.isSaving,
                showRightButton: true,
                onBack: {
                    if viewModel.hasChanges {
                        showDiscardAlert = true
                    } else {
                        dismiss()
                    }
                },
                onRightAction: {
                    viewModel.saveProfile {
                        dismiss()
                    }
                }
            )
        }
        .navigationBarHidden(true)
        .onAppear {
            viewModel.loadCurrentProfile()
        }
        .alert("Discard Changes?", isPresented: $showDiscardAlert) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") {
                viewModel.error = nil
            }
        } message: {
            Text(viewModel.error ?? "")
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            if let newItem = newItem {
                viewModel.loadPhoto(from: newItem)
            }
        }
    }
    
    // MARK: - Avatar Section (No pencil badge - just camera overlay)
    
    private var avatarSection: some View {
        VStack(spacing: 12) {
            // Avatar with tap to edit, long press to preview
            ZStack {
                // Avatar
                if let image = viewModel.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                } else {
                    AvatarView(url: viewModel.avatarUrl, size: 100)
                }
                
                // Camera overlay circle (shows on tap area)
                Circle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    )
                    .opacity(0.7)
            }
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear {
                        avatarFrame = geo.frame(in: .global)
                    }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        avatarFrame = newFrame
                    }
                }
            )
            .onTapGesture {
                showPhotoPicker = true
            }
            .onLongPressGesture(minimumDuration: 0.3) {
                if viewModel.selectedImage != nil || viewModel.avatarUrl != nil {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    AvatarPreviewState.shared.show(
                        image: viewModel.selectedImage,
                        imageUrl: viewModel.avatarUrl,
                        sourceFrame: avatarFrame
                    )
                }
            }
            
            // Change Photo text
            Button {
                showPhotoPicker = true
            } label: {
                Text("Change Photo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GourneyColors.coral)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
    
    // MARK: - Form Fields
    
    private var formFields: some View {
        VStack(spacing: 24) {
            // Personal Info Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Personal Info")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GourneyColors.coral)
                    .padding(.leading, 4)
                
                VStack(spacing: 0) {
                    EditProfileCardField(
                        title: "Display Name",
                        text: $viewModel.displayName,
                        placeholder: "Enter your name"
                    )
                    
                    Divider()
                        .padding(.leading, 14)
                    
                    EditProfileCardField(
                        title: "Username",
                        text: .constant(viewModel.handle),
                        placeholder: "username",
                        isEditable: false
                    )
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            // Bio Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Bio")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(GourneyColors.coral)
                    
                    Spacer()
                    
                    Text("\(viewModel.bio.count)/150")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(viewModel.bio.count > 130 ? .orange : .secondary)
                }
                .padding(.horizontal, 4)
                
                EditProfileBioCard(
                    text: $viewModel.bio,
                    placeholder: "Tell us about yourself..."
                )
            }
        }
    }
}

// MARK: - Edit Profile Card Field

struct EditProfileCardField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var isEditable: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            HStack {
                TextField(placeholder, text: $text)
                    .font(.system(size: 16))
                    .foregroundColor(isEditable ? .primary : .secondary)
                    .disabled(!isEditable)
                
                if !isEditable {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(.systemGray3))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Edit Profile Bio Card

struct EditProfileBioCard: View {
    @Binding var text: String
    var placeholder: String = ""
    var characterLimit: Int = 150
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty && !isFocused {
                Text(placeholder)
                    .font(.system(size: 16))
                    .foregroundColor(Color(.placeholderText))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
            }
            
            TextEditor(text: $text)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .onChange(of: text) { _, newValue in
                    if newValue.count > characterLimit {
                        text = String(newValue.prefix(characterLimit))
                    }
                }
        }
        .frame(minHeight: 100)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Edit Profile ViewModel

@MainActor
class EditProfileViewModel: ObservableObject {
    @Published var displayName: String = ""
    @Published var handle: String = ""
    @Published var bio: String = ""
    @Published var avatarUrl: String? = nil
    @Published var selectedImage: UIImage? = nil
    
    @Published var isSaving = false
    @Published var error: String? = nil
    
    private var originalDisplayName: String = ""
    private var originalBio: String = ""
    private var originalAvatarUrl: String? = nil
    
    var hasChanges: Bool {
        displayName != originalDisplayName ||
        bio != originalBio ||
        selectedImage != nil
    }
    
    func loadCurrentProfile() {
        guard let user = AuthManager.shared.currentUser else { return }
        
        displayName = user.displayName
        handle = user.handle
        bio = user.bio ?? ""
        avatarUrl = user.avatarUrl
        
        originalDisplayName = displayName
        originalBio = bio
        originalAvatarUrl = avatarUrl
    }
    
    func loadPhoto(from item: PhotosPickerItem) {
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedImage = image
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to load photo"
                }
            }
        }
    }
    
    func saveProfile(onSuccess: @escaping () -> Void) {
        guard hasChanges else { return }
        
        isSaving = true
        
        Task {
            do {
                var newAvatarUrl: String? = nil
                if let image = selectedImage {
                    newAvatarUrl = try await uploadAvatar(image)
                }
                
                let updates: [String: Any] = [
                    "display_name": displayName,
                    "bio": bio,
                    "avatar_url": newAvatarUrl ?? avatarUrl ?? ""
                ]
                
                let _: ProfileUpdateResponse = try await SupabaseClient.shared.post(
                    path: "/functions/v1/user-profile-update",
                    body: updates,
                    requiresAuth: true
                )
                
                await AuthManager.shared.fetchCurrentUser()
                
                await MainActor.run {
                    isSaving = false
                    onSuccess()
                }
                
            } catch {
                await MainActor.run {
                    isSaving = false
                    self.error = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func uploadAvatar(_ image: UIImage) async throws -> String {
        guard let userId = AuthManager.shared.currentUser?.id else {
            throw NSError(domain: "EditProfile", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        return try await AvatarUploadService.shared.uploadAvatar(image, userId: userId)
    }
}

// MARK: - Response Models

struct ProfileUpdateResponse: Codable {
    let success: Bool
    let user: UpdatedUser?
}

struct UpdatedUser: Codable {
    let id: String
    let displayName: String?
    let bio: String?
    let avatarUrl: String?
}

#Preview {
    NavigationStack {
        EditProfileView()
    }
}
