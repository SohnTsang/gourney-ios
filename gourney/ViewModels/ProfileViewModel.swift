// ViewModels/ProfileViewModel.swift
// Profile data management with visits, follow toggle, and map data
// Production-ready with memory optimization
// FIX: Always fetch from user-profile edge function for accurate counts

import Foundation
import SwiftUI
import MapKit
import Combine

@MainActor
class ProfileViewModel: ObservableObject {
    // MARK: - Published Properties
    
    // Profile Data
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    
    // Visits
    @Published private(set) var visits: [ProfileVisit] = []
    @Published private(set) var isLoadingVisits = false
    @Published private(set) var hasMoreVisits = true
    
    // Follow State
    @Published var isFollowing = false
    @Published private(set) var isTogglingFollow = false
    
    // Bio
    @Published var isBioExpanded = false
    
    // MARK: - Private Properties
    
    private let client = SupabaseClient.shared
    private var handle: String?
    private var userId: String?
    private var visitsCursor: VisitsCursor?
    private var fetchTask: Task<Void, Never>?
    private var visitsTask: Task<Void, Never>?
    private let pageSize = 20
    
    // MARK: - Computed Properties
    
    var isOwnProfile: Bool {
        guard let profileId = profile?.id else { return false }
        return profileId == AuthManager.shared.currentUser?.id
    }
    
    var displayPoints: Int {
        profile?.points ?? 0
    }
    
    var visitCoordinates: [CLLocationCoordinate2D] {
        visits.compactMap { visit in
            guard let lat = visit.place?.lat, let lng = visit.place?.lng else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }
    
    // MARK: - Initialization
    
    init() {}
    
    deinit {
        fetchTask?.cancel()
        visitsTask?.cancel()
    }
    
    // MARK: - Load Profile
    
    func loadProfile(handle: String? = nil, userId: String? = nil) {
        self.handle = handle
        self.userId = userId
        
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            await self?.performLoadProfile()
        }
    }
    
