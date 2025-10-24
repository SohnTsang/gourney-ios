// Services/AppleMapKitService.swift
// Apple MapKit Search Service with improved error handling

import Foundation
import MapKit
import CoreLocation

final class AppleMapKitService {
    
    static let shared = AppleMapKitService()
    
    private init() {}
    
    // MARK: - Search Places
    
    func searchPlaces(
        query: String,
        region: MKCoordinateRegion,
        maxResults: Int = 5

    ) async throws -> [ApplePlaceResult] {
        
        // Validate query
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("❌ [Apple Maps] Empty query")
            return []
        }
        
        // Validate region
        guard region.span.latitudeDelta > 0 && region.span.longitudeDelta > 0 else {
            print("❌ [Apple Maps] Invalid region span")
            return []
        }
        
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = query
        searchRequest.region = region
        searchRequest.resultTypes = .pointOfInterest
        
        let search = MKLocalSearch(request: searchRequest)
        
        do {
            let response = try await search.start()
            
            print("🍎 [Apple Maps] Found \(response.mapItems.count) results for '\(query)'")
            
            return response.mapItems.compactMap { mapItem in
                guard let name = mapItem.name else { return nil }
                
                return ApplePlaceResult(
                    appleMapItem: mapItem,
                    name: name,
                    nameJa: extractJapaneseName(from: mapItem),
                    nameZh: extractChineseName(from: mapItem),
                    address: formatAddress(from: mapItem.placemark),
                    city: mapItem.placemark.locality ?? "",
                    ward: mapItem.placemark.subLocality,
                    lat: mapItem.placemark.coordinate.latitude,
                    lng: mapItem.placemark.coordinate.longitude,
                    phone: mapItem.phoneNumber,
                    website: mapItem.url?.absoluteString,
                    categories: extractCategories(from: mapItem)
                )
            }
        } catch let error as MKError {
            print("❌ [Apple Maps] MKError:")
            print("   Code: \(error.code)")
            print("   Description: \(error.localizedDescription)")
            
            // Treat most MKErrors as "no results" rather than fatal errors
            switch error.code {
            case .unknown, .placemarkNotFound:
                print("ℹ️ [Apple Maps] No results found")
                return []
            default:
                print("⚠️ [Apple Maps] Other error - treating as no results")
                return []
            }
        } catch {
            print("❌ [Apple Maps] Unexpected error: \(error)")
            return []
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatAddress(from placemark: MKPlacemark) -> String {
        var components: [String] = []
        
        if let subThoroughfare = placemark.subThoroughfare {
            components.append(subThoroughfare)
        }
        if let thoroughfare = placemark.thoroughfare {
            components.append(thoroughfare)
        }
        if let subLocality = placemark.subLocality {
            components.append(subLocality)
        }
        if let locality = placemark.locality {
            components.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            components.append(administrativeArea)
        }
        if let postalCode = placemark.postalCode {
            components.append(postalCode)
        }
        
        return components.joined(separator: ", ")
    }
    
    private func extractJapaneseName(from mapItem: MKMapItem) -> String? {
        return nil
    }
    
    private func extractChineseName(from mapItem: MKMapItem) -> String? {
        return nil
    }
    
    private func extractCategories(from mapItem: MKMapItem) -> [String] {
        guard let category = mapItem.pointOfInterestCategory else {
            return []
        }
        
        var categories: [String] = []
        
        switch category {
        case .restaurant:
            categories.append("restaurant")
        case .cafe:
            categories.append("cafe")
        case .bakery:
            categories.append("bakery")
        case .brewery:
            categories.append("brewery")
        case .nightlife:
            categories.append("bar")
        case .foodMarket:
            categories.append("food_market")
        default:
            break
        }
        
        return categories
    }
}

// MARK: - Apple Place Result Model

struct ApplePlaceResult {
    let appleMapItem: MKMapItem
    let name: String
    let nameJa: String?
    let nameZh: String?
    let address: String
    let city: String
    let ward: String?
    let lat: Double
    let lng: Double
    let phone: String?
    let website: String?
    let categories: [String]
    
    var applePlaceId: String {
        if #available(iOS 18.0, *) {
            if let identifier = appleMapItem.identifier {
                return identifier.rawValue
            }
        }
        return generateFallbackId()
    }
    
    private func generateFallbackId() -> String {
        let latStr = String(format: "%.6f", lat)
        let lngStr = String(format: "%.6f", lng)
        let nameHash = name.hash
        return "apple_\(latStr)_\(lngStr)_\(nameHash)"
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
