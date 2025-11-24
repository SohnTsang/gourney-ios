//
//  SupabaseClient.swift
//  gourney
//
//  ✅ FIXED: Handles 3xx redirects and adds URL logging

import Foundation

class SupabaseClient {
    static let shared = SupabaseClient()
    
    private let baseURL: URL
    private let anonKey: String
    private var authToken: String?
    
    var authRefreshHandler: (() async -> Bool)?

    
    private init() {
        guard let url = URL(string: Config.supabaseURL) else {
            fatalError("Invalid Supabase URL")
        }
        self.baseURL = url
        self.anonKey = Config.supabaseAnonKey
    }
    
    // MARK: - Token Management
    
    func setAuthToken(_ token: String?) {
        self.authToken = token
        if let token = token {
            UserDefaults.standard.set(token, forKey: "auth_token")
            print("✅ [Token] Saved new token (ends: ...\(token.suffix(10)))")
        } else {
            UserDefaults.standard.removeObject(forKey: "auth_token")
            print("🗑️ [Token] Cleared token")
        }
    }
    
    func getAuthToken() -> String? {
        if let token = authToken {
            return token
        }
        if let savedToken = UserDefaults.standard.string(forKey: "auth_token") {
            authToken = savedToken
            return savedToken
        }
        return nil
    }
    
    // Get current user ID from JWT token
    func getCurrentUserId() -> String? {
        guard let token = getAuthToken() else { return nil }
        return TokenDiagnostics.decode(token)?.userId
    }
    
    func clearAuthToken() {
        authToken = nil
        UserDefaults.standard.removeObject(forKey: "auth_token")
    }
    
    
    
