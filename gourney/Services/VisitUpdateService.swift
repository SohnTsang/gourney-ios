// Services/VisitUpdateService.swift
// Centralized service for propagating visit updates across all views
// Ensures seamless UI/UX when visits are edited - Instagram pattern

import Foundation
import Combine

/// Notification names for visit-related events
extension Notification.Name {
    static let visitDidUpdate = Notification.Name("visitDidUpdate")
    static let visitDidDelete = Notification.Name("visitDidDelete")
    static let visitDidCreate = Notification.Name("visitDidCreate")
}

/// Keys for notification userInfo dictionary
struct VisitNotificationKeys {
    static let visitId = "visitId"
    static let updatedVisit = "updatedVisit"
}

/// Matches the response from visits-update edge function
struct VisitUpdateData: Codable {
    let id: String
    let userId: String
    let placeId: String
    let rating: Int?
    let comment: String?
    let photoUrls: [String]?
    let visibility: String
    let visitedAt: String
    let createdAt: String
    let deletedAt: String?
    let place: VisitUpdatePlace?
    
    var photos: [String] { photoUrls ?? [] }
}

struct VisitUpdatePlace: Codable {
    let id: String
    let nameEn: String?
    let nameJa: String?
    let city: String?
    let ward: String?
    let categories: [String]?
    let lat: Double?
    let lng: Double?
}

/// Singleton service for broadcasting visit updates
@MainActor
final class VisitUpdateService {
    static let shared = VisitUpdateService()
    
    private init() {}
    
    // MARK: - Notify Updates
    
    /// Call after successful visit update
    func notifyVisitUpdated(visitId: String, data: VisitUpdateData) {
        print("📢 [VisitUpdateService] Broadcasting update for visit: \(visitId)")
        
        NotificationCenter.default.post(
            name: .visitDidUpdate,
            object: nil,
            userInfo: [
                VisitNotificationKeys.visitId: visitId,
                VisitNotificationKeys.updatedVisit: data
            ]
        )
    }
    
    /// Call after successful visit delete
    func notifyVisitDeleted(visitId: String) {
        print("📢 [VisitUpdateService] Broadcasting delete for visit: \(visitId)")
        
        NotificationCenter.default.post(
            name: .visitDidDelete,
            object: nil,
            userInfo: [VisitNotificationKeys.visitId: visitId]
        )
    }
    
    /// Call after successful visit create
    func notifyVisitCreated(visitId: String) {
        print("📢 [VisitUpdateService] Broadcasting create for visit: \(visitId)")
        
        NotificationCenter.default.post(
            name: .visitDidCreate,
            object: nil,
            userInfo: [VisitNotificationKeys.visitId: visitId]
        )
    }
}

// MARK: - Conversion Extensions

extension VisitUpdateData {
    /// Convert to ProfileVisit for ProfileViewModel
    func toProfileVisit() -> ProfileVisit {
        ProfileVisit(
            id: id,
            rating: rating,
            comment: comment,
            photoUrls: photoUrls,
            visibility: visibility,
            visitedAt: visitedAt,
            createdAt: createdAt,
            place: place.map { p in
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
            }
        )
    }
    
    /// Convert to FeedItem - needs existing FeedItem for user data
    func toFeedItem(existingItem: FeedItem) -> FeedItem {
        FeedItem(
            id: id,
            rating: rating,
            comment: comment,
            photoUrls: photoUrls,
            visibility: visibility,
            createdAt: createdAt,
            visitedAt: visitedAt,
            likeCount: existingItem.likeCount,
            commentCount: existingItem.commentCount,
            isLiked: existingItem.isLiked,
            isFollowing: existingItem.isFollowing,
            user: existingItem.user,
            place: existingItem.place
        )
    }
}
