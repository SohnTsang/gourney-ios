// Views/Authentication/SignUpView.swift
// Week 7 Day 1: Email verification required - NO profile creation until verified

import SwiftUI
import AuthenticationServices

struct SignUpView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var authManager = AuthManager.shared
    @FocusState private var focusedField: Field?
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    
    // Store handle and display name for after email verification
    @State private var pendingHandle = ""
    @State private var pendingDisplayName = ""
    
    enum Field: Hashable {
        case email, password, confirmPassword
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Show email confirmation message if needed
                    if authManager.emailConfirmationRequired {
                        VStack(spacing: 16) {
                            Image(systemName: "envelope.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                                .padding(.top, 60)
                            
                            Text(authManager.errorMessage?.contains("already in use") == true ? "Email Resent!" : "Check Your Email!")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            
                            Text("We've sent a confirmation link to")
                                .font(.system(size: 15, design: .rounded))
                                .foregroundColor(.secondary)
                            
                            Text(email)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                                .padding(.top, 4)
                            
                            if authManager.errorMessage?.contains("already in use") == true {
                                Text("This email was already registered but not verified. We've sent you a new verification email.")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.orange)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                                    .padding(.top, 12)
                            } else {
                                Text("Click the link in the email to verify your account. Once verified, you'll complete your profile in the app.")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                                    .padding(.top, 12)
                            }
                            
                            Divider()
                                .padding(.horizontal, 40)
                                .padding(.top, 32)
                            
                            Button(action: {
                                authManager.emailConfirmationRequired = false
                                authManager.errorMessage = nil
                            }) {
                                Text("Back to Sign Up")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundColor(Color(red: 0.95, green: 0.3, blue: 0.35))
                            }
                            .padding(.top, 16)
                        }
                        .padding(.horizontal, 40)
                    } else {
                        // Regular signup form
                        VStack(spacing: 0) {
                            // Header
                            Text("Create Account")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .padding(.top, 60)
                            
                            Text("Join Gourney today")
                                .font(.system(size: 15, weight: .regular, design: .rounded))
                                .foregroundColor(.secondary)
                                .padding(.top, 6)
                            
                            // Email Field
                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .focused($focusedField, equals: .email)
                                .font(.system(size: 15, design: .rounded))
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
                                        .onTapGesture { focusedField = .email }
                                )
                                .padding(.horizontal, 40)
                                .padding(.top, 40)
                                .id("email")
                            
                            // Password Field
                            HStack {
                                Group {
                                    if showPassword {
                                        TextField("Password", text: $password)
                                    } else {
                                        SecureField("Password", text: $password)
                                    }
                                }
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .password)
                                .font(.system(size: 15, design: .rounded))
                                
                                Button(action: {
                                    showPassword.toggle()
                                }) {
                                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
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
                                    .onTapGesture { focusedField = .password }
                            )
                            .padding(.horizontal, 40)
                            .padding(.top, 12)
                            .id("password")
                            
                            // Confirm Password Field
                            HStack {
                                Group {
                                    if showConfirmPassword {
                                        TextField("Confirm Password", text: $confirmPassword)
                                    } else {
                                        SecureField("Confirm Password", text: $confirmPassword)
                                    }
                                }
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .confirmPassword)
                                .font(.system(size: 15, design: .rounded))
                                
                                Button(action: {
                                    showConfirmPassword.toggle()
                                }) {
                                    Image(systemName: showConfirmPassword ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 16))
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
                                    .onTapGesture { focusedField = .confirmPassword }
                            )
                            .padding(.horizontal, 40)
                            .padding(.top, 12)
                            .id("confirmPassword")
                            
                            // Password requirements hint
                            if !password.isEmpty && password.count < 8 {
                                Text("Password must be at least 8 characters")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 40)
                                    .padding(.top, 6)
                            }
                            
                            // Password mismatch error
                            if !confirmPassword.isEmpty && password != confirmPassword {
                                Text("Passwords do not match")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 40)
                                    .padding(.top, 6)
                            }
                            
                            // Error message
                            if let error = authManager.errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .font(.system(size: 14))
                                    
                                    Text(error)
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundColor(.red)
                                }
                                .padding(.horizontal, 40)
                                .padding(.top, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            // Sign Up Button
                            Button(action: {
                                focusedField = nil
                                Task {
                                    // Note: We're NOT passing handle/displayName to signup
                                    // Profile will be completed after email verification
                                    await authManager.signUp(
                                        email: email,
                                        password: password,
                                        handle: "", // Will be set after email verification
                                        displayName: "" // Will be set after email verification
                                    )
                                }
                            }) {
                                if authManager.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 48)
                                } else {
                                    Text("Sign Up")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 48)
                                }
                            }
                            .background(
                                isSignUpEnabled ?
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
                            .disabled(!isSignUpEnabled || authManager.isLoading)
                            
                            // Divider
                            HStack(spacing: 16) {
                                Rectangle()
                                    .fill(Color(uiColor: .separator))
                                    .frame(height: 0.5)
                                
                                Text("or")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.secondary)
                                
                                Rectangle()
                                    .fill(Color(uiColor: .separator))
                                    .frame(height: 0.5)
                            }
                            .padding(.horizontal, 40)
                            .padding(.top, 24)
                            
                            // Sign in with Apple Button
                            SignInWithAppleButton(
                                .signUp, // shows “Sign up with Apple”
                                onRequest: { request in
                                    request.requestedScopes = [.email, .fullName]
                                },
                                onCompletion: { result in
                                    Task {
                                        switch result {
                                        case .success(let authorization):
                                            await authManager.signInWithApple(authorization: authorization)
                                        case .failure(let error):
                                            print("❌ Sign in with Apple error: \(error)")
                                            authManager.errorMessage = "Sign in with Apple failed. Please try again."
                                        }
                                    }
                                }
                            )
                            .signInWithAppleButtonStyle(            // ✅ pass a value, not a closure
                                colorScheme == .dark ? .white : .black
                            )
                            .frame(height: 44)
                            .cornerRadius(14)
                            .padding(.horizontal, 40)
                            .padding(.top, 16)
                            .accessibilityLabel("Sign up with Apple")
                            
                            // Sign In Link
                            Button(action: {
                                dismiss()
                            }) {
                                HStack(spacing: 4) {
                                    Text("Already have an account?")
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundColor(.secondary)
                                    
                                    Text("Sign In")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color(red: 0.95, green: 0.3, blue: 0.35))
                                }
                            }
                            .padding(.top, 24)
                            .padding(.bottom, 40)
                        }
                    }
                    
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
    }
    
    private var isSignUpEnabled: Bool {
        !email.isEmpty &&
        authManager.validateEmail(email) &&
        password.count >= 8 &&
        password == confirmPassword
    }
}

#Preview {
    SignUpView()
}