    private func buildURL(path: String, queryItems: [URLQueryItem]? = nil) -> URL {
        // Check if path already contains query parameters
        if path.contains("?") {
            // Path already has query string - append directly to baseURL
            guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
                fatalError("Invalid path: \(path)")
            }
            return url
        } else {
            // Normal path without query string - use URLComponents
            var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)!
            components.queryItems = queryItems
            return components.url!
        }
    }
    
    // MARK: - Request Building
    
    private func buildRequest(
        path: String,
        method: String,
        body: [String: Any]? = nil,
        queryItems: [URLQueryItem]? = nil,
        requiresAuth: Bool = true
    ) throws -> URLRequest {
        let url = buildURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // Headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue(Config.apiVersion, forHTTPHeaderField: "X-API-Version")
        
        // Language header based on device locale
        let locale = Locale.current.language.languageCode?.identifier ?? "en"
        let languageMap = ["ja": "ja", "zh": "zh-Hant"]
        let apiLanguage = languageMap[locale] ?? "en"
        request.setValue(apiLanguage, forHTTPHeaderField: "Accept-Language")
        
        // Auth token
        if requiresAuth, let token = getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            print("🔐 [Request] Using token (ends: ...\(token.suffix(10)))")
        }
        
        // Body
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        return request
    }
    
    // MARK: - Generic Request Handler
    
    func request<T: Decodable>(
        path: String,
        method: String,
        body: [String: Any]? = nil,
        queryItems: [URLQueryItem]? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        let request = try buildRequest(
            path: path,
            method: method,
            body: body,
            queryItems: queryItems,
            requiresAuth: requiresAuth
        )
        
        // ✅ ENHANCED: Log full URL for debugging
        print("📤 [SupabaseClient] \(method) \(request.url?.absoluteString ?? "unknown")")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [API] Invalid response type")
            throw APIError.invalidResponse
        }
        
        // (NEW) Tiny logger to see what hit 401
        if httpResponse.statusCode == 401 {
            print("⚠️ [API] 401 from \(request.url?.path ?? "(unknown)") \(request.httpMethod ?? "")")
        }
        
        print("📥 [SupabaseClient] Response: \(httpResponse.statusCode)")
        
        // ✅ CRITICAL: Handle 3xx redirects
        if (300...399).contains(httpResponse.statusCode) {
            // Check if there's a Location header
            if let location = httpResponse.allHeaderFields["Location"] as? String {
                print("🔀 [SupabaseClient] Redirect to: \(location)")
                print("⚠️ [SupabaseClient] PostgREST doesn't normally redirect - check your API URL")
            }
            
            // Log response body to see what Supabase is returning
            if let responseBody = String(data: data, encoding: .utf8) {
                print("📦 [SupabaseClient] 3xx Response body:")
                print(responseBody)
            }
            
            throw APIError.badRequest("Unexpected redirect (300-399). Check API URL configuration.")
        }
        
        // Handle errors
        switch httpResponse.statusCode {
        case 204:
            // No Content - return empty response for EmptyResponse type
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            // For other types expecting 204, also return empty
            break
        case 200...299:
            break
        case 401:
            // Try a one-time refresh + retry if this endpoint needs auth
            if requiresAuth, let refresh = authRefreshHandler {
                print("🔄 [API] Attempting token refresh...")
                
                let refreshed = await refresh()
                
                if refreshed {
                    print("✅ [API] Token refreshed successfully, retrying request...")
                    
                    // CRITICAL: Small delay to ensure token is fully saved
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    
                    // Rebuild request with new token
                    let retry = try buildRequest(
                        path: path,
                        method: method,
                        body: body,
                        queryItems: queryItems,
                        requiresAuth: requiresAuth
                    )
                    
                    let (retryData, retryResp) = try await URLSession.shared.data(for: retry)
                    guard let retryHTTP = retryResp as? HTTPURLResponse else {
                        throw APIError.invalidResponse
                    }
                    
                    print("📥 [API] Retry response: \(retryHTTP.statusCode)")
                    
                    if retryHTTP.statusCode == 401 {
                        print("❌ [API] Still 401 after refresh - token may be invalid")
                        if let currentToken = getAuthToken() {
                            print("🔍 [Debug] Current token ends: ...\(currentToken.suffix(10))")
                        }
                    }
                    
                    switch retryHTTP.statusCode {
                    case 200...299:
                        let decoder = JSONDecoder()
                        decoder.keyDecodingStrategy = .convertFromSnakeCase
                        decoder.dateDecodingStrategy = .iso8601
                        return try decoder.decode(T.self, from: retryData)
                    case 429:
                        throw APIError.rateLimitExceeded
                    case 400...499:
                        if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: retryData) {
                            throw APIError.badRequest(errorResponse.message)
                        }
                        throw APIError.badRequest("Request failed")
                    case 500...599:
                        throw APIError.serverError
                    default:
                        throw APIError.unknown
                    }
                } else {
                    print("❌ [API] Token refresh failed")
                }
            }
            // No refresh available or not an auth'd call → bubble up
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimitExceeded
        case 400...499:
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw APIError.badRequest(errorResponse.message)
            }
            throw APIError.badRequest("Request failed")
        case 500...599:
            throw APIError.serverError
        default:
            throw APIError.unknown
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            
            // ✅ TEMPORARY DEBUG
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📦 [API] Raw JSON:")
                print(jsonString.prefix(2000))  // First 500 chars only
            }
            
            return try decoder.decode(T.self, from: data)
        } catch {
            if Config.isDebug {
                print("❌ Decode error: \(error)")
            }
            throw APIError.decodingFailed
        }
    }
    
    // MARK: - Convenience Methods
        
    func get<T: Decodable>(path: String, queryItems: [URLQueryItem]? = nil, requiresAuth: Bool = true) async throws -> T {
        return try await request(path: path, method: "GET", queryItems: queryItems, requiresAuth: requiresAuth)
    }
    
    func post<T: Decodable>(path: String, body: [String: Any], queryItems: [URLQueryItem]? = nil, requiresAuth: Bool = true) async throws -> T {
        return try await request(path: path, method: "POST", body: body, queryItems: queryItems, requiresAuth: requiresAuth)
    }
    
    func put<T: Decodable>(path: String, body: [String: Any], queryItems: [URLQueryItem]? = nil, requiresAuth: Bool = true) async throws -> T {
        return try await request(path: path, method: "PUT", body: body, queryItems: queryItems, requiresAuth: requiresAuth)
    }
    
    func patch<T: Decodable>(path: String, body: [String: Any], queryItems: [URLQueryItem]? = nil, requiresAuth: Bool = true) async throws -> T {
        return try await request(path: path, method: "PATCH", body: body, queryItems: queryItems, requiresAuth: requiresAuth)
    }
    
    func delete<T: Decodable>(path: String, queryItems: [URLQueryItem]? = nil, requiresAuth: Bool = true) async throws -> T {
        return try await request(path: path, method: "DELETE", queryItems: queryItems, requiresAuth: requiresAuth)
    }
    
    // MARK: - Upsert Method (for user profile creation)

    func upsert<T: Decodable>(
        path: String,
        body: [String: Any],
        queryItems: [URLQueryItem]? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        let url = buildURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue(Config.apiVersion, forHTTPHeaderField: "X-API-Version")

        // CRITICAL FIX: Combine both Prefer values in ONE header (comma-separated)
        request.setValue("return=representation,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        // Language header
        let locale = Locale.current.language.languageCode?.identifier ?? "en"
        let languageMap = ["ja": "ja", "zh": "zh-Hant"]
        let apiLanguage = languageMap[locale] ?? "en"
        request.setValue(apiLanguage, forHTTPHeaderField: "Accept-Language")

        // Auth token
        if requiresAuth, let token = getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Body
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            print("⚠️ [API] 401 from \(request.url?.path ?? "(unknown)") \(request.httpMethod ?? "")")
        }

        switch httpResponse.statusCode {
        case 200...299:
            break

        case 401:
            if requiresAuth, let refresh = authRefreshHandler, await refresh() {
                // Rebuild manually with fresh token
                var retry = URLRequest(url: buildURL(path: path, queryItems: queryItems))
                retry.httpMethod = "POST"
                retry.setValue("application/json", forHTTPHeaderField: "Content-Type")
                retry.setValue(anonKey, forHTTPHeaderField: "apikey")
                retry.setValue(Config.apiVersion, forHTTPHeaderField: "X-API-Version")
                retry.setValue("return=representation,resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
                retry.setValue(apiLanguage, forHTTPHeaderField: "Accept-Language")
                if let token = getAuthToken() {
                    retry.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                retry.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (retryData, retryResp) = try await URLSession.shared.data(for: retry)
                guard let retryHTTP = retryResp as? HTTPURLResponse else { throw APIError.invalidResponse }

                if retryHTTP.statusCode == 401 {
                    print("⚠️ [API] 401 again after refresh from \(retry.url?.path ?? "(unknown)")")
                }

                switch retryHTTP.statusCode {
                case 200...299:
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    decoder.dateDecodingStrategy = .iso8601
                    return try decoder.decode(T.self, from: retryData)
                case 429:
                    throw APIError.rateLimitExceeded
                case 400...499:
                    if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: retryData) {
                        throw APIError.badRequest(errorResponse.message)
                    }
                    throw APIError.badRequest("Request failed")
                case 500...599:
                    throw APIError.serverError
                default:
                    throw APIError.unknown
                }
            }
            throw APIError.unauthorized

        case 429:
            throw APIError.rateLimitExceeded

        case 400...499:
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw APIError.badRequest(errorResponse.message)
            }
            throw APIError.badRequest("Request failed")

        case 500...599:
            throw APIError.serverError

        default:
            throw APIError.unknown
        }

        if data.isEmpty {
            print("⚠️ [API] UPSERT returned empty body despite success; trigger fallback decode path")
            throw APIError.decodingFailed
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }


}

