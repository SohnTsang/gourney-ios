//
//  AuthManager.swift
//  gourney
//
//  Week 7 Day 1: Complete authentication manager - FIXED
//  Fixed: Email verification flow requires profile completion
//

import Foundation
import Combine
import AuthenticationServices

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    let client = SupabaseClient.shared
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var needsProfileCompletion = false
    @Published var emailConfirmationRequired = false
    
    private init() {
        Task {
            await checkAuthStatus()
        }
    }
    
    // MARK: - Auth Status Check
    
    func checkAuthStatus() async {
        if client.getAuthToken() != nil {
            await fetchCurrentUser()
        }
    }
    
    // MARK: - Public Token Management (for deep links)
    
    /// Set auth token from external source (e.g., email verification deep link)
    func setAuthTokenFromDeepLink(_ token: String) {
        client.setAuthToken(token)
        print("✅ [Auth] Token set from deep link")
    }
    
    // MARK: - Sign In
    
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let body: [String: Any] = [
                "email": email,
                "password": password
            ]
            
            let response: AuthResponse = try await client.post(
                path: "/auth/v1/token",
                body: body,
                queryItems: [URLQueryItem(name: "grant_type", value: "password")],
                requiresAuth: false
            )
            
            client.setAuthToken(response.accessToken)
            await fetchCurrentUser()
            
            // Check if profile is complete
            if let user = currentUser, isProfileIncomplete(user) {
                print("📝 [Sign In] Profile incomplete, showing profile completion")
                needsProfileCompletion = true
                isAuthenticated = false
            } else {
                isAuthenticated = true
            }
            
            isLoading = false
            
        } catch let error as APIError {
            isLoading = false
            handleAuthError(error)
            print("❌ Sign in error: \(error)")
        } catch {
            isLoading = false
            errorMessage = NSLocalizedString("error.unknown", comment: "")
            print("❌ Sign in error: \(error)")
        }
    }
    
    // MARK: - Sign Up
    
    func signUp(
        email: String,
        password: String,
        handle: String,
        displayName: String
    ) async {
        isLoading = true
        errorMessage = nil
        emailConfirmationRequired = false
        
        do {
            print("📝 [Signup] Starting signup for email: \(email)")
            
            // Strategy: Try to sign in first to check if email exists
            // This is more reliable than checking the users table
            let authStatus = await checkAuthEmailStatus(email: email, password: password)
            
            switch authStatus {
            case .verified:
                print("❌ [Signup] Email already verified - user should sign in")
                errorMessage = "This email is already registered. Please sign in instead."
                isLoading = false
                return
                
            case .unverified:
                print("⚠️ [Signup] Email exists but not verified - resending")
                await resendVerificationEmail(email: email)
                emailConfirmationRequired = true
                errorMessage = "This email is already in use but not verified. We've sent you a new verification email."
                isLoading = false
                return
                
            case .notFound:
                print("✅ [Signup] Email is new, proceeding with signup")
                // Continue with signup
            }
            
            // Attempt signup
            let signupBody: [String: Any] = [
                "email": email,
                "password": password
            ]
            
            let (data, response) = try await performSignupRequest(body: signupBody)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            print("📝 [Signup] Status: \(httpResponse.statusCode)")
            
            // Parse the response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("📝 [Signup] Response keys: \(json.keys)")
                
                // Check for error in response
                if let error = json["error"] as? String {
                    print("❌ [Signup] Error from Supabase: \(error)")
                    if let errorDescription = json["error_description"] as? String {
                        print("❌ [Signup] Description: \(errorDescription)")
                        errorMessage = errorDescription
                    } else {
                        errorMessage = error
                    }
                    isLoading = false
                    return
                }
                
                // Success - email confirmation required
                print("📧 [Signup] Signup successful, email confirmation sent")
                emailConfirmationRequired = true
            }
            
            isLoading = false
            
        } catch let error as APIError {
            isLoading = false
            handleAuthError(error)
            print("❌ Sign up error: \(error)")
        } catch {
            isLoading = false
            errorMessage = NSLocalizedString("error.unknown", comment: "")
            print("❌ Sign up error: \(error)")
        }
    }
    
    // MARK: - Auth Email Status
    
    enum AuthEmailStatus {
        case verified      // Email exists and verified (has profile)
        case unverified    // Email exists but not verified (no profile)
        case notFound      // Email doesn't exist
    }
    
    private func checkAuthEmailStatus(email: String, password: String) async -> AuthEmailStatus {
        do {
            print("📧 [Auth Status] Checking email status for: \(email)")
            
            // Try to sign in with the provided password
            let body: [String: Any] = [
                "email": email,
                "password": password
            ]
            
            let response: AuthResponse = try await client.post(
                path: "/auth/v1/token",
                body: body,
                queryItems: [URLQueryItem(name: "grant_type", value: "password")],
                requiresAuth: false
            )
            
            // Sign in succeeded - check if profile exists
            print("✅ [Auth Status] Sign in succeeded, checking profile")
            let profileExists = await checkUserProfileExistsById(userId: response.user.id)
            
            if profileExists {
                print("✅ [Auth Status] Profile exists - VERIFIED")
                return .verified
            } else {
                print("⚠️ [Auth Status] No profile - UNVERIFIED")
                return .unverified
            }
            
        } catch let error as APIError {
            if case .badRequest(let message) = error {
                print("📧 [Auth Status] Error: \(message)")
                
                // "Email not confirmed" = exists but NOT verified
                if message.contains("Email not confirmed") ||
                   message.contains("email_not_confirmed") {
                    print("⚠️ [Auth Status] Email NOT confirmed - UNVERIFIED")
                    return .unverified
                }
                
                // "Invalid login credentials" with the ACTUAL password they entered
                // This is tricky - could mean:
                // 1. Email doesn't exist, OR
                // 2. Email exists but wrong password
                // We need to try a different approach
                if message.contains("Invalid login credentials") ||
                   message.contains("invalid_credentials") {
                    print("📧 [Auth Status] Invalid credentials, trying dummy password")
                    // Try again with a definitely wrong password
                    return await checkAuthEmailStatusWithDummyPassword(email: email)
                }
            }
            
            print("📧 [Auth Status] Unknown error - NOT FOUND")
            return .notFound
        } catch {
            print("📧 [Auth Status] Unknown error - NOT FOUND")
            return .notFound
        }
    }
    
    private func checkAuthEmailStatusWithDummyPassword(email: String) async -> AuthEmailStatus {
        do {
            let body: [String: Any] = [
                "email": email,
                "password": UUID().uuidString // Definitely wrong password
            ]
            
            let _: AuthResponse = try await client.post(
                path: "/auth/v1/token",
                body: body,
                queryItems: [URLQueryItem(name: "grant_type", value: "password")],
                requiresAuth: false
            )
            
            // Should never succeed with random password
            print("⚠️ [Auth Status Dummy] Unexpected success")
            return .verified
            
        } catch let error as APIError {
            if case .badRequest(let message) = error {
                print("📧 [Auth Status Dummy] Error: \(message)")
                
                if message.contains("Email not confirmed") {
                    print("⚠️ [Auth Status Dummy] UNVERIFIED")
                    return .unverified
                }
                
                if message.contains("Invalid login credentials") {
                    // With wrong password: "Invalid credentials" means email EXISTS and is verified
                    print("✅ [Auth Status Dummy] VERIFIED (wrong password but email exists)")
                    return .verified
                }
            }
            
            print("📧 [Auth Status Dummy] NOT FOUND")
            return .notFound
        } catch {
            print("📧 [Auth Status Dummy] NOT FOUND")
            return .notFound
        }
    }
    
    // MARK: - Check if User Profile Exists (by ID)
    
    private func checkUserProfileExistsById(userId: String) async -> Bool {
        do {
            print("📧 [Profile Check] Checking if profile exists for ID: \(userId)")
            
            struct IdCheck: Codable {
                let id: String
            }
            
            let users: [IdCheck] = try await client.get(
                path: "/rest/v1/users",
                queryItems: [
                    URLQueryItem(name: "id", value: "eq.\(userId)"),
                    URLQueryItem(name: "select", value: "id")
                ],
                requiresAuth: false
            )
            
            let exists = !users.isEmpty
            print("📧 [Profile Check] Profile exists: \(exists)")
            return exists
            
        } catch {
            print("⚠️ [Profile Check] Error: \(error)")
            return false
        }
    }
    
    // MARK: - Check if Email is Verified (Simple Version)
    
    private func checkEmailVerifiedSimple(email: String) async -> Bool {
        // We can't check by email since users table doesn't have email column
        // This method is not used anymore, but keeping it for compatibility
        return false
    }
    
    // MARK: - Check if Email is Verified (with password)
    
    private func checkEmailVerified(email: String, password: String) async -> Bool {
        do {
            print("📧 [Verify Check] Attempting sign in to check verification")
            
            let body: [String: Any] = [
                "email": email,
                "password": password
            ]
            
            let _: AuthResponse = try await client.post(
                path: "/auth/v1/token",
                body: body,
                queryItems: [URLQueryItem(name: "grant_type", value: "password")],
                requiresAuth: false
            )
            
            print("✅ [Verify Check] Sign in succeeded - email is verified")
            return true
            
        } catch let error as APIError {
            if case .badRequest(let message) = error {
                print("📧 [Verify Check] Error: \(message)")
                
                if message.contains("Email not confirmed") ||
                   message.contains("email_not_confirmed") {
                    print("📧 [Verify Check] Email NOT verified")
                    return false
                }
                
                // "Invalid login credentials" could mean verified but wrong password
                // In this case, check if profile exists
                if message.contains("Invalid login credentials") {
                    print("📧 [Verify Check] Invalid credentials - checking profile")
                    return await checkEmailVerifiedSimple(email: email)
                }
            }
            
            print("⚠️ [Verify Check] Unknown error: \(error)")
            return false
        } catch {
            print("⚠️ [Verify Check] Unknown error: \(error)")
            return false
        }
    }
    
    // MARK: - Resend Verification Email
    
    private func resendVerificationEmail(email: String) async {
        do {
            print("📧 [Resend] Attempting to resend verification email to: \(email)")
            
            guard let url = URL(string: "\(Config.supabaseURL)/auth/v1/resend") else {
                throw APIError.invalidResponse
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            
            let body: [String: Any] = [
                "type": "signup",
                "email": email
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📧 [Resend] Response status: \(httpResponse.statusCode)")
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("📧 [Resend] Response: \(json)")
                }
                
                if httpResponse.statusCode == 200 {
                    print("✅ [Resend] Verification email resent successfully")
                } else {
                    print("⚠️ [Resend] Unexpected status code: \(httpResponse.statusCode)")
                }
            }
            
        } catch {
            print("⚠️ [Resend] Could not resend verification email: \(error)")
        }
    }

    // MARK: - Helper: Perform Signup Request

    private func performSignupRequest(body: [String: Any]) async throws -> (Data, URLResponse) {
        guard let url = URL(string: "\(Config.supabaseURL)/auth/v1/signup") else {
            throw APIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue(Config.apiVersion, forHTTPHeaderField: "X-API-Version")
        
        let locale = Locale.current.language.languageCode?.identifier ?? "en"
        let languageMap = ["ja": "ja", "zh": "zh-Hant"]
        let apiLanguage = languageMap[locale] ?? "en"
        request.setValue(apiLanguage, forHTTPHeaderField: "Accept-Language")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        return try await URLSession.shared.data(for: request)
    }
    
    // MARK: - Sign in with Apple
    
    func signInWithApple(authorization: ASAuthorization) async {
        print("🎯 [Apple Auth] Starting Sign in with Apple flow")
        isLoading = true
        errorMessage = nil
        needsProfileCompletion = false
        
        print("🎯 [Apple Auth] Checking credential type...")
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            print("❌ [Apple Auth] Failed to cast credential to ASAuthorizationAppleIDCredential")
            errorMessage = NSLocalizedString("auth.error.apple_failed", comment: "Sign in with Apple failed. Please try again.")
            isLoading = false
            return
        }
        
        print("✅ [Apple Auth] Got ASAuthorizationAppleIDCredential")
        print("🎯 [Apple Auth] User ID: \(appleIDCredential.user)")
        print("🎯 [Apple Auth] Email: \(appleIDCredential.email ?? "not provided")")
        
        print("🎯 [Apple Auth] Extracting identity token...")
        guard let identityToken = appleIDCredential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            print("❌ [Apple Auth] Failed to extract identity token")
            errorMessage = NSLocalizedString("auth.error.apple_token_failed", comment: "Could not complete authentication. Please try again.")
            isLoading = false
            return
        }
        
        print("✅ [Apple Auth] Got identity token (length: \(tokenString.count))")
        
        do {
            print("🎯 [Apple Auth] Preparing request to Supabase...")
            let body: [String: Any] = [
                "provider": "apple",
                "id_token": tokenString
            ]
            
            print("🎯 [Apple Auth] Calling Supabase auth endpoint...")
            let response: AuthResponse = try await client.post(
                path: "/auth/v1/token",
                body: body,
                queryItems: [URLQueryItem(name: "grant_type", value: "id_token")],
                requiresAuth: false
            )
            
            print("✅ [Apple Auth] Supabase response received")
            print("🎯 [Apple Auth] User ID from Supabase: \(response.user.id)")
            
            client.setAuthToken(response.accessToken)
            print("✅ [Apple Auth] Token saved")
            
            // CRITICAL: Always fetch the current user from database
            print("🎯 [Apple Auth] Fetching user profile from database...")
            await fetchCurrentUser()
            
            if let user = currentUser {
                print("✅ [Apple Auth] Found user profile: @\(user.handle)")
                print("🎯 [Apple Auth] Display name: '\(user.displayName)'")
                
                // Check if profile is complete
                if isProfileIncomplete(user) {
                    print("📝 [Apple Auth] Profile incomplete - showing profile completion")
                    needsProfileCompletion = true
                    isAuthenticated = false
                } else {
                    print("✅ [Apple Auth] Profile complete - user authenticated")
                    isAuthenticated = true
                    needsProfileCompletion = false
                }
            } else {
                // No user profile found - show profile completion
                print("📝 [Apple Auth] No user profile found - showing profile completion")
                needsProfileCompletion = true
                isAuthenticated = false
            }
            
            isLoading = false
            
        } catch let error as APIError {
            print("❌ [Apple Auth] API Error: \(error)")
            isLoading = false
            needsProfileCompletion = false
            handleAuthError(error)
        } catch {
            print("❌ [Apple Auth] Unexpected error: \(error)")
            isLoading = false
            needsProfileCompletion = false
            errorMessage = NSLocalizedString("auth.error.apple_failed", comment: "Sign in with Apple failed. Please try again.")
        }
    }
    
    // MARK: - Check if Profile is Incomplete
    
    func isProfileIncomplete(_ user: User) -> Bool {
        // Profile is incomplete if:
        // 1. Display name is empty
        // 2. Handle is system-generated (starts with test_ or user_)
        
        let hasEmptyDisplayName = user.displayName.isEmpty
        
        let hasSystemGeneratedHandle = user.handle.hasPrefix("test_") ||
                                       user.handle.hasPrefix("user_")
        
        let isIncomplete = hasEmptyDisplayName || hasSystemGeneratedHandle
        
        print("📝 [Profile Check] User: @\(user.handle)")
        print("📝 [Profile Check] Display Name: '\(user.displayName)'")
        print("📝 [Profile Check] Display Name Empty: \(hasEmptyDisplayName)")
        print("📝 [Profile Check] Has System Handle: \(hasSystemGeneratedHandle)")
        print("📝 [Profile Check] Is Incomplete: \(isIncomplete)")
        
        return isIncomplete
    }
    
    // MARK: - Complete Apple Sign Up Profile
    
    func completeAppleSignUp(handle: String, displayName: String) async {
        print("📝 [Profile Complete] Starting profile completion")
        print("📝 [Profile Complete] Handle: @\(handle)")
        print("📝 [Profile Complete] Display Name: '\(displayName)'")
        
        isLoading = true
        errorMessage = nil
        
        guard let token = client.getAuthToken() else {
            errorMessage = NSLocalizedString("auth.error.no_token", comment: "")
            isLoading = false
            needsProfileCompletion = true
            print("❌ [Profile Complete] No auth token found")
            return
        }
        
        guard let userId = extractUserIdFromToken(token) else {
            errorMessage = NSLocalizedString("auth.error.invalid_token", comment: "")
            isLoading = false
            needsProfileCompletion = true
            print("❌ [Profile Complete] Could not extract user ID from token")
            return
        }
        
        print("📝 [Profile Complete] User ID: \(userId)")
        
        do {
            let profileBody: [String: Any] = [
                "id": userId,
                "handle": handle,
                "display_name": displayName,
                "locale": Locale.current.identifier
            ]
            
            print("📝 [Profile Complete] Upserting profile to database...")
            print("📝 [Profile Complete] Body: \(profileBody)")
            
            // Try to upsert
            do {
                let users: [User] = try await client.upsert(
                    path: "/rest/v1/users",
                    body: profileBody
                )
                
                if let user = users.first {
                    print("✅ [Profile Complete] Got user from upsert response")
                    print("✅ [Profile Complete] User: \(user)")
                    currentUser = user
                    isAuthenticated = true
                    needsProfileCompletion = false
                    isLoading = false
                    return
                }
                
                print("⚠️ [Profile Complete] Upsert returned empty array")
            } catch APIError.decodingFailed {
                print("⚠️ [Profile Complete] Upsert returned empty, fetching user instead")
            }
            
            // Fallback: Wait and fetch the user we just created
            print("📝 [Profile Complete] Waiting 1 second for database to settle...")
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            print("📝 [Profile Complete] Fetching newly created user from database")
            await fetchCurrentUser()
            
            if let user = currentUser {
                print("✅ [Profile Complete] Successfully fetched created user")
                print("✅ [Profile Complete] User: \(user)")
                isAuthenticated = true
                needsProfileCompletion = false
            } else {
                print("❌ [Profile Complete] Could not fetch created user")
                errorMessage = NSLocalizedString("auth.error.profile_save_failed", comment: "")
                needsProfileCompletion = true
            }
            
            isLoading = false
            
        } catch let error as APIError {
            print("❌ [Profile Complete] API Error: \(error)")
            isLoading = false
            needsProfileCompletion = true
            handleAuthError(error)
        } catch {
            print("❌ [Profile Complete] Unknown error: \(error)")
            isLoading = false
            needsProfileCompletion = true
            errorMessage = NSLocalizedString("auth.error.profile_save_failed", comment: "")
        }
    }
    
    // MARK: - Update Profile
    
    func updateProfile(handle: String, displayName: String) async {
        isLoading = true
        errorMessage = nil
        
        guard let token = client.getAuthToken() else {
            errorMessage = NSLocalizedString("auth.error.no_token", comment: "Authentication token not found.")
            isLoading = false
            return
        }
        
        guard let userId = extractUserIdFromToken(token) else {
            errorMessage = NSLocalizedString("auth.error.invalid_token", comment: "Invalid authentication.")
            isLoading = false
            return
        }
        
        do {
            let profileBody: [String: Any] = [
                "handle": handle,
                "display_name": displayName
            ]
            
            print("📝 [Profile Update] Updating user profile for user ID: \(userId)")
            
            let _: User = try await client.put(
                path: "/rest/v1/users",
                body: profileBody,
                queryItems: [URLQueryItem(name: "id", value: "eq.\(userId)")]
            )
            
            print("✅ [Profile Update] User profile updated successfully")
            await fetchCurrentUser()
            isLoading = false
            print("✅ [Profile Update] Profile update completed")
            
        } catch let error as APIError {
            isLoading = false
            handleAuthError(error)
            print("❌ [Profile Update] Profile update error: \(error)")
        } catch {
            isLoading = false
            errorMessage = NSLocalizedString("error.unknown", comment: "")
            print("❌ [Profile Update] Profile update error: \(error)")
        }
    }
    
    // MARK: - Extract User ID from JWT
    
    private func extractUserIdFromToken(_ token: String) -> String? {
        let segments = token.components(separatedBy: ".")
        guard segments.count > 1 else { return nil }
        
        var base64 = segments[1]
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 = base64.padding(toLength: base64.count + 4 - remainder, withPad: "=", startingAt: 0)
        }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else {
            return nil
        }
        
        return sub
    }
    
    // MARK: - Check User Profile Exists (by user ID)
    
    private func checkUserProfileExists(userId: String) async -> Bool {
        do {
            print("📝 [Profile Check] Checking if user profile exists for ID: \(userId)")
            
            struct UserIdCheck: Codable {
                let id: String
            }
            
            let response: [UserIdCheck] = try await client.get(
                path: "/rest/v1/users",
                queryItems: [
                    URLQueryItem(name: "id", value: "eq.\(userId)"),
                    URLQueryItem(name: "select", value: "id")
                ]
            )
            
            let exists = !response.isEmpty
            print("📝 [Profile Check] Profile exists: \(exists)")
            return exists
            
        } catch {
            print("❌ [Profile Check] Error checking user profile: \(error)")
            return false
        }
    }
    
    // MARK: - Fetch Current User
    
    private func fetchCurrentUser() async {
        do {
            print("👤 [Fetch User] Fetching current user profile...")
            
            // Get the user ID from the token
            guard let token = client.getAuthToken() else {
                print("❌ [Fetch User] No auth token found")
                currentUser = nil
                return
            }
            
            guard let userId = extractUserIdFromToken(token) else {
                print("❌ [Fetch User] Could not extract user ID from token")
                currentUser = nil
                return
            }
            
            print("👤 [Fetch User] User ID from token: \(userId)")
            print("👤 [Fetch User] Token length: \(token.count)")
            
            // Query with explicit user ID filter
            let users: [User] = try await client.get(
                path: "/rest/v1/users",
                queryItems: [
                    URLQueryItem(name: "id", value: "eq.\(userId)"),
                    URLQueryItem(name: "select", value: "*")
                ],
                requiresAuth: true // CRITICAL: Must be true for RLS
            )
            
            print("👤 [Fetch User] Query returned \(users.count) user(s)")
            
            if let user = users.first {
                currentUser = user
                print("✅ [Fetch User] Fetched user successfully")
                print("👤 [Fetch User] ID: \(user.id)")
                print("👤 [Fetch User] Handle: @\(user.handle)")
                print("👤 [Fetch User] Display Name: '\(user.displayName)'")
                print("👤 [Fetch User] Email: \(user.email ?? "none")")
                print("👤 [Fetch User] Home City: \(user.homeCity ?? "none")")
                print("👤 [Fetch User] Created At: \(user.createdAt ?? "none")")
            } else {
                print("❌ [Fetch User] No user found in database with ID: \(userId)")
                print("❌ [Fetch User] This means either:")
                print("   1. User profile was never created in database")
                print("   2. RLS policy is blocking the SELECT")
                print("   3. User ID from token doesn't match database")
                currentUser = nil
            }
        } catch {
            print("❌ [Fetch User] Error fetching user: \(error)")
            if let apiError = error as? APIError {
                print("❌ [Fetch User] API Error details: \(apiError)")
                print("❌ [Fetch User] Error description: \(apiError.errorDescription ?? "none")")
            }
            currentUser = nil
        }
    }
    
    // MARK: - Error Handling
    
    private func handleAuthError(_ error: APIError) {
        switch error {
        case .badRequest(let message):
            if message.contains("row-level security") || message.contains("RLS") {
                errorMessage = NSLocalizedString("auth.error.profile_creation_failed", comment: "")
            } else if message.contains("users_handle_key") || message.contains("duplicate key") || message.contains("23505") {
                errorMessage = NSLocalizedString("auth.error.handle_taken", comment: "")
            } else if message.contains("users_email_key") || message.contains("email") {
                errorMessage = NSLocalizedString("auth.error.email_taken", comment: "")
            } else {
                errorMessage = message
            }
        case .unauthorized:
            errorMessage = NSLocalizedString("auth.error.unauthorized", comment: "")
        case .rateLimitExceeded:
            errorMessage = NSLocalizedString("auth.error.rate_limit", comment: "")
        default:
            errorMessage = error.errorDescription
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        client.clearAuthToken()
        isAuthenticated = false
        currentUser = nil
        needsProfileCompletion = false
        print("✅ User signed out")
    }
    
    // MARK: - Clear Session (for testing)
    
    func clearSession() {
        client.clearAuthToken()
        isAuthenticated = false
        currentUser = nil
        needsProfileCompletion = false
        emailConfirmationRequired = false
        print("✅ Session cleared")
    }
    
    // MARK: - Validation
    
    func validateEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    func validateHandle(_ handle: String) -> String? {
        if handle.count < 3 {
            return NSLocalizedString("auth.error.handle_too_short", comment: "Username must be at least 3 characters")
        }
        if handle.count > 20 {
            return NSLocalizedString("auth.error.handle_too_long", comment: "Username must be less than 20 characters")
        }
        
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if handle.unicodeScalars.contains(where: { !allowedCharacters.contains($0) }) {
            return NSLocalizedString("auth.error.handle_invalid_chars", comment: "Username can only contain letters, numbers, and underscores")
        }
        
        if let firstChar = handle.first, !firstChar.isLetter && !firstChar.isNumber {
            return NSLocalizedString("auth.error.handle_invalid_start", comment: "Username must start with a letter or number")
        }
        
        return nil
    }
    
    // MARK: - Check Handle Availability

    func checkHandleAvailable(_ handle: String) async -> Bool {
        guard validateHandle(handle) == nil else {
            return false
        }
        
        do {
            struct HandleCheck: Codable {
                let handle: String
            }
            
            let response: [HandleCheck] = try await client.get(
                path: "/rest/v1/users",
                queryItems: [
                    URLQueryItem(name: "handle", value: "eq.\(handle)"),
                    URLQueryItem(name: "select", value: "handle")
                ],
                requiresAuth: false
            )
            
            let isAvailable = response.isEmpty
            print("📝 [Handle Check] @\(handle) available: \(isAvailable)")
            return isAvailable
            
        } catch {
            print("❌ [Handle Check] Error checking @\(handle): \(error)")
            return false
        }
    }
    // MARK: - Check Existing Session

    func checkExistingSession() async {
        print("🔐 [Session Check] Checking for existing session...")
        
        guard let _ = client.getAuthToken() else {  // ✅ Use underscore
            print("❌ [Session Check] No token found - user needs to sign in")
            isAuthenticated = false
            needsProfileCompletion = false
            return
        }
        
        print("✅ [Session Check] Token found, fetching user profile...")
        await fetchCurrentUser()
        
        if let user = currentUser {
            print("✅ [Session Check] User profile found: @\(user.handle)")
            
            if isProfileIncomplete(user) {
                print("⚠️ [Session Check] Profile incomplete")
                needsProfileCompletion = true
                isAuthenticated = false
            } else {
                print("✅ [Session Check] Session valid - user authenticated")
                isAuthenticated = true
                needsProfileCompletion = false
            }
        } else {
            print("❌ [Session Check] No user profile found - clearing session")
            signOut()
        }
    }
}

// MARK: - Auth Response Models

struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?
    let user: AuthUser
}

struct AuthUser: Decodable {
    let id: String
    let email: String?
    let phone: String?
    let role: String?
    let createdAt: String?
}
