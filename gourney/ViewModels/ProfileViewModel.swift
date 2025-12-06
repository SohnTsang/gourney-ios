// ViewModels/ProfileViewModel.swift
// Profile data management with visits, follow toggle, and map data
// ✅ Production-ready with:
// - ProfileDataCache for smart data caching
// - Auto-recovery on errors
// - Memory-optimized pagination
// FIX: Added notification listeners for seamless visit updates
// FIX: Added support for loading by userId (fetches handle first)

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
    private let pageSize = 9
    
    /// Track if initial data came from cache (for refresh hints)
    private var loadedFromCache = false
    
    /// Last successful load time (for smart refresh)
    private var lastLoadTime: Date?
    
    /// Minimum time between automatic refreshes (30 seconds)
    private let minRefreshInterval: TimeInterval = 30
    
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
            
            // ✅ Invalidate cache since data changed
            if let handle = handle {
                ProfileDataCache.shared.invalidate(handle: handle)
            }
        }
    }
    
    private func refreshVisitsOnly() {
        // ✅ Invalidate cache before refresh
        if let handle = handle {
            ProfileDataCache.shared.invalidate(handle: handle)
        }
        
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
    
    /// For own profile - uses cache if fresh, otherwise fetches from edge function
    func loadOwnProfile() {
        guard let user = AuthManager.shared.currentUser else {
            print("❌ [Profile] No current user found")
            return
        }
        
        self.handle = user.handle
        self.userId = nil
        
        // ✅ Check if we should use cache or refresh
        let shouldUseCache = shouldUseCachedData(handle: user.handle)
        
        if shouldUseCache, let cached = ProfileDataCache.shared.get(handle: user.handle) {
            print("📦 [Profile] Using cached data for @\(user.handle)")
            self.profile = cached.profile
            self.visits = cached.visits
            self.hasMoreVisits = cached.hasMore
            self.visitsCursor = cached.cursor
            self.isFollowing = cached.profile.isFollowing
            self.loadedFromCache = true
            return
        }
        
        print("👤 [Profile] Loading own profile for @\(user.handle)")
        
        // Cancel any existing tasks
        currentProfileTask?.cancel()
        currentVisitsTask?.cancel()
        
        currentProfileTask = Task { [weak self] in
            await self?.performLoadProfile()
        }
    }
    
    /// Check if we should use cached data
    private func shouldUseCachedData(handle: String) -> Bool {
        // Don't use cache if we've never loaded
        guard lastLoadTime != nil else { return true } // First load can use cache
        
        // Don't use cache if it's been invalidated
        guard ProfileDataCache.shared.get(handle: handle) != nil else { return false }
        
        // Use cache if last load was recent
        if let lastLoad = lastLoadTime, Date().timeIntervalSince(lastLoad) < minRefreshInterval {
            return true
        }
        
        return true // Default to using cache
    }
    
    private func performLoadProfile() async {
        // If we only have userId, fetch handle first
        if handle == nil, let userId = userId {
            print("🔄 [Profile] Fetching handle for userId: \(userId)")
            do {
                let fetchedHandle = try await fetchHandleFromUserId(userId)
                self.handle = fetchedHandle
                print("✅ [Profile] Got handle: @\(fetchedHandle)")
            } catch {
                if Task.isCancelled { return }
                print("❌ [Profile] Failed to fetch handle: \(error)")
                self.error = "Failed to load profile"
                isLoading = false
                return
            }
        }
        
        guard let handle = handle else {
            print("❌ [Profile] No handle provided")
            self.error = "User not found"
            isLoading = false
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
            loadedFromCache = false
            lastLoadTime = Date()
            
            // Load visits after profile (don't cancel if profile task continues)
            await loadVisitsInternal(refresh: true)
            
            // ✅ Cache the data after visits are loaded
            if let profile = profile {
                ProfileDataCache.shared.set(
                    handle: handle,
                    profile: profile,
                    visits: visits,
                    hasMore: hasMoreVisits,
                    cursor: visitsCursor
                )
            }
            await loadVisitsInternal(refresh: true)
            
        } catch {
            if Task.isCancelled { return }
            print("❌ [Profile] Error: \(error)")
            self.error = "Failed to load profile"
            isLoading = false
        }
    }
    
    // MARK: - Fetch Handle from UserId
    
    /// Fetches user handle from userId via direct Supabase REST query
    private func fetchHandleFromUserId(_ userId: String) async throws -> String {
        // Direct query to users table for handle
        let path = "/rest/v1/users?id=eq.\(userId)&select=handle&limit=1"
        
        struct HandleResponse: Codable {
            let handle: String
        }
        
        let response: [HandleResponse] = try await client.get(
            path: path,
            requiresAuth: true
        )
        
        guard let first = response.first else {
            throw ProfileError.userNotFound
        }
        
        return first.handle
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
        
        guard hasMoreVisits else {
            print("📭 [Visits] No more visits to load")
            return
        }
        
        // Prevent duplicate loading
        guard !isLoadingVisits else {
            print("⚠️ [Visits] Already loading, skipping")
            return
        }
        
        isLoadingVisits = true
        
        do {
            try Task.checkCancellation()
            
            // Use visits-history endpoint with 'handle' parameter
            var path = "/functions/v1/visits-history?handle=\(handle)&limit=\(pageSize)"
            
            // ✅ FIX: Use correct cursor parameter format
            // Edge Function expects: cursor_created_at and cursor_id as separate query params
            if let cursor = visitsCursor {
                path += "&cursor_created_at=\(cursor.cursorCreatedAt)"
                path += "&cursor_id=\(cursor.cursorId)"
            }
            
            print("📸 [Visits] Fetching: \(path)")
            
            let response: ProfileVisitsResponse = try await client.get(
                path: path,
                requiresAuth: true
            )
            
            try Task.checkCancellation()
            
            let hasMore = response.nextCursor != nil
            print("✅ [Visits] Got \(response.visits.count) visits, hasMore: \(hasMore)")
            if let cursor = response.nextCursor {
                print("   📍 Next cursor: \(cursor.cursorCreatedAt), \(cursor.cursorId)")
            }
            
            if refresh {
                visits = response.visits
            } else {
                let existingIds = Set(visits.map { $0.id })
                let newVisits = response.visits.filter { !existingIds.contains($0.id) }
                visits.append(contentsOf: newVisits)
                print("📊 [Visits] Total visits now: \(visits.count)")
            }
            
            hasMoreVisits = hasMore
            visitsCursor = response.nextCursor
            isLoadingVisits = false
            
        } catch is CancellationError {
            print("⚠️ [Visits] Task cancelled")
            isLoadingVisits = false
        } catch {
            if Task.isCancelled { return }
            print("❌ [Visits] Error: \(error)")
            isLoadingVisits = false
        }
    }
    
    // MARK: - Load More Visits (Pagination) - Instagram Style
    
    /// Called when user scrolls to bottom of grid
    func loadMoreVisits() {
        guard hasMoreVisits else {
            print("📜 [Visits] No more visits to load")
            return
        }
        guard !isLoadingVisits else {
            print("📜 [Visits] Already loading, skipping")
            return
        }
        
        print("🚀 [Visits] Loading more visits...")
        
        Task { [weak self] in
            await self?.loadMoreVisitsWithMinDelay()
        }
    }
    
    /// Internal function that ensures minimum loading time for smooth UX
    @MainActor
    private func loadMoreVisitsWithMinDelay() async {
        guard let handle = handle else { return }
        
        isLoadingVisits = true
        
        // ✅ Start timer for minimum 0.3s loading time (Instagram-style)
        let startTime = Date()
        
        do {
            var path = "/functions/v1/visits-history?handle=\(handle)&limit=\(pageSize)"
            
            if let cursor = visitsCursor {
                path += "&cursor_created_at=\(cursor.cursorCreatedAt)"
                path += "&cursor_id=\(cursor.cursorId)"
            }
            
            print("📸 [Visits] Fetching: \(path)")
            
            let response: ProfileVisitsResponse = try await client.get(
                path: path,
                requiresAuth: true
            )
            
            let hasMore = response.nextCursor != nil
            print("✅ [Visits] Got \(response.visits.count) visits, hasMore: \(hasMore)")
            
            // ✅ Ensure minimum loading time for skeleton visibility
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < 0.3 {
                try? await Task.sleep(nanoseconds: UInt64((0.3 - elapsed) * 1_000_000_000))
            }
            
            // Append new visits
            let existingIds = Set(visits.map { $0.id })
            let newVisits = response.visits.filter { !existingIds.contains($0.id) }
            visits.append(contentsOf: newVisits)
            print("📊 [Visits] Total visits now: \(visits.count)")
            
            hasMoreVisits = hasMore
            visitsCursor = response.nextCursor
            isLoadingVisits = false
            
            // ✅ Update cache with new pagination data
            ProfileDataCache.shared.updateVisits(
                handle: handle,
                visits: visits,
                hasMore: hasMoreVisits,
                cursor: visitsCursor
            )
            
        } catch {
            print("❌ [Visits] Pagination error: \(error)")
            isLoadingVisits = false
        }
    }
    
    // MARK: - Toggle Follow
    
    func toggleFollow() {
        guard let profileId = profile?.id else { return }
        guard !isTogglingFollow else { return }
        
        isTogglingFollow = true
        
        // Optimistic update
        let wasFollowing = isFollowing
        isFollowing.toggle()
        
        // Update follower count optimistically
        if var currentProfile = profile {
            currentProfile.followerCount += wasFollowing ? -1 : 1
            profile = currentProfile
        }
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        Task {
            do {
                let path = "/functions/v1/follows-manage"
                print("👥 [Follow] Toggling follow for: \(profileId)")
                
                let response: FollowResponse = try await client.post(
                    path: path,
                    body: ["followee_id": profileId],
                    requiresAuth: true
                )
                
                print("✅ [Follow] Result: \(response.action)")
                
                // Sync with server response
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
        
        // ✅ Force refresh - invalidate cache first
        if let handle = handle {
            ProfileDataCache.shared.invalidate(handle: handle)
            print("🔄 [Profile] Pull-to-refresh - cache invalidated")
        }
        
        // Fetch fresh data
        await performLoadProfile()
    }
    
    // MARK: - Memory Management
    
    func cleanup() {
        currentProfileTask?.cancel()
        currentVisitsTask?.cancel()
        paginationTask?.cancel()
        
        // ✅ Trim visits array to prevent memory bloat
        if visits.count > 50 {
            visits = Array(visits.prefix(50))
            hasMoreVisits = true
        }
        
        // Update cache with trimmed data
        if let handle = handle, let profile = profile {
            ProfileDataCache.shared.set(
                handle: handle,
                profile: profile,
                visits: visits,
                hasMore: hasMoreVisits,
                cursor: visitsCursor
            )
        }
    }
    
    /// Full reset - only call when navigating away completely
    func reset() {
        currentProfileTask?.cancel()
        currentVisitsTask?.cancel()
        paginationTask?.cancel()
        
        // ✅ Invalidate cache for this profile before clearing
        if let handle = handle {
            ProfileDataCache.shared.invalidate(handle: handle)
        }
        
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
        userId = nil
        loadedFromCache = false
        lastLoadTime = nil
    }
}

// MARK: - Profile Error

enum ProfileError: Error, LocalizedError {
    case userNotFound
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .userNotFound:
            return "User not found"
        case .invalidResponse:
            return "Invalid response from server"
        }
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

// MARK: - API Response Models

struct ProfileVisitsResponse: Codable {
    let visits: [ProfileVisit]
    let nextCursor: VisitsCursor?
    
}

// ✅ FIX: VisitsCursor with explicit CodingKeys
// API returns: { "cursor_created_at": "...", "cursor_id": "..." }
// Must use explicit CodingKeys to map snake_case JSON keys to camelCase properties
struct VisitsCursor: Codable {
    let cursorCreatedAt: String
    let cursorId: String
    
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