    /// FIX: For own profile, always fetch from edge function to get accurate counts
    func loadOwnProfile() {
        guard let user = AuthManager.shared.currentUser else {
            print("❌ [Profile] No current user found")
            return
        }
        
        print("👤 [Profile] Loading own profile for @\(user.handle)")
        
        // Set the handle and fetch from edge function for accurate data
        self.handle = user.handle
        
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            await self?.performLoadProfile()
        }
    }
    
    private func performLoadProfile() async {
        guard let handle = handle else {
            print("❌ [Profile] No handle provided")
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            let path = "/functions/v1/user-profile?handle=\(handle)"
            print("👤 [Profile] Fetching: \(path)")
            
            let response: UserProfileAPIResponse = try await client.get(
                path: path,
                requiresAuth: true
            )
            
            // Log all the data we received
            print("✅ [Profile] Loaded: @\(handle)")
            print("   📊 Points: \(response.points ?? 0)")
            print("   📋 Lists: \(response.listCount)")
            print("   🍽️ Visits: \(response.visitCount)")
            print("   👥 Followers: \(response.followerCount)")
            print("   👤 Following: \(response.followingCount)")
            print("   🔗 Relationship: \(response.relationship)")
            
            profile = response.toUserProfile()
            isFollowing = response.isFollowing
            
            // Load visits after profile
            await loadVisits(refresh: true)
            
        } catch {
            print("❌ [Profile] Error: \(error)")
            self.error = "Failed to load profile"
        }
        
        isLoading = false
    }
    
    // MARK: - Load Visits
    
    func loadVisits(refresh: Bool = false) async {
        guard let handle = handle ?? AuthManager.shared.currentUser?.handle else {
            print("❌ [Visits] No handle available")
            return
        }
        
        if refresh {
            visitsCursor = nil
            hasMoreVisits = true
            visits = []
        }
        
        guard hasMoreVisits else { return }
        
        isLoadingVisits = true
        
        do {
            var path = "/functions/v1/visits-history?handle=\(handle)&limit=\(pageSize)"
            if let cursor = visitsCursor {
                path += "&cursor_created_at=\(cursor.createdAt)&cursor_id=\(cursor.id)"
            }
            
            print("📋 [Visits] Fetching: \(path)")
            
            let response: ProfileVisitsResponse = try await client.get(
                path: path,
                requiresAuth: true
            )
            
            print("✅ [Visits] Received \(response.visits.count) visits")
            print("   📄 Has more: \(response.nextCursor != nil)")
            
            if refresh {
                visits = response.visits
            } else {
                let existingIds = Set(visits.map { $0.id })
                let newVisits = response.visits.filter { !existingIds.contains($0.id) }
                visits.append(contentsOf: newVisits)
            }
            
            hasMoreVisits = response.nextCursor != nil
            visitsCursor = response.nextCursor
            
            print("📊 [Visits] Total loaded: \(visits.count)")
            
        } catch {
            print("❌ [Visits] Error: \(error)")
        }
        
        isLoadingVisits = false
    }
    
    func loadMoreVisitsIfNeeded(currentVisit: ProfileVisit) {
        guard let index = visits.firstIndex(where: { $0.id == currentVisit.id }) else { return }
        
        if index >= visits.count - 5 && hasMoreVisits && visitsTask == nil {
            visitsTask = Task { [weak self] in
                await self?.loadVisits(refresh: false)
                self?.visitsTask = nil
            }
        }
    }
    
    // MARK: - Toggle Follow
    
    func toggleFollow() {
        guard !isOwnProfile, let targetId = profile?.id else { return }
        
        let wasFollowing = isFollowing
        
        // Optimistic update
        isFollowing = !wasFollowing
        if var currentProfile = profile {
            currentProfile.followerCount += wasFollowing ? -1 : 1
            profile = currentProfile
        }
        
        // Haptic
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        isTogglingFollow = true
        
        Task {
            do {
                let method = wasFollowing ? "DELETE" : "POST"
                let path = "/functions/v1/follows-manage?user_id=\(targetId)"
                
                print("👥 [Follow] \(method) \(path)")
                
                let response: FollowResponse = try await client.request(
                    path: path,
                    method: method,
                    requiresAuth: true
                )
                
                print("✅ [Follow] \(response.action)")
                
                // Sync with server
                isFollowing = response.action == "followed"
                if var currentProfile = profile {
                    currentProfile.followerCount = response.followerCount
                    profile = currentProfile
                }
                
            } catch {
                print("❌ [Follow] Error: \(error)")
                
                // Rollback
                isFollowing = wasFollowing
                if var currentProfile = profile {
                    currentProfile.followerCount += wasFollowing ? 1 : -1
                    profile = currentProfile
                }
            }
            
            isTogglingFollow = false
        }
    }
    
    // MARK: - Refresh
    
    func refresh() async {
        if let handle = handle {
            loadProfile(handle: handle)
        } else {
            loadOwnProfile()
        }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        await loadVisits(refresh: true)
    }
    
    // MARK: - Memory Management
    
    func cleanup() {
        fetchTask?.cancel()
        visitsTask?.cancel()
        
        if visits.count > 50 {
            visits = Array(visits.prefix(50))
            hasMoreVisits = true
        }
    }
    
    func reset() {
        fetchTask?.cancel()
        visitsTask?.cancel()
        profile = nil
        visits = []
        visitsCursor = nil
        hasMoreVisits = true
        isFollowing = false
        isLoadingVisits = false
        isLoading = false
        error = nil
        isBioExpanded = false
    }
}

// MARK: - Models

struct UserProfile {
    let id: String
    let handle: String
    let displayName: String
    let avatarUrl: String?
    let bio: String?
    var visitCount: Int
    var followerCount: Int
    var followingCount: Int
    var listCount: Int
    var points: Int
    let relationship: String
    var isFollowing: Bool
    let followsYou: Bool
    
    var displayNameOrHandle: String {
        if !displayName.isEmpty {
            return displayName
        }
        return handle
    }
}

struct ProfileVisit: Codable, Identifiable, Equatable {
    let id: String
    let rating: Int?
    let comment: String?
    let photoUrls: [String]?
    let visibility: String
    let visitedAt: String
    let createdAt: String
    let place: ProfilePlace?
    
