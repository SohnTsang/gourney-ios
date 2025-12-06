// Utilities/ClusterAnnotation.swift
// Shared types for map annotations
// ✅ PinAnnotation: Used by DiscoverView for map pins

import Foundation
import CoreLocation
import MapKit

// MARK: - Pin Annotation (Shared Type)

struct PinAnnotation: Identifiable, Equatable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let isVisited: Bool  // true = red pin (DB), false = grey pin (external)
    let place: Place?
    let searchResult: PlaceSearchResult?
    
    static func == (lhs: PinAnnotation, rhs: PinAnnotation) -> Bool {
        lhs.id == rhs.id &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.isVisited == rhs.isVisited
    }
}

// MARK: - Cluster Annotation

struct ClusterAnnotation: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let count: Int
    let pins: [PinAnnotation]
    
    var hasVisited: Bool {
        pins.contains { $0.isVisited }
    }
}

// MARK: - Cluster Item (Union Type)

enum ClusterItem: Identifiable {
    case single(PinAnnotation)
    case cluster(ClusterAnnotation)
    
    var id: String {
        switch self {
        case .single(let pin): return pin.id
        case .cluster(let cluster): return cluster.id
        }
    }
    
    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .single(let pin): return pin.coordinate
        case .cluster(let cluster): return cluster.coordinate
        }
    }
}

// MARK: - Clustering Helper

class MapClusteringHelper {
    
    /// Cluster pins based on zoom level
    static func cluster(pins: [PinAnnotation], zoomLevel: Double) -> [ClusterItem] {
        guard !pins.isEmpty else { return [] }
        
        // At high zoom (street level), don't cluster
        if zoomLevel > 15 {
            return pins.map { .single($0) }
        }
        
        // Clustering distance based on zoom
        let clusterDistance = clusteringDistance(for: zoomLevel)
        
        var clusters: [ClusterItem] = []
        var processed = Set<String>()
        
        for pin in pins {
            guard !processed.contains(pin.id) else { continue }
            
            // Find nearby pins
            var nearbyPins = [pin]
            processed.insert(pin.id)
            
            for other in pins {
                guard !processed.contains(other.id) else { continue }
                
                let distance = pin.coordinate.distance(to: other.coordinate)
                if distance < clusterDistance {
                    nearbyPins.append(other)
                    processed.insert(other.id)
                }
            }
            
            if nearbyPins.count == 1 {
                clusters.append(.single(pin))
            } else {
                // Calculate cluster center
                let avgLat = nearbyPins.reduce(0) { $0 + $1.coordinate.latitude } / Double(nearbyPins.count)
                let avgLng = nearbyPins.reduce(0) { $0 + $1.coordinate.longitude } / Double(nearbyPins.count)
                
                let cluster = ClusterAnnotation(
                    id: "cluster_\(pin.id)",
                    coordinate: CLLocationCoordinate2D(latitude: avgLat, longitude: avgLng),
                    count: nearbyPins.count,
                    pins: nearbyPins
                )
                clusters.append(.cluster(cluster))
            }
        }
        
        return clusters
    }
    
    /// Clustering distance in meters based on zoom level
    private static func clusteringDistance(for zoomLevel: Double) -> Double {
        switch zoomLevel {
        case 0..<5:   return 5000   // World view: 5km
        case 5..<8:   return 1000   // Country: 1km
        case 8..<11:  return 300    // City: 300m
        case 11..<14: return 100    // District: 100m
        case 14..<16: return 30     // Street: 30m
        default:      return 0      // Building: no clustering
        }
    }
}

// MARK: - CLLocationCoordinate2D Extension

extension CLLocationCoordinate2D {
    /// Calculate distance in meters to another coordinate
    func distance(to other: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: latitude, longitude: longitude)
        let loc2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return loc1.distance(from: loc2)
    }
}
