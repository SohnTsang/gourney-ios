//
//  ImageCache.swift
//  gourney
//
//  Created by 曾家浩 on 2025/12/05.
//


// Services/ImageCache.swift
// Instagram-style image caching with NSCache
// Production-grade with memory management, auto-recovery, and TTL
// Used across Profile, Feed, and other image-heavy views

import UIKit
import SwiftUI

// MARK: - Image Cache (Singleton)

final class ImageCache {
    static let shared = ImageCache()
    
    // MARK: - Cache Storage
    
    /// Main image cache - NSCache automatically handles memory pressure
    private let cache = NSCache<NSString, CachedImage>()
    
    /// Track URLs currently being fetched to prevent duplicate requests
    private var pendingRequests = Set<String>()
    private let pendingLock = NSLock()
    
    /// Track cache statistics for debugging
    private(set) var hitCount: Int = 0
    private(set) var missCount: Int = 0
    
    // MARK: - Configuration
    
    /// Maximum memory for cached images (~100MB)
    private let maxMemoryCost = 100 * 1024 * 1024
    
    /// Maximum number of cached images
    private let maxImageCount = 200
    
    /// Time-to-live for cached images (1 hour)
    private let cacheTTL: TimeInterval = 3600
    
    // MARK: - Initialization
    
    private init() {
        cache.totalCostLimit = maxMemoryCost
        cache.countLimit = maxImageCount
        cache.name = "com.gourney.imageCache"
        
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // Listen for app entering background - trim cache
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        print("🖼️ [ImageCache] Initialized - Max: \(maxImageCount) images, \(maxMemoryCost / 1024 / 1024)MB")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public API
    
    /// Get image from cache (returns nil if not cached or expired)
    func get(for url: String) -> UIImage? {
        guard let cached = cache.object(forKey: url as NSString) else {
            missCount += 1
            return nil
        }
        
        // Check if expired
        if Date().timeIntervalSince(cached.timestamp) > cacheTTL {
            cache.removeObject(forKey: url as NSString)
            missCount += 1
            print("🖼️ [ImageCache] Expired: \(url.suffix(30))")
            return nil
        }
        
        hitCount += 1
        return cached.image
    }
    
    /// Store image in cache
    func set(_ image: UIImage, for url: String) {
        let cost = imageCost(image)
        let cached = CachedImage(image: image, timestamp: Date())
        cache.setObject(cached, forKey: url as NSString, cost: cost)
    }
    
    /// Remove specific image from cache
    func remove(for url: String) {
        cache.removeObject(forKey: url as NSString)
    }
    
    /// Clear entire cache
    func clearAll() {
        cache.removeAllObjects()
        hitCount = 0
        missCount = 0
        print("🧹 [ImageCache] Cleared all cached images")
    }
    
    /// Get cache statistics
    var stats: String {
        let total = hitCount + missCount
        let hitRate = total > 0 ? Double(hitCount) / Double(total) * 100 : 0
        return "Hits: \(hitCount), Misses: \(missCount), Rate: \(String(format: "%.1f", hitRate))%"
    }
    
    // MARK: - Async Image Loading
    
    /// Load image with caching (async)
    func loadImage(from url: String) async -> UIImage? {
        // Check cache first
        if let cached = get(for: url) {
            return cached
        }
        
        // Check if already loading
        pendingLock.lock()
        if pendingRequests.contains(url) {
            pendingLock.unlock()
            // Wait for existing request to complete
            return await waitForPendingRequest(url: url)
        }
        pendingRequests.insert(url)
        pendingLock.unlock()
        
        defer {
            pendingLock.lock()
            pendingRequests.remove(url)
            pendingLock.unlock()
        }
        
        // Load from network
        guard let imageUrl = URL(string: url) else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: imageUrl)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                print("🖼️ [ImageCache] Failed to load: \(url.suffix(30))")
                return nil
            }
            
            // Downscale if too large (save memory)
            let optimizedImage = optimizeImage(image, maxDimension: 600)
            
            // Cache it
            set(optimizedImage, for: url)
            
            return optimizedImage
            
        } catch {
            print("🖼️ [ImageCache] Error loading \(url.suffix(30)): \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Private Helpers
    
    /// Calculate memory cost for an image
    private func imageCost(_ image: UIImage) -> Int {
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        return width * height * 4 // 4 bytes per pixel (RGBA)
    }
    
    /// Downscale image if too large
    private func optimizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        
        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }
        
        let scale = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    /// Wait for a pending request to complete
    private func waitForPendingRequest(url: String) async -> UIImage? {
        // Poll until request completes (max 10 seconds)
        for _ in 0..<100 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            
            pendingLock.lock()
            let stillPending = pendingRequests.contains(url)
            pendingLock.unlock()
            
            if !stillPending {
                return get(for: url)
            }
        }
        return nil
    }
    
    // MARK: - Memory Management
    
    @objc private func handleMemoryWarning() {
        // Clear 50% of cache on memory warning
        let countBefore = cache.countLimit
        cache.removeAllObjects()
        print("⚠️ [ImageCache] Memory warning - cleared cache (was ~\(countBefore) items)")
        print("📊 [ImageCache] Stats before clear: \(stats)")
    }
    
    @objc private func handleAppBackground() {
        // Trim cache when going to background
        print("🌙 [ImageCache] App backgrounded - cache stats: \(stats)")
    }
}

