// Views/Authentication/ProfileCompletionView.swift
// Week 7 Day 1: Complete profile after Sign in with Apple

import SwiftUI

struct ProfileCompletionView: View {
    @StateObject private var authManager = AuthManager.shared
    @FocusState private var focusedField: Field?
    
    @State private var displayName = ""
    @State private var handle = ""
    @State private var hasManuallyEditedHandle = false
    @State private var isCheckingHandle = false
    @State private var handleAvailable: Bool? = nil
    @State private var handleCheckTask: Task<Void, Never>? = nil
    
    let isAppleSignUp: Bool
    
    enum Field: Hashable {
        case displayName, handle
    }
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Header
                        Text("Complete Your Profile")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .padding(.top, 60)
                        
                        Text("Choose how you want to be known")
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.top, 6)
                        
                        // Display Name Field
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Display Name", text: $displayName)
                                .textContentType(.name)
                                .focused($focusedField, equals: .displayName)
                                .font(.system(size: 15, design: .rounded))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color(uiColor: .tertiarySystemFill))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                                )
                                .cornerRadius(12)
                                .onChange(of: displayName) { oldValue, newValue in
                                    if !hasManuallyEditedHandle {
                                        handle = generateHandle(from: newValue)
                                    }
                                }
                                .id("displayName")
                            
                            if displayName.isEmpty {
                                Text("Display name is required")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 40)

                        // Handle Field
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("@")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                                TextField("username", text: $handle)
                                    .textContentType(.username)
                                    .autocapitalization(.none)
                                    .focused($focusedField, equals: .handle)
                                    .font(.system(size: 15, design: .rounded))
                                    .onChange(of: handle) { oldValue, newValue in
                                        if !newValue.isEmpty && newValue != generateHandle(from: displayName) {
                                            hasManuallyEditedHandle = true
                                        }
                                        
                                        // Debounced handle availability check
                                        handleCheckTask?.cancel()
                                        handleAvailable = nil
                                        
                                        if !newValue.isEmpty && authManager.validateHandle(newValue) == nil {
                                            isCheckingHandle = true
                                            handleCheckTask = Task {
                                                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
                                                guard !Task.isCancelled else { return }
                                                
                                                let available = await authManager.checkHandleAvailable(newValue)
                                                
                                                guard !Task.isCancelled else { return }
                                                await MainActor.run {
                                                    handleAvailable = available
                                                    isCheckingHandle = false
                                                }
                                            }
                                        }
                                    }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                            )
                            .cornerRadius(12)
                            .overlay(
                                Color.clear
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 4)   // ← tweak this number to narrow/widen
                                    .padding(.horizontal, 6) // ← optional, for slight side hit-slop
                                    .onTapGesture { focusedField = .displayName }
                            )
                            .id("handle")
                            
                            // Handle validation feedback
                            if !handle.isEmpty {
                                if let error = authManager.validateHandle(handle) {
                                    // Format error
                                    Text(error)
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundColor(.red)
                                } else if isCheckingHandle {
                                    // Checking availability
                                    HStack(spacing: 5) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                        Text("Checking...")
                                            .font(.system(size: 11, design: .rounded))
                                            .foregroundColor(.secondary)
                                    }
                                } else if let available = handleAvailable {
                                    if available {
                                        // Available
                                        HStack(spacing: 5) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 12))
                                            Text("Available!")
                                                .font(.system(size: 11, design: .rounded))
                                                .foregroundColor(.green)
                                        }
                                    } else {
                                        // Not available
                                        HStack(spacing: 5) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.system(size: 12))
                                            Text("Already taken")
                                                .font(.system(size: 11, design: .rounded))
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 16)
                        
                        // Error message
                        if let error = authManager.errorMessage {
                            Text(error)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(.red)
                                .padding(.horizontal, 40)
                                .padding(.top, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        // Complete Button
                        Button(action: {
                            focusedField = nil
                            Task {
                                if isAppleSignUp {
                                    await authManager.completeAppleSignUp(
                                        handle: handle,
                                        displayName: displayName
                                    )
                                } else {
                                    await authManager.updateProfile(
                                        handle: handle,
                                        displayName: displayName
                                    )
                                }
                            }
                        }) {
                            if authManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                            } else {
                                Text("Complete Profile")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                            }
                        }
                        .background(
                            isCompleteEnabled ?
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(colors: [Color.gray, Color.gray], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(14)
                        .padding(.horizontal, 40)
                        .padding(.top, 32)
                        .disabled(!isCompleteEnabled || authManager.isLoading)
                        
                        Spacer()
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedField) { oldValue, newValue in
                    if let field = newValue {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(field, anchor: .center)
                        }
                    }
                }
            }
            .background(Color(.systemBackground))
            .navigationBarBackButtonHidden(true)
            .interactiveDismissDisabled()
        }
        .onDisappear {
            handleCheckTask?.cancel()
        }
    }
    
    private var isCompleteEnabled: Bool {
        !displayName.isEmpty &&
        !handle.isEmpty &&
        authManager.validateHandle(handle) == nil &&
        handleAvailable == true && // CRITICAL: Must be available
        !isCheckingHandle
    }
    
    private func generateHandle(from displayName: String) -> String {
        let handle = displayName
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        
        let maxLength = 20
        if handle.count > maxLength {
            return String(handle.prefix(maxLength))
        }
        
        return handle
    }
}

#Preview {
    ProfileCompletionView(isAppleSignUp: true)
}

