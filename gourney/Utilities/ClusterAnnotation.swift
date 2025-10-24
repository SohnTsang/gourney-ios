//
//  MapClusteringHelper.swift
//  gourney
//
//  Pin clustering logic with loose clustering and performance optimization
//

import Foundation
import CoreLocation
import MapKit

// MARK: - Cluster Annotation

/// Represents a cluster of pins on the map
struct ClusterAnnotation: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let pinIds: [String]  // IDs of pins in this cluster
    let count: Int
    let isVisited: Bool  // True if any pin in cluster is visited
    
    init(coordinate: CLLocationCoordinate2D, pins: [PinAnnotation]) {
        self.id = UUID().uuidString
        self.coordinate = coordinate
        self.pinIds = pins.map { $0.id }
        self.count = pins.count
        self.isVisited = pins.contains { $0.isVisited }
    }
}

// MARK: - Clustering Helper

class MapClusteringHelper {
    
    /// Minimum distance (in meters) for pins to cluster together
    /// Lower = looser clustering (pins separate more easily)
    private static let baseClusteringDistance: Double = 50.0  // 50 meters base
    
    /// Perform clustering based on current map zoom level
    /// - Parameters:
    ///   - pins: All pins to cluster
    ///   - region: Current map region (determines zoom level)
    /// - Returns: Array of clusters (single pins or grouped)
    static func clusterPins(
        _ pins: [PinAnnotation],
        in region: MKCoordinateRegion
    ) -> [ClusterItem] {
        
        // Calculate zoom level from span
        let zoomLevel = calculateZoomLevel(from: region)
        
        // Adaptive clustering distance based on zoom
        let clusteringDistance = calculateClusteringDistance(for: zoomLevel)
        
        print("🔍 [Clustering] Zoom: \(String(format: "%.2f", zoomLevel)), Distance: \(Int(clusteringDistance))m")
        
        // If zoomed in very close, don't cluster at all
        if zoomLevel > 16 {
            return pins.map { .single($0) }
        }
        
        var unclustered = pins
        var clusters: [ClusterItem] = []
        
        // Greedy clustering algorithm
        while !unclustered.isEmpty {
            let current = unclustered.removeFirst()
            var clusterGroup = [current]
            
            // Find nearby pins
            unclustered.removeAll { pin in
                let distance = current.coordinate.distance(to: pin.coordinate)
                if distance < clusteringDistance {
                    clusterGroup.append(pin)
                    return true
                }
                return false
            }
            
            // Create cluster or single pin
            if clusterGroup.count > 1 {
                let centerCoord = calculateCentroid(of: clusterGroup)
                let cluster = ClusterAnnotation(coordinate: centerCoord, pins: clusterGroup)
                clusters.append(.cluster(cluster))
            } else {
                clusters.append(.single(current))
            }
        }
        
        print("📍 [Clustering] \(pins.count) pins → \(clusters.count) items")
        
        return clusters
    }
    
    // MARK: - Private Helpers
    
    /// Calculate zoom level from map region span
    private static func calculateZoomLevel(from region: MKCoordinateRegion) -> Double {
        let longitudeDelta = region.span.longitudeDelta
        
        // Zoom level formula (0 = world, 20 = street level)
        let zoomLevel = log2(360.0 / longitudeDelta)
        
        return max(0, min(20, zoomLevel))
    }
    
    /// Calculate adaptive clustering distance based on zoom level
    /// - Zoomed out (city level): Large distance = more clustering
    /// - Zoomed in (street level): Small distance = loose clustering
    private static func calculateClusteringDistance(for zoomLevel: Double) -> Double {
        switch zoomLevel {
        case 0..<10:   // World/Country level
            return 5000.0  // 5km
        case 10..<12:  // City level
            return 1000.0  // 1km
        case 12..<14:  // District level
            return 300.0   // 300m
        case 14..<16:  // Neighborhood level
            return 100.0   // 100m (loose clustering)
        case 16..<18:  // Street level
            return 30.0    // 30m (very loose)
        default:       // Building level
            return 0.0     // No clustering
        }
    }
    
    /// Calculate centroid (center point) of multiple pins
    private static func calculateCentroid(of pins: [PinAnnotation]) -> CLLocationCoordinate2D {
        var totalLat = 0.0
        var totalLng = 0.0
        
        for pin in pins {
            totalLat += pin.coordinate.latitude
            totalLng += pin.coordinate.longitude
        }
        
        return CLLocationCoordinate2D(
            latitude: totalLat / Double(pins.count),
            longitude: totalLng / Double(pins.count)
        )
    }
}

// MARK: - Cluster Item Enum

/// Represents either a single pin or a cluster
enum ClusterItem: Identifiable {
    case single(PinAnnotation)
    case cluster(ClusterAnnotation)
    
    var id: String {
        switch self {
        case .single(let pin):
            return pin.id
        case .cluster(let cluster):
            return cluster.id
        }
    }
    
    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .single(let pin):
            return pin.coordinate
        case .cluster(let cluster):
            return cluster.coordinate
        }
    }
}

// MARK: - CLLocationCoordinate2D Extension

extension CLLocationCoordinate2D {
    /// Calculate distance to another coordinate in meters
    func distance(to coordinate: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: latitude, longitude: longitude)
        let location2 = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location1.distance(from: location2)
    }
}
