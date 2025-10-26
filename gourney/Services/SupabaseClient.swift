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
        } else {
            UserDefaults.standard.removeObject(forKey: "auth_token")
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
    
    func clearAuthToken() {
        authToken = nil
        UserDefaults.standard.removeObject(forKey: "auth_token")
    }
    
    
    
    private func buildURL(path: String, queryItems: [URLQueryItem]? = nil) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)!
        components.queryItems = queryItems
        return components.url!
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
        case 200...299:
            break
        case 401:
            clearAuthToken()
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
                print(jsonString.prefix(500))  // First 500 chars only
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
    
    func delete<T: Decodable>(path: String, queryItems: [URLQueryItem]? = nil, requiresAuth: Bool = true) async throws -> T {
        return try await request(path: path, method: "DELETE", queryItems: queryItems, requiresAuth: requiresAuth)
    }
    
    // MARK: - Upsert Method (for user profile creation)

    func upsert<T: Decodable>(path: String, body: [String: Any], queryItems: [URLQueryItem]? = nil, requiresAuth: Bool = true) async throws -> T {
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
        
        
        // Handle errors
        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            clearAuthToken()
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
        
        // CRITICAL: Handle empty response (still success)
        if data.isEmpty {
            print("⚠️ [API] UPSERT returned empty body despite 201 - this is a Supabase config issue")
            print("⚠️ [API] User was created successfully, fetching from database instead")
            throw APIError.decodingFailed // Will trigger fallback in AuthManager
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
