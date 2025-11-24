// ViewModels/RankViewModel.swift
// ✅ SIMPLIFIED: Home/Current/Global with total points

import Foundation
import SwiftUI
import Combine
import CoreLocation

// MARK: - Models

struct LeaderboardEntry: Identifiable, Codable {
    let rank: Int
    let userId: String
    let handle: String
    let displayName: String?
    let avatarUrl: String?
    let weeklyPoints: Int
    let monthlyPoints: Int?
    let lifetimePoints: Int
    let isFollowing: Bool?
    
    var id: String { userId }
}

struct UserRank: Codable {
    let rank: Int?
    let weeklyPoints: Int
    let monthlyPoints: Int?
    let lifetimePoints: Int
}

struct LeaderboardResponse: Codable {
    let leaderboard: [LeaderboardEntry]
    let myRank: UserRank?
    let nextCursor: String?
}

enum RankTimeframe: String, CaseIterable {
    case weekly = "week"
    case monthly = "month"
    case allTime = "lifetime"
    
    var localizedTitle: String {
        switch self {
        case .weekly: return NSLocalizedString("rank.timeframe.weekly", comment: "This Week")
        case .monthly: return NSLocalizedString("rank.timeframe.monthly", comment: "This Month")
        case .allTime: return NSLocalizedString("rank.timeframe.alltime", comment: "All Time")
        }
    }
}

enum LocationScope: Equatable {
    case home
    case current
    case global
    
    var title: String {
        switch self {
        case .home: return "Home"
        case .current: return "Current"
        case .global: return "Global"
        }
    }
    
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .current: return "location.fill"
        case .global: return "globe.americas.fill"
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
    
    private var cursor: String?
    @Published var hasMore = true
    
    @Published var selectedTimeframe: RankTimeframe = .weekly
    @Published var selectedScope: LocationScope = .home
    
    // Current location (from reverse geocoding)
    @Published var currentCity: String?
    @Published var currentCountry: String?
    
    // Home location (from user profile)
    @Published var homeCity: String?
    @Published var homeCountry: String?
    
    private let client = SupabaseClient.shared
    private let authManager = AuthManager.shared
    private let locationManager = LocationManager.shared
    private let geocoder = CLGeocoder()
    
    private var cancellables = Set<AnyCancellable>()
    private var hasGeocodedOnce = false
    
    init() {
        setupLocationTracking()
    }
    
    private func setupDefaultScope() {
        // Default to home if available, otherwise current, finally global
        if homeCity != nil {
            selectedScope = .home
        } else if currentCity != nil {
            selectedScope = .current
        } else {
            selectedScope = .global
        }
    }
    
    private func setupLocationTracking() {
        // Get home city/country from user profile
        if let user = authManager.currentUser {
            homeCity = user.homeCity
            // homeCountry will come from user profile when we add it
            // For now, derive from homeCity
            if let city = homeCity {
                homeCountry = deriveCountryFromCity(city)
            }
        }
        
        // Listen to location updates and reverse geocode
        locationManager.$userLocation
            .compactMap { $0 }
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] coordinate in
                guard let self = self, !self.hasGeocodedOnce else { return }
                Task {
                    await self.reverseGeocode(coordinate: coordinate)
                }
            }
            .store(in: &cancellables)
        
        // Initial reverse geocode if location available
        if let coordinate = locationManager.userLocation {
            Task {
                await reverseGeocode(coordinate: coordinate)
            }
        }
        
        print("🌍 [Rank] Location setup - home: \(homeCity ?? "nil"), current: \(currentCity ?? "nil")")
    }
    
    private func reverseGeocode(coordinate: CLLocationCoordinate2D) async {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            if let placemark = placemarks.first {
                // Japan: Use administrativeArea (prefecture = Tokyo)
                if placemark.isoCountryCode == "JP" {
                    self.currentCity = placemark.administrativeArea
                } else {
                    self.currentCity = placemark.locality ?? placemark.administrativeArea
                }
                
                self.currentCountry = placemark.country
                self.hasGeocodedOnce = true
                
                // Set default scope after we have location
                setupDefaultScope()
                
                // Update user's current_city in database
                if let city = self.currentCity, let country = self.currentCountry {
                    Task {
                        await self.updateUserCurrentLocation(city: city, country: country)
                    }
                }
                
                // Auto-load leaderboard if this is the first load
                if entries.isEmpty && !isLoading {
                    Task {
                        await loadLeaderboard()
                    }
                }
                
                print("📍 [Rank] Reverse geocoded: \(self.currentCity ?? "nil"), \(self.currentCountry ?? "nil")")
            }
        } catch {
            print("❌ [Rank] Reverse geocode error: \(error)")
            // Fall back to global if geocoding fails
            if homeCity == nil && currentCity == nil {
                selectedScope = .global
            }
        }
    }
    
    private func updateUserCurrentLocation(city: String, country: String) async {
        // Update users.current_city and current_country in database
        guard let userId = authManager.currentUser?.id else { return }
        
        do {
            let _: EmptyResponse = try await client.request(
                path: "/rest/v1/users",
                method: "PATCH",
                body: ["current_city": city, "current_country": country],
                queryItems: [URLQueryItem(name: "id", value: "eq.\(userId)")],
                requiresAuth: true
            )
            print("✅ [Rank] Updated user current location: \(city), \(country)")
        } catch {
            print("⚠️ [Rank] Failed to update current location: \(error)")
        }
    }
    
    private func deriveCountryFromCity(_ city: String) -> String? {
        switch city {
        case "Tokyo", "Osaka", "Kyoto", "Yokohama", "Nagoya", "Fukuoka", "Sapporo", "Kobe":
            return "Japan"
        case "Singapore":
            return "Singapore"
        case "Hong Kong":
            return "Hong Kong"
        default:
            return nil
        }
    }
    
    // MARK: - Display Helpers
    
    var displayLocationText: String {
        switch selectedScope {
        case .home:
            return formatLocation(city: homeCity, country: homeCountry) ?? "Set Home"
        case .current:
            return formatLocation(city: currentCity, country: currentCountry) ?? "Locating..."
        case .global:
            return "Global"
        }
    }
    
    var displayLocationIcon: String {
        return selectedScope.icon
    }
    
    private func formatLocation(city: String?, country: String?) -> String? {
        guard let city = city else { return nil }
        if let country = country {
            return "\(city), \(country)"
        }
        return city
    }
    
    var canSelectHome: Bool {
        return homeCity != nil
    }
    
    var canSelectCurrent: Bool {
        return currentCity != nil
    }
    
    // MARK: - Data Loading
    
    func clearMemory() {
        entries.removeAll(keepingCapacity: false)
        userRank = nil
        cursor = nil
        hasMore = true
        print("🧹 [Rank] Memory cleared")
    }
    
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
            case .home:
                guard let city = homeCity else {
                    errorMessage = "Please set your home city"
                    isLoading = false
                    return
                }
                response = try await loadCityLeaderboard(city: city, loadMore: loadMore)
                
            case .current:
                guard let city = currentCity else {
                    errorMessage = "Unable to determine current location"
                    isLoading = false
                    return
                }
                response = try await loadCityLeaderboard(city: city, loadMore: loadMore)
                
            case .global:
                response = try await loadGlobalLeaderboard(loadMore: loadMore)
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
    
    private func loadCityLeaderboard(city: String, loadMore: Bool) async throws -> LeaderboardResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "city", value: city),
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
    
    private func loadGlobalLeaderboard(loadMore: Bool) async throws -> LeaderboardResponse {
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
}