// MARK: - Error Types

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case rateLimitExceeded
    case badRequest(String)
    case serverError
    case decodingFailed
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return NSLocalizedString("error.network", comment: "Network error")
        case .unauthorized:
            return NSLocalizedString("error.unauthorized", comment: "Unauthorized")
        case .rateLimitExceeded:
            return NSLocalizedString("error.rate_limit", comment: "Too many requests")
        case .badRequest(let message):
            return message
        case .serverError:
            return NSLocalizedString("error.server", comment: "Server error")
        case .decodingFailed:
            return NSLocalizedString("error.decode", comment: "Data error")
        case .unknown:
            return NSLocalizedString("error.unknown", comment: "Unknown error")
        }
    }
}

struct ErrorResponse: Decodable {
    let error: String
    let message: String
}


extension SupabaseClient {
    
    /// Decode JWT and check if it's expired or needs refresh
    func diagnoseToken() -> TokenDiagnostics? {
        guard let token = getAuthToken() else {
            return nil
        }
        
        return TokenDiagnostics.decode(token)
    }
    
    /// Check if token is valid and refresh if needed
    /// Returns true if token is valid (or was successfully refreshed)
    func ensureValidToken() async -> Bool {
        guard let diagnostics = diagnoseToken() else {
            print("⚠️ [Token] No token available")
            return false
        }
        
        // Token expired - must refresh
        if diagnostics.isExpired {
            print("⚠️ [Token] Token expired, refreshing...")
            if let refreshHandler = authRefreshHandler {
                return await refreshHandler()
            }
            return false
        }
        
        // Token expiring soon - proactive refresh in background
        if diagnostics.needsRefresh {
            print("⚠️ [Token] Token expiring soon (\(Int(diagnostics.timeUntilExpiry/60)) min), refreshing proactively...")
            if let refreshHandler = authRefreshHandler {
                // Don't wait for result, just trigger refresh in background
                Task.detached(priority: .background) {
                    _ = await refreshHandler()
                }
            }
        }
        
        return true
    }
}