// MARK: - Cached Image Wrapper

private class CachedImage {
    let image: UIImage
    let timestamp: Date
    
    init(image: UIImage, timestamp: Date) {
        self.image = image
        self.timestamp = timestamp
    }
}

// MARK: - Cached Async Image View (SwiftUI)

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: String?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    @State private var loadFailed = false
    
    init(
        url: String?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = loadedImage {
                content(Image(uiImage: image))
            } else if loadFailed {
                placeholder()
            } else {
                placeholder()
                    .onAppear {
                        loadImage()
                    }
            }
        }
    }
    
    private func loadImage() {
        guard let url = url, !url.isEmpty else {
            loadFailed = true
            return
        }
        
        // Check cache synchronously first
        if let cached = ImageCache.shared.get(for: url) {
            loadedImage = cached
            isLoading = false
            return
        }
        
        // Load async
        Task {
            let image = await ImageCache.shared.loadImage(from: url)
            await MainActor.run {
                if let image = image {
                    loadedImage = image
                } else {
                    loadFailed = true
                }
                isLoading = false
            }
        }
    }
}

// MARK: - Convenience Extensions

extension CachedAsyncImage where Placeholder == EmptyView {
    init(
        url: String?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(url: url, content: content, placeholder: { EmptyView() })
    }
}

// MARK: - Profile Data Cache

final class ProfileDataCache {
    static let shared = ProfileDataCache()
    
    private struct CachedProfile {
        let profile: UserProfile
        let visits: [ProfileVisit]
        let hasMoreVisits: Bool
        let cursor: VisitsCursor?
        let timestamp: Date
    }
    
    private var cache: [String: CachedProfile] = [:] // keyed by handle
    private let lock = NSLock()
    
    /// Cache TTL (5 minutes - profiles don't change frequently)
    private let cacheTTL: TimeInterval = 300
    
    private init() {
        // Clear cache on memory warning
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearAll()
        }
    }
    
    // MARK: - Public API
    
    /// Get cached profile data if fresh
    func get(handle: String) -> (profile: UserProfile, visits: [ProfileVisit], hasMore: Bool, cursor: VisitsCursor?)? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let cached = cache[handle] else { return nil }
        
        // Check if expired
        if Date().timeIntervalSince(cached.timestamp) > cacheTTL {
            cache.removeValue(forKey: handle)
            print("📦 [ProfileCache] Expired: @\(handle)")
            return nil
        }
        
        print("📦 [ProfileCache] Hit: @\(handle)")
        return (cached.profile, cached.visits, cached.hasMoreVisits, cached.cursor)
    }
    
    /// Cache profile data
    func set(
        handle: String,
        profile: UserProfile,
        visits: [ProfileVisit],
        hasMore: Bool,
        cursor: VisitsCursor?
    ) {
        lock.lock()
        defer { lock.unlock() }
        
        cache[handle] = CachedProfile(
            profile: profile,
            visits: visits,
            hasMoreVisits: hasMore,
            cursor: cursor,
            timestamp: Date()
        )
        print("📦 [ProfileCache] Stored: @\(handle) (\(visits.count) visits)")
    }
    
    /// Update visits for a cached profile (for pagination)
    func updateVisits(
        handle: String,
        visits: [ProfileVisit],
        hasMore: Bool,
        cursor: VisitsCursor?
    ) {
        lock.lock()
        defer { lock.unlock() }
        
        guard let existing = cache[handle] else { return }
        
        cache[handle] = CachedProfile(
            profile: existing.profile,
            visits: visits,
            hasMoreVisits: hasMore,
            cursor: cursor,
            timestamp: existing.timestamp // Keep original timestamp
        )
    }
    
    /// Invalidate cache for a specific handle
    func invalidate(handle: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeValue(forKey: handle)
        print("📦 [ProfileCache] Invalidated: @\(handle)")
    }
    
    /// Clear all cached data
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
        print("🧹 [ProfileCache] Cleared all")
    }
}

// MARK: - Cache Manager (Coordinates all caches)

final class CacheManager {
    static let shared = CacheManager()
    
    private init() {}
    
    /// Clear all caches (call on logout or major state changes)
    func clearAll() {
        ImageCache.shared.clearAll()
        ProfileDataCache.shared.clearAll()
        print("🧹 [CacheManager] All caches cleared")
    }
    
    /// Invalidate profile-related caches for a user
    func invalidateProfile(handle: String) {
        ProfileDataCache.shared.invalidate(handle: handle)
    }
    
    /// Called when a new visit is posted
    func onVisitPosted(handle: String) {
        ProfileDataCache.shared.invalidate(handle: handle)
        print("📦 [CacheManager] Invalidated profile cache after visit post: @\(handle)")
    }
    
    /// Called when a visit is deleted
    func onVisitDeleted(handle: String) {
        ProfileDataCache.shared.invalidate(handle: handle)
        print("📦 [CacheManager] Invalidated profile cache after visit delete: @\(handle)")
    }
    
    /// Print cache statistics
    func printStats() {
        print("📊 [CacheManager] Image Cache: \(ImageCache.shared.stats)")
    }
}