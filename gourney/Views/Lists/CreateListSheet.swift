// Views/Components/CreateListSheet.swift
// ✅ Gourney-styled list creation modal
// ✅ Coral gradient accent, clean typography
// ✅ Callback for seamless UI updates without full refresh

import SwiftUI

struct CreateListSheet: View {
    @ObservedObject var viewModel: ListsViewModel
    @Binding var isPresented: Bool
    var onListCreated: ((RestaurantList) -> Void)? = nil
    
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
            // Dimmed background - no animation
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isCreating {
                        dismissSheet()
                    }
                }
            
            // Modal card - no shadow, no animation, just appear
            VStack(spacing: 0) {
                // Header - just title
                headerSection
                
                // Input section
                inputSection
                
                // Action buttons
                buttonSection
            }
            .frame(width: min(UIScreen.main.bounds.width - 48, 340))
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
            )
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }
    
    // MARK: - Header Section (simplified - no icon, no subtitle)
    
    private var headerSection: some View {
        Text("New List")
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.primary)
            .padding(.top, 28)
            .padding(.bottom, 20)
            .padding(.horizontal, 24)
    }
    
    // MARK: - Input Section (search bar style)
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Text field - search bar style
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
            
            // Character count
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
    }
    
    // MARK: - Button Section
    
    private var buttonSection: some View {
        HStack(spacing: 12) {
            // Cancel button - just text, no background
            Button {
                dismissSheet()
            } label: {
                Text("Cancel")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .disabled(isCreating)
            .opacity(isCreating ? 0.6 : 1)
            
            // Create button
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
                .shadow(color: isValid ? Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3) : .clear, radius: 8, y: 4)
            }
            .disabled(!isValid || isCreating)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
    
    // MARK: - Actions
    
    private func dismissSheet() {
        isFocused = false
        isPresented = false
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
                    // ✅ Callback with the newly created list
                    if let newList = viewModel.customLists.first(where: { $0.title == trimmedTitle }) {
                        onListCreated?(newList)
                    }
                    
                    // Haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    
                    dismissSheet()
                } else {
                    showError = true
                    
                    // Error haptic
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()
        
        CreateListSheet(
            viewModel: ListsViewModel(),
            isPresented: .constant(true)
        )
    }
}
