// Services/LocationManager.swift
// MEMORY OPTIMIZED - Proper cleanup and throttling

import Foundation
import CoreLocation
import Combine

@MainActor
class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    // MARK: - Published Properties
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var heading: CLHeading?
    @Published var accuracy: CLLocationAccuracy = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private var lastLocationUpdate: Date?
    private var lastHeadingUpdate: Date?
    
    // ✅ PERFORMANCE: Throttle settings
    private let locationUpdateThrottleInterval: TimeInterval = 1.0 // 1 update/second max
    private let headingUpdateThrottleInterval: TimeInterval = 0.5 // 2 updates/second max
    
    // ✅ MEMORY: Track if we're actively using location
    private var isTracking = false
    
    private override init() {
        super.init()
        setupLocationManager()
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update every 10 meters minimum
        
        // ✅ POWER OPTIMIZATION
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.activityType = .other
        locationManager.showsBackgroundLocationIndicator = false
        
        authorizationStatus = locationManager.authorizationStatus
    }
    
    // MARK: - Public Methods
    
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        guard !isTracking else { return }
        isTracking = true
        MemoryDebugHelper.shared.logMemory(tag: "📡 LocationManager - Start")

        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        print("🟢 [LocationManager] Started tracking")
    }
    
    func stopUpdatingLocation() {
        guard isTracking else { return }
        isTracking = false
        MemoryDebugHelper.shared.logMemory(tag: "📡 LocationManager - Stop")

        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        print("🔴 [LocationManager] Stopped tracking")
    }
    
    // ✅ CLEANUP: Call this when view disappears
    func cleanup() {
        MemoryDebugHelper.shared.logMemory(tag: "🧹 LocationManager - Before Cleanup")

        stopUpdatingLocation()
        lastLocationUpdate = nil
        lastHeadingUpdate = nil
        MemoryDebugHelper.shared.logMemory(tag: "🧹 LocationManager - After Cleanup")

        print("🧹 [LocationManager] Cleaned up")
    }
    
    // MARK: - Helper Methods
    
    func distance(from coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let userLocation = userLocation else { return nil }
        
        let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        return userCLLocation.distance(from: targetLocation)
    }
    
    func formattedDistance(from coordinate: CLLocationCoordinate2D) -> String? {
        guard let distance = distance(from: coordinate) else { return nil }
        
        if distance < 100 {
            return String(format: "%.0fm", distance)
        } else if distance < 1000 {
            return String(format: "%.0fm", distance)
        } else if distance < 10000 {
            return String(format: "%.1fkm", distance / 1000)
        } else {
            return String(format: "%.0fkm", distance / 1000)
        }
    }
    
    // MARK: - Validation
    
    private func isValidLocation(_ location: CLLocation) -> Bool {
        // ✅ Reject locations with negative accuracy
        guard location.horizontalAccuracy >= 0 else {
            print("⚠️ [Location] Rejected: Negative accuracy")
            return false
        }
        
        // ✅ Reject locations with very poor accuracy (>100m)
        guard location.horizontalAccuracy <= 100 else {
            print("⚠️ [Location] Rejected: Poor accuracy (\(location.horizontalAccuracy)m)")
            return false
        }
        
        // ✅ Reject stale locations (>15 seconds old)
        guard abs(location.timestamp.timeIntervalSinceNow) < 15 else {
            print("⚠️ [Location] Rejected: Stale timestamp")
            return false
        }
        
        // ✅ Reject invalid coordinates
        guard location.coordinate.latitude.isFinite && location.coordinate.longitude.isFinite else {
            print("⚠️ [Location] Rejected: Invalid coordinates")
            return false
        }
        
        return true
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                startUpdatingLocation()
            case .denied, .restricted:
                stopUpdatingLocation()
            default:
                break
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            // ✅ THROTTLE: Prevent too-frequent updates
            if let lastUpdate = lastLocationUpdate,
               Date().timeIntervalSince(lastUpdate) < locationUpdateThrottleInterval {
                return
            }
            
            // ✅ VALIDATE: Only accept good quality locations
            guard isValidLocation(location) else {
                return
            }
            
            // ✅ UPDATE: Store new location
            userLocation = location.coordinate
            accuracy = location.horizontalAccuracy
            lastLocationUpdate = Date()
            
            print("📍 [Location] Updated: (\(location.coordinate.latitude), \(location.coordinate.longitude)), accuracy: \(location.horizontalAccuracy)m")
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            // ✅ THROTTLE: Prevent too-frequent heading updates
            if let lastUpdate = lastHeadingUpdate,
               Date().timeIntervalSince(lastUpdate) < headingUpdateThrottleInterval {
                return
            }
            
            // ✅ VALIDATE: Only accept valid headings
            guard newHeading.headingAccuracy >= 0 else { return }
            
            heading = newHeading
            lastHeadingUpdate = Date()
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // ✅ Ignore common errors
            if let clError = error as? CLError {
                switch clError.code {
                case .locationUnknown:
                    // This is normal, location will come soon
                    return
                case .denied:
                    print("❌ [Location] Permission denied")
                    authorizationStatus = .denied
                default:
                    print("❌ [Location] Error: \(error.localizedDescription)")
                }
            }
        }
    }
}
