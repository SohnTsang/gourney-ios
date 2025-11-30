// ViewModels/ProfileViewModel.swift
// Profile data management with visits, follow toggle, and map data
// Production-ready with memory optimization
// FIX: Added notification listeners for seamless visit updates

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
    private var currentProfileTask: Task<Void, Never>?
    private var currentVisitsTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private let pageSize = 20
    
    // Notification subscriptions
    private var cancellables = Set<AnyCancellable>()
    
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
    
    init() {
        setupNotificationListeners()
    }
    
    deinit {
        currentProfileTask?.cancel()
        currentVisitsTask?.cancel()
        paginationTask?.cancel()
        cancellables.removeAll()
    }
    
    // MARK: - Notification Listeners
    
    private func setupNotificationListeners() {
        // Listen for visit updates
        NotificationCenter.default.publisher(for: .visitDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleVisitUpdate(notification)
            }
            .store(in: &cancellables)
        
        // Listen for visit deletes
        NotificationCenter.default.publisher(for: .visitDidDelete)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleVisitDelete(notification)
            }
            .store(in: &cancellables)
        
        // Listen for visit creates
        NotificationCenter.default.publisher(for: .visitDidCreate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Refresh visits on create
                self?.refreshVisitsOnly()
            }
            .store(in: &cancellables)
    }
    
    private func handleVisitUpdate(_ notification: Notification) {
        guard let visitId = notification.userInfo?[VisitNotificationKeys.visitId] as? String,
              let updatedData = notification.userInfo?[VisitNotificationKeys.updatedVisit] as? VisitUpdateData else {
            print("⚠️ [ProfileVM] Received notification but missing data")
            return
        }
        
        print("📥 [ProfileVM] Received update notification for visit: \(visitId)")
        print("   📊 Current visits count: \(visits.count)")
        
        // Only update if this visit is in our list
        guard let index = visits.firstIndex(where: { $0.id == visitId }) else {
            print("📭 [ProfileVM] Visit \(visitId) not in current list, skipping")
            return
        }
        
        print("📥 [ProfileVM] Updating visit at index \(index): \(visitId)")
        
        // Create updated ProfileVisit preserving place data if not returned
        let existingVisit = visits[index]
        let updatedVisit = ProfileVisit(
            id: updatedData.id,
            rating: updatedData.rating,
            comment: updatedData.comment,
            photoUrls: updatedData.photoUrls,
            visibility: updatedData.visibility,
            visitedAt: updatedData.visitedAt,
            createdAt: updatedData.createdAt,
            place: updatedData.place.map { p in
                ProfilePlace(
                    id: p.id,
                    nameEn: p.nameEn,
                    nameJa: p.nameJa,
                    nameZh: nil,
                    city: p.city,
                    ward: p.ward,
                    categories: p.categories,
                    lat: p.lat,
                    lng: p.lng
                )
            } ?? existingVisit.place
        )
        
        visits[index] = updatedVisit
        print("✅ [ProfileVM] Visit updated - new photoUrls: \(updatedVisit.photoUrls ?? [])")
    }
    
    private func handleVisitDelete(_ notification: Notification) {
        guard let visitId = notification.userInfo?[VisitNotificationKeys.visitId] as? String else {
            return
        }
        
        if let index = visits.firstIndex(where: { $0.id == visitId }) {
            visits.remove(at: index)
            print("🗑️ [ProfileVM] Removed visit: \(visitId)")
            
            // Update visit count
            if var currentProfile = profile {
                currentProfile.visitCount = max(0, currentProfile.visitCount - 1)
                profile = currentProfile
            }
        }
    }
    
    private func refreshVisitsOnly() {
        Task {
            await loadVisitsInternal(refresh: true)
        }
    }
    
    // MARK: - Load Profile
    
    func loadProfile(handle: String? = nil, userId: String? = nil) {
        self.handle = handle
        self.userId = userId
        
        // Cancel any existing profile task
        currentProfileTask?.cancel()
        currentVisitsTask?.cancel()
        
        currentProfileTask = Task { [weak self] in
            await self?.performLoadProfile()
        }
    }
    
    /// For own profile - always fetch from edge function for accurate data
    func loadOwnProfile() {
        guard let user = AuthManager.shared.currentUser else {
            print("❌ [Profile] No current user found")
            return
        }
        
        print("👤 [Profile] Loading own profile for @\(user.handle)")
        self.handle = user.handle
        
        // Cancel any existing tasks
        currentProfileTask?.cancel()
        currentVisitsTask?.cancel()
        
        currentProfileTask = Task { [weak self] in
            await self?.performLoadProfile()
        }
    }
    
    private func performLoadProfile() async {
        guard let handle = handle else {
            print("❌ [Profile] No handle provided")
            return
        }
        
        // Only show loading if we don't have data yet
        if profile == nil {
            isLoading = true
        }
        error = nil
        
        do {
            let path = "/functions/v1/user-profile?handle=\(handle)"
            print("👤 [Profile] Fetching: \(path)")
            
            let response: UserProfileAPIResponse = try await client.get(
                path: path,
                requiresAuth: true
            )
            
            // Check if task was cancelled
            if Task.isCancelled { return }
            
            print("✅ [Profile] Loaded: @\(handle)")
            print("   📊 Points: \(response.points ?? 0)")
            print("   📋 Lists: \(response.listCount)")
            print("   🍽️ Visits: \(response.visitCount)")
            print("   👥 Followers: \(response.followerCount)")
            print("   👤 Following: \(response.followingCount)")
            print("   🔗 Relationship: \(response.relationship)")
            
            profile = response.toUserProfile()
            isFollowing = response.isFollowing
            isLoading = false
            
            // Load visits after profile (don't cancel if profile task continues)
            await loadVisitsInternal(refresh: true)
            
        } catch {
            if Task.isCancelled { return }
            print("❌ [Profile] Error: \(error)")
            self.error = "Failed to load profile"
            isLoading = false
        }
    }
    
    // MARK: - Load Visits
    
    private func loadVisitsInternal(refresh: Bool) async {
        guard let handle = handle else {
            print("❌ [Visits] No handle available")
            return
        }
        
        if refresh {
            visitsCursor = nil
            hasMoreVisits = true
            // Keep existing visits visible during refresh (Instagram pattern)
        }
        
        guard hasMoreVisits else { return }
        
        // Only show loading indicator if no visits yet
        if visits.isEmpty {
            isLoadingVisits = true
        }
        
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
            
            // Check if task was cancelled
            if Task.isCancelled { return }
            
            print("✅ [Visits] Received \(response.visits.count) visits")
            print("   📄 Has more: \(response.nextCursor != nil)")
            
            if refresh {
                // Replace visits on refresh
                visits = response.visits
            } else {
                // Append for pagination
                let existingIds = Set(visits.map { $0.id })
                let newVisits = response.visits.filter { !existingIds.contains($0.id) }
                visits.append(contentsOf: newVisits)
            }
            
            hasMoreVisits = response.nextCursor != nil
            visitsCursor = response.nextCursor
            
            print("📊 [Visits] Total loaded: \(visits.count)")
            
        } catch {
            if Task.isCancelled { return }
            print("❌ [Visits] Error: \(error)")
        }
        
        isLoadingVisits = false
    }
    
    func loadMoreVisitsIfNeeded(currentVisit: ProfileVisit) {
        guard let index = visits.firstIndex(where: { $0.id == currentVisit.id }) else { return }
        
        // Load more when near the end
        if index >= visits.count - 5 && hasMoreVisits && paginationTask == nil {
            paginationTask = Task { [weak self] in
                await self?.loadVisitsInternal(refresh: false)
                self?.paginationTask = nil
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
    
    // MARK: - Refresh (Pull to refresh)
    
    func refresh() async {
        // Ensure we have a handle
        if handle == nil {
            if let user = AuthManager.shared.currentUser {
                self.handle = user.handle
            } else {
                return
            }
        }
        
        // Don't cancel existing tasks - let them complete
        // Just start a new fetch that will update the data
        await performLoadProfile()
    }
    
    // MARK: - Memory Management
    
    func cleanup() {
        currentProfileTask?.cancel()
        currentVisitsTask?.cancel()
        paginationTask?.cancel()
        
        if visits.count > 50 {
            visits = Array(visits.prefix(50))
            hasMoreVisits = true
        }
    }
    
    /// Full reset - only call when navigating away completely
    func reset() {
        currentProfileTask?.cancel()
        currentVisitsTask?.cancel()
        paginationTask?.cancel()
        profile = nil
        visits = []
        visitsCursor = nil
        hasMoreVisits = true
        isFollowing = false
        isLoadingVisits = false
        isLoading = false
        error = nil
        isBioExpanded = false
        handle = nil
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
    
    // Compare all fields for SwiftUI to detect changes
    static func == (lhs: ProfileVisit, rhs: ProfileVisit) -> Bool {
        lhs.id == rhs.id &&
        lhs.rating == rhs.rating &&
        lhs.comment == rhs.comment &&
        lhs.photoUrls == rhs.photoUrls &&
        lhs.visibility == rhs.visibility
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

// MARK: - API Response Model

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

// MARK: - CodingKeys

extension ProfileVisitsResponse {
    enum CodingKeys: String, CodingKey {
        case visits
        case nextCursor = "next_cursor"
    }
}

extension FollowResponse {
    enum CodingKeys: String, CodingKey {
        case success
        case action
        case followeeId = "followee_id"
        case followerCount = "follower_count"
    }
}
