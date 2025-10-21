import SwiftUI

@main
struct GourneyApp: App {
    init() {
            #if DEBUG
            // Start monitoring every 3 seconds
            MemoryDebugHelper.shared.startMonitoring(interval: 3.0)
            #endif
        }
    @StateObject private var authManager = AuthManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                                    MemoryDebugHelper.shared.logMemory(tag: "🚀 App Started")
                                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    handleUniversalLink(userActivity)
                }
        }
    }
    
    // MARK: - Universal Links (https://gourney.jp/...)
    
    private func handleUniversalLink(_ userActivity: NSUserActivity) {
        guard let url = userActivity.webpageURL else {
            print("❌ [Universal Link] No webpage URL")
            return
        }
        
        print("🌐 [Universal Link] Received: \(url.absoluteString)")
        
        // Parse URL components
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            print("❌ [Universal Link] Could not parse URL")
            return
        }
        
        // Handle different paths
        switch components.path {
        case let path where path.hasPrefix("/auth/verify"),
             let path where path.hasPrefix("/auth/callback"):
            handleAuthCallback(url: url, components: components)
            
        case let path where path.hasPrefix("/u/"):
            handleUserProfile(path: path)
            
        case let path where path.hasPrefix("/visit/"):
            handleVisitDeepLink(path: path)
            
        default:
            print("ℹ️ [Universal Link] Unknown path: \(components.path)")
        }
    }
    
    // MARK: - Deep Links (gourney://...)
    
    private func handleDeepLink(_ url: URL) {
        print("🔗 [Deep Link] Received: \(url.absoluteString)")
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            print("❌ [Deep Link] Could not parse URL")
            return
        }
        
        // Handle auth callback
        if components.path.contains("auth/callback") || url.host == "auth" {
            handleAuthCallback(url: url, components: components)
        }
    }
    
    // MARK: - Handle Auth Callback (Email Verification)
    
    private func handleAuthCallback(url: URL, components: URLComponents) {
        print("🔐 [Auth Callback] Processing authentication")
        print("🔐 [Auth Callback] Full URL: \(url.absoluteString)")
        
        // Extract access_token from fragment or query
        var token: String?
        var refreshToken: String?
        
        // Check fragment (#access_token=...)
        if let fragment = components.fragment {
            print("🔐 [Auth Callback] Fragment found: \(fragment)")
            let params = fragment.components(separatedBy: "&")
            for param in params {
                let keyValue = param.components(separatedBy: "=")
                if keyValue.count == 2 {
                    if keyValue[0] == "access_token" {
                        token = keyValue[1]
                    } else if keyValue[0] == "refresh_token" {
                        refreshToken = keyValue[1]
                    }
                }
            }
        }
        
        // Check query parameters (?access_token=...)
        if token == nil, let queryItems = components.queryItems {
            token = queryItems.first(where: { $0.name == "access_token" })?.value
            refreshToken = queryItems.first(where: { $0.name == "refresh_token" })?.value
        }
        
        guard let accessToken = token else {
            print("❌ [Auth Callback] No access token found")
            print("❌ [Auth Callback] Fragment: \(components.fragment ?? "none")")
            print("❌ [Auth Callback] Query: \(components.queryItems?.description ?? "none")")
            
            // Show error to user
            Task { @MainActor in
                authManager.errorMessage = "Email verification failed. Please try again."
            }
            return
        }
        
        print("✅ [Auth Callback] Got access token (length: \(accessToken.count))")
        if let refresh = refreshToken {
            print("✅ [Auth Callback] Got refresh token (length: \(refresh.count))")
        }
        
        Task { @MainActor in
            // Save the token
            authManager.client.setAuthToken(accessToken)
            print("✅ [Auth Callback] Token saved to AuthManager")
            
            // Show loading state
            authManager.isLoading = true
            authManager.errorMessage = nil
            
            // Check if user profile exists
            await authManager.checkAuthStatus()
            
            if authManager.currentUser == nil {
                // New user - show profile completion
                print("📝 [Auth Callback] New user - showing profile completion")
                authManager.needsProfileCompletion = true
                authManager.isAuthenticated = false
                authManager.emailConfirmationRequired = false
            } else if let user = authManager.currentUser, authManager.isProfileIncomplete(user) {
                // Profile exists but incomplete (system-generated) - show profile completion
                print("📝 [Auth Callback] Profile incomplete - showing profile completion")
                authManager.needsProfileCompletion = true
                authManager.isAuthenticated = false
                authManager.emailConfirmationRequired = false
            } else {
                // Existing user with complete profile - authenticate
                print("✅ [Auth Callback] Existing user - authenticated as @\(authManager.currentUser?.handle ?? "unknown")")
                authManager.isAuthenticated = true
                authManager.needsProfileCompletion = false
                authManager.emailConfirmationRequired = false
            }
            
            authManager.isLoading = false
        }
    }
    
    // MARK: - Handle User Profile Deep Link
    
    private func handleUserProfile(path: String) {
        // Extract handle from path like "/u/username"
        let handle = path.replacingOccurrences(of: "/u/", with: "")
        print("👤 [Deep Link] Opening profile: @\(handle)")
        
        // TODO: Navigate to user profile
        // You can implement this later when you have profile navigation
    }
    
    // MARK: - Handle Visit Deep Link
    
    private func handleVisitDeepLink(path: String) {
        // Extract visit ID from path like "/visit/uuid"
        let visitId = path.replacingOccurrences(of: "/visit/", with: "")
        print("📍 [Deep Link] Opening visit: \(visitId)")
        
        // TODO: Navigate to visit detail
        // You can implement this later when you have visit detail view
    }
}
