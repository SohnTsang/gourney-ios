// ViewModels/RankViewModel.swift
// ✅ Production-grade with Instagram-style memory management
// ✅ Fixed: Seamless tab switching - cancelled tasks don't reset loading state

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
    
    init(rank: Int, userId: String, handle: String, displayName: String?, avatarUrl: String?, weeklyPoints: Int, monthlyPoints: Int?, lifetimePoints: Int, isFollowing: Bool?) {
        self.rank = rank
        self.userId = userId
        self.handle = handle
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.weeklyPoints = weeklyPoints
        self.monthlyPoints = monthlyPoints
        self.lifetimePoints = lifetimePoints
        self.isFollowing = isFollowing
    }
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
    
    var apiType: String {
        switch self {
        case .home: return "home"
        case .current: return "current"
        case .global: return "global"
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
    
    // Memory optimization (Instagram pattern: ~100 max visible)
    private let maxEntries = 100
    private let pageSize = 20
    
    @Published var selectedTimeframe: RankTimeframe = .weekly
    @Published var selectedScope: LocationScope = .global
    
    @Published var currentCity: String?
    @Published var currentCountry: String?
    @Published var homeCity: String?
    @Published var homeCountry: String?
    
    private let client = SupabaseClient.shared
    private let authManager = AuthManager.shared
    private let locationManager = LocationManager.shared
    private let geocoder = CLGeocoder()
    
    private var cancellables = Set<AnyCancellable>()
    private var hasGeocodedOnce = false
    private var loadTask: Task<Void, Never>?
    
    // ✅ FIX: Track which task "owns" the loading state to prevent race conditions
    private var currentLoadId: UUID?
    
    init() {
        setupLocationTracking()
    }
    
    deinit {
        loadTask?.cancel()
        cancellables.removeAll()
        print("🧹 [Rank] ViewModel deinit")
    }
    
    // MARK: - Lifecycle (Instagram pattern)
    
    func onAppear() {
        print("📱 [Rank] View appeared - entries: \(entries.count), isLoading: \(isLoading)")
        // Reload if entries empty and not already loading
        if entries.isEmpty && !isLoading {
            errorMessage = nil
            isLoading = true
            let loadId = UUID()
            currentLoadId = loadId
            loadTask = Task { await loadLeaderboard(loadId: loadId) }
        }
    }
    
    func onDisappear() {
        loadTask?.cancel()
        loadTask = nil
        print("📱 [Rank] View disappeared - cancelled tasks, kept cache")
    }
    
    func clearAndReload() {
        loadTask?.cancel()
        
        // Set loading state and generate new load ID
        isLoading = true
        errorMessage = nil
        let loadId = UUID()
        currentLoadId = loadId
        
        entries.removeAll(keepingCapacity: false)
        userRank = nil
        cursor = nil
        hasMore = true
        
        loadTask = Task { await loadLeaderboard(loadId: loadId) }
        print("🔄 [Rank] Clear and reload triggered - loadId: \(loadId.uuidString.prefix(8))")
    }
    
    // MARK: - Location
    
    private func setupDefaultScope() {
        if homeCity != nil {
            selectedScope = .home
        } else if currentCity != nil {
            selectedScope = .current
        } else {
            selectedScope = .global
        }
    }
    
    private func setupLocationTracking() {
        if let user = authManager.currentUser {
            homeCity = user.homeCity
            if let city = homeCity {
                homeCountry = deriveCountryFromCity(city)
            }
        }
        
        locationManager.$userLocation
            .compactMap { $0 }
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] coordinate in
                guard let self = self, !self.hasGeocodedOnce else { return }
                Task { await self.reverseGeocode(coordinate: coordinate) }
            }
            .store(in: &cancellables)
        
        if let coordinate = locationManager.userLocation {
            Task { await reverseGeocode(coordinate: coordinate) }
        }
        
        print("🌍 [Rank] Location setup - home: \(homeCity ?? "nil"), current: \(currentCity ?? "nil")")
    }
    
    private func reverseGeocode(coordinate: CLLocationCoordinate2D) async {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            if let placemark = placemarks.first {
                if placemark.isoCountryCode == "JP" {
                    self.currentCity = placemark.administrativeArea
                } else {
                    self.currentCity = placemark.locality ?? placemark.administrativeArea
                }
                
                self.currentCountry = placemark.country
                self.hasGeocodedOnce = true
                setupDefaultScope()
                
                if let city = self.currentCity, let country = self.currentCountry {
                    Task { await self.updateUserCurrentLocation(city: city, country: country) }
                }
                
                if entries.isEmpty && !isLoading {
                    isLoading = true
                    let loadId = UUID()
                    currentLoadId = loadId
                    loadTask = Task { await loadLeaderboard(loadId: loadId) }
                }
                
                print("📍 [Rank] Geocoded: \(self.currentCity ?? "nil"), \(self.currentCountry ?? "nil")")
            }
        } catch {
            print("❌ [Rank] Geocode error: \(error)")
            if homeCity == nil && currentCity == nil {
                selectedScope = .global
            }
        }
    }
    
    private func updateUserCurrentLocation(city: String, country: String) async {
        guard let userId = authManager.currentUser?.id else { return }
        
        do {
            let _: EmptyResponse = try await client.request(
                path: "/rest/v1/users",
                method: "PATCH",
                body: ["current_city": city, "current_country": country],
                queryItems: [URLQueryItem(name: "id", value: "eq.\(userId)")],
                requiresAuth: true
            )
        } catch {
            print("⚠️ [Rank] Failed to update location: \(error)")
        }
    }
    
    private func deriveCountryFromCity(_ city: String) -> String? {
        switch city {
        case "Tokyo", "Osaka", "Kyoto", "Yokohama", "Nagoya", "Fukuoka", "Sapporo", "Kobe":
            return "Japan"
        case "Singapore": return "Singapore"
        case "Hong Kong": return "Hong Kong"
        default: return nil
        }
    }
    
    // MARK: - Display Helpers
    
    var displayLocationText: String {
        switch selectedScope {
        case .home: return formatLocation(city: homeCity, country: homeCountry) ?? "Set Home"
        case .current: return formatLocation(city: currentCity, country: currentCountry) ?? "Locating..."
        case .global: return "Global"
        }
    }
    
    var displayLocationIcon: String { selectedScope.icon }
    
    private func formatLocation(city: String?, country: String?) -> String? {
        guard let city = city else { return nil }
        return country != nil ? "\(city), \(country!)" : city
    }
    
    var canSelectHome: Bool { homeCity != nil }
    var canSelectCurrent: Bool { currentCity != nil }
    
    // MARK: - Data Loading
    
    func loadLeaderboard(loadMore: Bool = false, loadId: UUID? = nil) async {
        // ✅ FIX: Use loadId to track ownership of loading state
        // If no loadId provided (e.g., from pull-to-refresh), generate one
        let thisLoadId = loadId ?? UUID()
        if loadId == nil {
            currentLoadId = thisLoadId
        }
        
        // Check for cancellation early
        guard !Task.isCancelled else {
            print("⚡ [Rank] Load skipped - task already cancelled")
            return
        }
        
        if loadMore {
            guard hasMore && !isLoadingMore && entries.count < maxEntries else { return }
            isLoadingMore = true
        } else {
            isLoading = true
            cursor = nil
            hasMore = true
            errorMessage = nil
        }
        
        do {
            // Check cancellation before network call
            try Task.checkCancellation()
            
            let response: LeaderboardResponse
            
            switch selectedScope {
            case .home:
                guard let city = homeCity else {
                    // ✅ Only update state if we still own the loading
                    if currentLoadId == thisLoadId {
                        errorMessage = "Please set your home city"
                        isLoading = false
                    }
                    return
                }
                response = try await loadCityLeaderboard(city: city, type: "home", loadMore: loadMore)
                
            case .current:
                guard let city = currentCity else {
                    if currentLoadId == thisLoadId {
                        errorMessage = "Unable to determine current location"
                        isLoading = false
                    }
                    return
                }
                response = try await loadCityLeaderboard(city: city, type: "current", loadMore: loadMore)
                
            case .global:
                response = try await loadGlobalLeaderboard(loadMore: loadMore)
            }
            
            // ✅ FIX: Check if we still own the loading state before updating
            guard currentLoadId == thisLoadId else {
                print("⚡ [Rank] Load completed but ownership changed - discarding results")
                return
            }
            
            // Check cancellation after network call
            guard !Task.isCancelled else {
                print("⚡ [Rank] Load cancelled after network - not updating UI")
                return
            }
            
            if loadMore {
                let startRank = entries.count + 1
                let adjustedEntries = response.leaderboard.enumerated().map { index, entry in
                    LeaderboardEntry(
                        rank: startRank + index,
                        userId: entry.userId,
                        handle: entry.handle,
                        displayName: entry.displayName,
                        avatarUrl: entry.avatarUrl,
                        weeklyPoints: entry.weeklyPoints,
                        monthlyPoints: entry.monthlyPoints,
                        lifetimePoints: entry.lifetimePoints,
                        isFollowing: entry.isFollowing
                    )
                }
                entries.append(contentsOf: adjustedEntries)
                
                if entries.count >= maxEntries {
                    hasMore = false
                }
            } else {
                entries = response.leaderboard
                userRank = response.myRank
            }
            
            cursor = response.nextCursor
            hasMore = response.nextCursor != nil && entries.count < maxEntries
            
            isLoading = false
            isLoadingMore = false
            
            print("✅ [Rank] Loaded \(entries.count) entries for \(selectedScope)")
            
        } catch is CancellationError {
            // ✅ FIX: Only reset loading state if we still own it
            if currentLoadId == thisLoadId {
                isLoading = false
                isLoadingMore = false
            }
            print("⚡ [Rank] Load cancelled (CancellationError) - ownership: \(currentLoadId == thisLoadId)")
            
        } catch {
            // Check if this is a URL cancellation error
            if let urlError = error as? URLError, urlError.code == .cancelled {
                // ✅ FIX: Only reset loading state if we still own it
                if currentLoadId == thisLoadId {
                    isLoading = false
                    isLoadingMore = false
                }
                print("⚡ [Rank] Load cancelled (URLError) - ownership: \(currentLoadId == thisLoadId)")
                return
            }
            
            // ✅ FIX: Only show error if we still own the loading state
            if currentLoadId == thisLoadId {
                errorMessage = error.localizedDescription
                isLoading = false
                isLoadingMore = false
                print("❌ [Rank] Load error: \(error)")
            } else {
                print("⚡ [Rank] Error occurred but ownership changed - ignoring")
            }
        }
    }
    
    private func loadCityLeaderboard(city: String, type: String, loadMore: Bool) async throws -> LeaderboardResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "city", value: city),
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "range", value: selectedTimeframe.rawValue),
            URLQueryItem(name: "limit", value: "\(pageSize)")
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
            URLQueryItem(name: "limit", value: "\(pageSize)")
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