    var photos: [String] { photoUrls ?? [] }
    var hasPhotos: Bool { !photos.isEmpty }
    
    static func == (lhs: ProfileVisit, rhs: ProfileVisit) -> Bool {
        lhs.id == rhs.id
    }
}

struct ProfilePlace: Codable {
    let id: String
    let nameEn: String?
    let nameJa: String?
    let nameZh: String?
    let city: String?
    let ward: String?
    let categories: [String]?
    let lat: Double?
    let lng: Double?
    
    var displayName: String {
        let locale = Locale.current.language.languageCode?.identifier ?? "en"
        switch locale {
        case "ja":
            return nameJa ?? nameEn ?? "Unknown"
        case "zh":
            return nameZh ?? nameEn ?? "Unknown"
        default:
            return nameEn ?? nameJa ?? "Unknown"
        }
    }
    
    // Convert to FeedPlace for FeedDetailView
    func toFeedPlace() -> FeedPlace {
        FeedPlace(
            id: id,
            nameEn: nameEn,
            nameJa: nameJa,
            nameZh: nameZh,
            city: city,
            ward: ward,
            country: nil,
            categories: categories
        )
    }
}

// MARK: - ProfileVisit to FeedItem Conversion

extension ProfileVisit {
    func toFeedItem(user: UserProfile) -> FeedItem {
        FeedItem(
            id: id,
            rating: rating,
            comment: comment,
            photoUrls: photoUrls,
            visibility: visibility,
            createdAt: createdAt,
            visitedAt: visitedAt,
            likeCount: 0,
            commentCount: 0,
            isLiked: false,
            isFollowing: true,
            user: FeedUser(
                id: user.id,
                handle: user.handle,
                displayName: user.displayName,
                avatarUrl: user.avatarUrl
            ),
            place: place?.toFeedPlace() ?? FeedPlace(
                id: "unknown",
                nameEn: "Unknown",
                nameJa: nil,
                nameZh: nil,
                city: nil,
                ward: nil,
                country: nil,
                categories: nil
            )
        )
    }
}

struct ProfileVisitsResponse: Codable {
    let visits: [ProfileVisit]
    let nextCursor: VisitsCursor?
}

struct VisitsCursor: Codable {
    let createdAt: String
    let id: String
    
    enum CodingKeys: String, CodingKey {
        case createdAt = "cursor_created_at"
        case id = "cursor_id"
    }
}

struct FollowResponse: Codable {
    let success: Bool
    let action: String
    let followeeId: String
    let followerCount: Int
}

struct ListsCountResponse: Codable {
    let lists: [RestaurantList]
    let totalCount: Int?
}

// MARK: - API Response Model (matches user-profile edge function)

struct UserProfileAPIResponse: Codable {
    let id: String
    let handle: String
    let displayName: String?
    let avatarUrl: String?
    let bio: String?
    let homeCity: String?
    let createdAt: String?
    let visitCount: Int
    let listCount: Int
    let followerCount: Int
    let followingCount: Int
    let points: Int?
    let relationship: String
    let isFollowing: Bool
    let followsYou: Bool
    
    func toUserProfile() -> UserProfile {
        UserProfile(
            id: id,
            handle: handle,
            displayName: displayName ?? handle,
            avatarUrl: avatarUrl,
            bio: bio,
            visitCount: visitCount,
            followerCount: followerCount,
            followingCount: followingCount,
            listCount: listCount,
            points: points ?? 0,
            relationship: relationship,
            isFollowing: isFollowing,
            followsYou: followsYou
        )
    }
}

// MARK: - Visits Response (matches visits-history edge function)

extension ProfileVisitsResponse {
    enum CodingKeys: String, CodingKey {
        case visits
        case nextCursor = "next_cursor"
    }
}

// MARK: - Follow Response (matches follows-manage edge function)

extension FollowResponse {
    enum CodingKeys: String, CodingKey {
        case success
        case action
        case followeeId = "followee_id"
        case followerCount = "follower_count"
    }
}
