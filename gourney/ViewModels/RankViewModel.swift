// ViewModels/RankViewModel.swift
// Production-grade rank system with City/Country/World

import Foundation
import SwiftUI
import Combine

// MARK: - Models

struct LeaderboardEntry: Identifiable, Codable {
    let rank: Int
    let userId: String
    let handle: String
    let displayName: String?
    let avatarUrl: String?
    let weeklyPoints: Int
    let lifetimePoints: Int
    let isFollowing: Bool?
    
    var id: String { userId }
    
    enum CodingKeys: String, CodingKey {
        case rank
        case userId = "user_id"
        case handle
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case weeklyPoints = "weekly_points"
        case lifetimePoints = "lifetime_points"
        case isFollowing = "is_following"
    }
}

struct UserRank: Codable {
    let rank: Int?
    let weeklyPoints: Int
    let lifetimePoints: Int
    
    enum CodingKeys: String, CodingKey {
        case rank
        case weeklyPoints = "weekly_points"
        case lifetimePoints = "lifetime_points"
    }
}

struct LeaderboardResponse: Codable {
    let leaderboard: [LeaderboardEntry]
    let myRank: UserRank?
    let nextCursor: String?
    
    enum CodingKeys: String, CodingKey {
        case leaderboard
        case myRank = "my_rank"
        case nextCursor = "next_cursor"
    }
}

enum RankScope: String, CaseIterable {
    case city
    case country
    case world
    
    var localizedTitle: String {
        switch self {
        case .city: return NSLocalizedString("rank.scope.city", comment: "City")
        case .country: return NSLocalizedString("rank.scope.country", comment: "Country")
        case .world: return NSLocalizedString("rank.scope.world", comment: "World")
        }
    }
}

enum RankTimeframe: String, CaseIterable {
    case weekly = "week"
    case allTime = "lifetime"
    
    var localizedTitle: String {
        switch self {
        case .weekly: return NSLocalizedString("rank.timeframe.weekly", comment: "This Week")
        case .allTime: return NSLocalizedString("rank.timeframe.alltime", comment: "All Time")
        }
    }
}

// MARK: - ViewModel

@MainActor
class RankViewModel: ObservableObject {
    @Published var entries: [LeaderboardEntry] = []
    @Published var userRank: UserRank?
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    
    // Pagination
    private var cursor: String?
    @Published var hasMore = true
    
    // Filters
    @Published var selectedScope: RankScope = .city
    @Published var selectedTimeframe: RankTimeframe = .weekly
    @Published var selectedCity: String = "Tokyo"
    @Published var selectedCountry: String = "JP"
    
    private let client = SupabaseClient.shared
    private let authManager = AuthManager.shared
    
    // Available options
    let availableCities = ["Tokyo", "Osaka", "Singapore", "Hong Kong"]
    let availableCountries = [
        "JP": "Japan",
        "SG": "Singapore",
        "HK": "Hong Kong"
    ]
    
    // MARK: - Memory Management
    
    func clearMemory() {
        entries.removeAll(keepingCapacity: false)
        userRank = nil
        cursor = nil
        hasMore = true
        print("🧹 [Rank] Memory cleared")
    }
    
    // MARK: - Load Leaderboard
    
    func loadLeaderboard(loadMore: Bool = false) async {
        if loadMore {
            guard hasMore && !isLoadingMore else { return }
            isLoadingMore = true
        } else {
            isLoading = true
            cursor = nil
            hasMore = true
        }
        
        errorMessage = nil
        
        do {
            let response: LeaderboardResponse
            
            switch selectedScope {
            case .city:
                response = try await loadCityLeaderboard(loadMore: loadMore)
            case .country:
                response = try await loadCountryLeaderboard(loadMore: loadMore)
            case .world:
                response = try await loadWorldLeaderboard(loadMore: loadMore)
            }
            
            if loadMore {
                entries.append(contentsOf: response.leaderboard)
            } else {
                entries = response.leaderboard
                userRank = response.myRank
            }
            
            cursor = response.nextCursor
            hasMore = response.nextCursor != nil
            
            isLoading = false
            isLoadingMore = false
            
            print("✅ [Rank] Loaded \(entries.count) entries for \(selectedScope)")
            
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            isLoadingMore = false
            print("❌ [Rank] Load error: \(error)")
        }
    }
    
    // MARK: - Scope-Specific Loading
    
    // ✅ FIXED: Use queryItems parameter with URLQueryItem array
    private func loadCityLeaderboard(loadMore: Bool) async throws -> LeaderboardResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "city", value: selectedCity),
            URLQueryItem(name: "range", value: selectedTimeframe.rawValue),
            URLQueryItem(name: "limit", value: "50")
        ]
        
        if loadMore, let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        
        return try await client.request(
            path: "/functions/v1/leaderboard",
            method: "GET",
            body: nil,
            queryItems: queryItems,
            requiresAuth: true
        )
    }
    
    private func loadCountryLeaderboard(loadMore: Bool) async throws -> LeaderboardResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "country", value: selectedCountry),
            URLQueryItem(name: "range", value: selectedTimeframe.rawValue),
            URLQueryItem(name: "limit", value: "50")
        ]
        
        if loadMore, let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        
        return try await client.request(
            path: "/functions/v1/leaderboard-country",
            method: "GET",
            body: nil,
            queryItems: queryItems,
            requiresAuth: true
        )
    }
    
    private func loadWorldLeaderboard(loadMore: Bool) async throws -> LeaderboardResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "range", value: selectedTimeframe.rawValue),
            URLQueryItem(name: "limit", value: "50")
        ]
        
        if loadMore, let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        
        return try await client.request(
            path: "/functions/v1/leaderboard-world",
            method: "GET",
            body: nil,
            queryItems: queryItems,
            requiresAuth: true
        )
    }
    
    // MARK: - Helper Methods
    
    func rankEmoji(for rank: Int) -> String {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return ""
        }
    }
    
    func rankColor(for rank: Int) -> (red: Double, green: Double, blue: Double) {
        switch rank {
        case 1: return (1.0, 0.84, 0.0) // Gold
        case 2: return (0.75, 0.75, 0.75) // Silver
        case 3: return (0.8, 0.5, 0.2) // Bronze
        default: return (0.5, 0.5, 0.5) // Gray
        }
    }
    
    // MARK: - User City Detection
    
    func setUserHomeCity() {
        guard let user = authManager.currentUser else { return }
        if let homeCity = user.homeCity, availableCities.contains(homeCity) {
            selectedCity = homeCity
            print("✅ [Rank] Set city to user's home: \(homeCity)")
        }
    }
    
    func deriveCountryFromCity() {
        // Auto-select country based on city
        switch selectedCity {
        case "Tokyo", "Osaka", "Kyoto", "Yokohama", "Nagoya":
            selectedCountry = "JP"
        case "Singapore":
            selectedCountry = "SG"
        case "Hong Kong", "Kowloon":
            selectedCountry = "HK"
        default:
            selectedCountry = "JP"
        }
    }
}