struct TokenDiagnostics {
    let isExpired: Bool
    let expiresAt: Date
    let issuedAt: Date
    let userId: String?
    let timeUntilExpiry: TimeInterval
    
    var needsRefresh: Bool {
        // Refresh if less than 5 minutes until expiry
        return timeUntilExpiry < 300
    }
    
    static func decode(_ token: String) -> TokenDiagnostics? {
        let segments = token.components(separatedBy: ".")
        guard segments.count > 1 else {
            print("❌ [Token] Invalid JWT format")
            return nil
        }
        
        var base64 = segments[1]
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 = base64.padding(toLength: base64.count + 4 - remainder, withPad: "=", startingAt: 0)
        }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [Token] Failed to decode JWT payload")
            return nil
        }
        
        // Extract claims
        let exp = json["exp"] as? TimeInterval ?? 0
        let iat = json["iat"] as? TimeInterval ?? 0
        let sub = json["sub"] as? String
        
        let expiresAt = Date(timeIntervalSince1970: exp)
        let issuedAt = Date(timeIntervalSince1970: iat)
        let now = Date()
        let timeUntilExpiry = expiresAt.timeIntervalSince(now)
        let isExpired = timeUntilExpiry <= 0
        
        return TokenDiagnostics(
            isExpired: isExpired,
            expiresAt: expiresAt,
            issuedAt: issuedAt,
            userId: sub,
            timeUntilExpiry: timeUntilExpiry
        )
    }
    
    func printDiagnostics() {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        
        print("🔐 [Token Diagnostics]")
        print("   User ID: \(userId ?? "unknown")")
        print("   Issued: \(formatter.string(from: issuedAt))")
        print("   Expires: \(formatter.string(from: expiresAt))")
        print("   Time until expiry: \(Int(timeUntilExpiry / 60)) minutes")
        print("   Status: \(isExpired ? "❌ EXPIRED" : needsRefresh ? "⚠️ NEEDS REFRESH" : "✅ VALID")")
    }
}


#if DEBUG
import Foundation

extension SupabaseClient {
    
    // MARK: - Mock Expired Token
    
    /// Create and set a mock expired token for testing
    /// This simulates what happens when a real token expires
    func setMockExpiredToken(userId: String = "780c3ded-4691-4a88-ad6a-950cc356da7a") {
        print("\n" + String(repeating: "=", count: 50))
        print("🧪 [TEST] SETTING MOCK EXPIRED TOKEN")
        print(String(repeating: "=", count: 50))
        
        // JWT Header (standard HS256)
        let header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        
        // Create payload with expiry in the past
        let now = Int(Date().timeIntervalSince1970)
        let expiredTime = now - 3600  // 1 hour ago
        let issuedTime = now - 7200   // 2 hours ago
        
        let payloadDict: [String: Any] = [
            "sub": userId,
            "exp": expiredTime,
            "iat": issuedTime,
            "role": "authenticated",
            "aud": "authenticated"
        ]
        
        // Convert to JSON and base64
        let payloadData = try! JSONSerialization.data(withJSONObject: payloadDict)
        let payloadBase64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        // Fake signature (not validated in testing)
        let signature = "mock_signature_for_testing_purposes"
        
        // Combine parts
        let mockToken = "\(header).\(payloadBase64).\(signature)"
        
        // Set the mock token
        setAuthToken(mockToken)
        
        // Verify and print diagnostics
        print("✅ [TEST] Mock token created and set")
        print("📋 [TEST] Token info:")
        print("   - User ID: \(userId)")
        print("   - Expired: \(expiredTime) (1 hour ago)")
        print("   - Current: \(now)")
        
        if let diagnostics = diagnoseToken() {
            print("\n🔍 [TEST] Token Diagnostics:")
            diagnostics.printDiagnostics()
        }
        
        print("\n💡 [TEST] Next API call should:")
        print("   1. Detect token is expired")
        print("   2. Trigger refresh automatically")
        print("   3. Retry with new token")
        print("   4. Succeed")
        print(String(repeating: "=", count: 50) + "\n")
    }
    
