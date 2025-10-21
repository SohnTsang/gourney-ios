// Views/Authentication/SignInView.swift
// Week 7 Day 1: Final polished design with proper navigation

import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @StateObject private var authManager = AuthManager.shared
    @FocusState private var focusedField: Field?
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showSignUp = false
    
    enum Field: Hashable {
        case email, password
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // Centered content
                            VStack(spacing: 0) {
                                // App Icon
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 60))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 1.0, green: 0.5, blue: 0.5)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                    .background(
                                        RoundedRectangle(cornerRadius: 24)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .shadow(color: Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3), radius: 16, y: 8)
                                
                                // App Name
                                Text("Gourney")
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                    .padding(.top, 20)
                                
                                // Tagline
                                Text("Discover, follow & share the Deli")
                                    .font(.system(size: 15, weight: .regular, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 6)
                                
                                SignInWithAppleButton(
                                    .signIn, // keep Sign In wording for the SignInView
                                    onRequest: { request in
                                        print("🔵 [UI] Sign in with Apple button tapped")
                                        print("🔵 [UI] Configuring request...")
                                        request.requestedScopes = [.fullName, .email]
                                        print("🔵 [UI] Request configured with scopes: fullName, email")
                                    },
                                    onCompletion: { result in
                                        print("🔵 [UI] Apple authorization completed")
                                        focusedField = nil
                                        switch result {
                                        case .success(let authorization):
                                            print("✅ [UI] Authorization SUCCESS")
                                            print("🔵 [UI] Credential type: \(type(of: authorization.credential))")
                                            Task {
                                                print("🔵 [UI] Starting async Apple sign in...")
                                                await authManager.signInWithApple(authorization: authorization)
                                                print("🔵 [UI] Apple sign in completed")
                                            }
                                        case .failure(let error):
                                            // Check if user cancelled
                                            let nsError = error as NSError
                                            if nsError.code == 1001 { // ASAuthorizationError.canceled
                                                print("ℹ️ User cancelled Apple Sign In")
                                                // Don't show error message for cancellation
                                                return
                                            }
                                            
                                            print("❌ [UI] Authorization FAILED")
                                            print("❌ [UI] Error: \(error)")
                                            authManager.errorMessage = "Sign in with Apple failed. Please try again."
                                        }
                                    }
                                )
                                .signInWithAppleButtonStyle(           // auto theme: black in light mode, white in dark mode
                                    colorScheme == .dark ? .white : .black
                                )
                                .frame(height: 44)
                                .cornerRadius(14)
                                .padding(.horizontal, 40)
                                .padding(.top, 36)
                                .onAppear {
                                    print("🔵 [UI] Sign in with Apple button appeared on screen")
                                }
                                .accessibilityLabel("Sign in with Apple")

                                
                                // OR Divider
                                HStack(spacing: 14) {
                                    Rectangle()
                                        .frame(height: 0.5)
                                        .foregroundColor(Color(.systemGray4))
                                    
                                    Text("OR")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.secondary)
                                    
                                    Rectangle()
                                        .frame(height: 0.5)
                                        .foregroundColor(Color(.systemGray4))
                                }
                                .padding(.horizontal, 40)
                                .padding(.top, 24)
                                
                                // Email Field
                                VStack(alignment: .leading, spacing: 6) {
                                    TextField("Email", text: $email)
                                        .textContentType(.emailAddress)
                                        .keyboardType(.emailAddress)
                                        .textInputAutocapitalization(.never)  // modern API
                                        .disableAutocorrection(true)
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
                                        .id("email")
                                        .overlay(
                                            Color.clear
                                                .contentShape(Rectangle())
                                                .padding(.vertical, 4)   // ← tweak this number to narrow/widen
                                                .padding(.horizontal, 6) // ← optional, for slight side hit-slop
                                                .onTapGesture { focusedField = .email }
                                        )
                                }
                                .padding(.horizontal, 40)
                                .padding(.top, 20)
                                
                                // Password Field
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        if showPassword {
                                            TextField("Password", text: $password)
                                                .textContentType(.password)
                                                .focused($focusedField, equals: .password)
                                        } else {
                                            SecureField("Password", text: $password)
                                                .textContentType(.password)
                                                .focused($focusedField, equals: .password)
                                        }
                                        
                                        Button(action: { showPassword.toggle() }) {
                                            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                                .foregroundColor(.secondary)
                                                .font(.system(size: 14))
                                        }
                                    }
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
                                            .onTapGesture { focusedField = .password }
                                    )
                                    .id("password")
                                }
                                .padding(.horizontal, 40)
                                .padding(.top, 12)
                                // Error message
                                if let error = authManager.errorMessage {
                                    Text(error)
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 40)
                                        .padding(.top, 10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                
                                // Sign In Button
                                Button(action: {
                                    focusedField = nil
                                    Task {
                                        await authManager.signIn(email: email, password: password)
                                    }
                                }) {
                                    if authManager.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 48)
                                    } else {
                                        Text("Sign In")
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 48)
                                    }
                                }
                                .background(
                                    isSignInEnabled ?
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ) :
                                    LinearGradient(colors: [Color.gray, Color.gray], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(14)
                                .padding(.horizontal, 40)
                                .padding(.top, 20)
                                .disabled(!isSignInEnabled || authManager.isLoading)
                                
                                // Sign Up Link
                                HStack(spacing: 4) {
                                    Text("Don't have an account?")
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundColor(.secondary)
                                    
                                    Button(action: {
                                        focusedField = nil
                                        showSignUp = true
                                    }) {
                                        Text("Sign Up")
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                                    }
                                }
                                .padding(.top, 20)
                            }
                            .frame(minHeight: geometry.size.height)
                            .frame(maxWidth: .infinity)
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
            }
            .background(Color(.systemBackground))
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showSignUp) {
                SignUpView()
            }
        }
    }
    
    private var isSignInEnabled: Bool {
        !email.isEmpty && !password.isEmpty && password.count >= 8
    }
}

#Preview {
    SignInView()
}
