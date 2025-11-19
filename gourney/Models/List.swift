// Models/RestaurantList.swift
// Updated with likes_count for social features

import Foundation

struct RestaurantList: Codable, Identifiable {
    let id: String
    let title: String
    let description: String?
    let visibility: String
    let itemCount: Int?
    let coverPhotoUrl: String?
    let createdAt: String
    var likesCount: Int?
    
    // Computed property if you need Date
    var createdDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: createdAt) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: createdAt)
    }
}

struct ListItem: Codable, Identifiable {
    let id: String
    let placeId: String
    let notes: String?
    let addedAt: String
    var place: Place?
    
    enum CodingKeys: String, CodingKey {
        case id
        case placeId
        case notes = "note"  // API uses singular "note"
        case addedAt = "createdAt"  // After snake_case conversion
        case place
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        placeId = try container.decode(String.self, forKey: .placeId)
        notes = try? container.decodeIfPresent(String.self, forKey: .notes)
        addedAt = try container.decode(String.self, forKey: .addedAt)
        
        // Decode nested place object
        if let placeContainer = try? container.nestedContainer(keyedBy: PlaceCodingKeys.self, forKey: .place) {
            let placeId = try placeContainer.decode(String.self, forKey: .id)
            let nameEn = try? placeContainer.decodeIfPresent(String.self, forKey: .nameEn)
            let nameJa = try? placeContainer.decodeIfPresent(String.self, forKey: .nameJa)
            let nameZh = try? placeContainer.decodeIfPresent(String.self, forKey: .nameZh)
            let lat = try placeContainer.decode(Double.self, forKey: .lat)
            let lng = try placeContainer.decode(Double.self, forKey: .lng)
            let address = try? placeContainer.decodeIfPresent(String.self, forKey: .address)
            let categories = try? placeContainer.decodeIfPresent([String].self, forKey: .categories)
            let priceLevel = try? placeContainer.decodeIfPresent(Int.self, forKey: .priceLevel)
            let avgRating = try? placeContainer.decodeIfPresent(Double.self, forKey: .avgRating)
            let visitCount = try? placeContainer.decodeIfPresent(Int.self, forKey: .visitCount)
            let googlePlaceId = try? placeContainer.decodeIfPresent(String.self, forKey: .googlePlaceId)
            let applePlaceId = try? placeContainer.decodeIfPresent(String.self, forKey: .applePlaceId)
            
            // Handle photoUrl (single) vs photoUrls (array)
            var photoUrls: [String]? = nil
            if let photoUrl = try? placeContainer.decodeIfPresent(String.self, forKey: .photoUrl), !photoUrl.isEmpty {
                photoUrls = [photoUrl]
            }
            
            self.place = Place(
                id: placeId,
                provider: .google,
                googlePlaceId: googlePlaceId,
                applePlaceId: applePlaceId,
                nameEn: nameEn,
                nameJa: nameJa,
                nameZh: nameZh,
                lat: lat,
                lng: lng,
                formattedAddress: address,
                categories: categories,
                photoUrls: photoUrls,
                openNow: nil,
                priceLevel: priceLevel,
                avgRating: avgRating,
                visitCount: visitCount,
                userRatingsTotal: nil,
                phone: nil,
                website: nil,
                openingHours: nil,
                createdAt: nil,
                updatedAt: nil
            )
        } else {
            self.place = nil
        }
    }
    
    private enum PlaceCodingKeys: String, CodingKey {
        case id, nameEn, nameJa, nameZh, lat, lng, address, categories
        case priceLevel, avgRating, visitCount, googlePlaceId, applePlaceId
        case photoUrl
    }
}

// MARK: - Empty Response
struct EmptyResponse: Codable {}

// MARK: - Lists Response Models
struct ListsGetResponse: Codable {
    let lists: [RestaurantList]
}

struct CreateListResponse: Codable {
    let list: RestaurantList
}

// MARK: - List with Like Status
struct ListWithLikeStatus: Codable {
    let id: String
    let title: String
    let description: String?
    let visibility: String
    let ownerId: String
    let ownerHandle: String?
    let ownerDisplayName: String?
    let ownerAvatarUrl: String?
    let createdAt: String
    let itemCount: Int
    let likesCount: Int
    let hasLiked: Bool
}

struct ListDetailResponse: Codable {
    let list: ListWithLikeStatus
    let items: [ListItem]
    let nextCursor: String?
}

// MARK: - Like Models
struct ListLike: Codable {
    let listId: String
    let userId: String
    let createdAt: String?
}

struct ListLikeResponse: Codable {
    let liked: Bool
    let likeCount: Int
}