    // MARK: - Mock Expiring Token
    
    /// Create a token that will expire in 2 minutes (for proactive refresh testing)
    func setMockExpiringToken(userId: String = "780c3ded-4691-4a88-ad6a-950cc356da7a") {
        print("\n" + String(repeating: "=", count: 50))
        print("⚠️ [TEST] SETTING MOCK EXPIRING TOKEN")
        print(String(repeating: "=", count: 50))
        
        let header = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        
        // Token expires in 2 minutes (triggers proactive refresh at 5 min threshold)
        let now = Int(Date().timeIntervalSince1970)
        let expiringTime = now + 120  // 2 minutes from now
        let issuedTime = now - 3480   // 58 minutes ago
        
        let payloadDict: [String: Any] = [
            "sub": userId,
            "exp": expiringTime,
            "iat": issuedTime,
            "role": "authenticated",
            "aud": "authenticated"
        ]
        
        let payloadData = try! JSONSerialization.data(withJSONObject: payloadDict)
        let payloadBase64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let signature = "mock_signature_for_testing_purposes"
        let mockToken = "\(header).\(payloadBase64).\(signature)"
        
        setAuthToken(mockToken)
        
        print("✅ [TEST] Mock expiring token set")
        print("📋 [TEST] Token expires in 2 minutes")
        print("💡 [TEST] Should trigger proactive refresh")
        
        if let diagnostics = diagnoseToken() {
            diagnostics.printDiagnostics()
        }
        
        print(String(repeating: "=", count: 50) + "\n")
    }
    
    // MARK: - Restore Real Token
    
    /// Trigger refresh to get a real token back
    func restoreRealToken() async -> Bool {
        print("\n" + String(repeating: "=", count: 50))
        print("🔄 [TEST] RESTORING REAL TOKEN")
        print(String(repeating: "=", count: 50))
        
        guard let refreshHandler = authRefreshHandler else {
            print("❌ [TEST] No refresh handler available")
            print(String(repeating: "=", count: 50) + "\n")
            return false
        }
        
        print("⚠️ [TEST] Calling refresh handler...")
        let success = await refreshHandler()
        
        if success {
            print("✅ [TEST] Real token restored successfully")
            if let diagnostics = diagnoseToken() {
                diagnostics.printDiagnostics()
            }
        } else {
            print("❌ [TEST] Failed to restore real token")
            print("💡 [TEST] You may need to sign in again")
        }
        
        print(String(repeating: "=", count: 50) + "\n")
        return success
    }
    
    // MARK: - Print Current Token Status
    
    /// Helper to quickly check current token status
    func printTokenStatus() {
        print("\n" + String(repeating: "=", count: 50))
        print("🔍 [TEST] CURRENT TOKEN STATUS")
        print(String(repeating: "=", count: 50))
        
        if let diagnostics = diagnoseToken() {
            diagnostics.printDiagnostics()
        } else {
            print("❌ [TEST] No token found")
        }
        
        print(String(repeating: "=", count: 50) + "\n")
    }
}

// MARK: - Test Scenarios Helper

extension SupabaseClient {
    
    /// Run through all test scenarios
    func runTokenTests() async {
        print("\n" + String(repeating: "=", count: 60))
        print("🧪 RUNNING ALL TOKEN TEST SCENARIOS")
        print(String(repeating: "=", count: 60) + "\n")
        
        // Test 1: Current token status
        print("📊 TEST 1: Current Token Status")
        printTokenStatus()
        
        // Test 2: Mock expired token
        print("\n📊 TEST 2: Mock Expired Token")
        setMockExpiredToken()
        
        // Wait a moment
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Test 3: Restore real token
        print("\n📊 TEST 3: Restore Real Token")
        let restored = await restoreRealToken()
        
        if restored {
            print("\n✅ ALL TESTS PASSED")
            print("💡 Token refresh mechanism is working correctly")
        } else {
            print("\n⚠️ TEST INCOMPLETE")
            print("💡 May need to sign in again")
        }
        func patch<T: Decodable>(path: String, body: [String: Any], queryItems: [URLQueryItem]? = nil, requiresAuth: Bool = true) async throws -> T {
            return try await request(path: path, method: "PATCH", body: body, queryItems: queryItems, requiresAuth: requiresAuth)
        }
        print("\n" + String(repeating: "=", count: 60) + "\n")
    }
}

#endif
