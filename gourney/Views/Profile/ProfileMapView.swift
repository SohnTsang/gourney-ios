//
//  ProfileMapView.swift
//  gourney
//
//  Created by 曾家浩 on 2025/11/26.
//


// Views/Profile/ProfileMapView.swift
// Simplified interactive map for profile visits
// Memory optimized with annotation cleanup

import SwiftUI
import MapKit

struct ProfileMapView: View {
    let visits: [ProfileVisit]
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var annotations: [ProfileMapAnnotation] = []
    @State private var selectedAnnotation: ProfileMapAnnotation?
    @State private var hasSetInitialRegion = false
    
    var body: some View {
        ZStack {
            if annotations.isEmpty {
                emptyState
            } else {
                mapContent
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            buildAnnotations()
        }
        .onDisappear {
            // Memory cleanup
            annotations.removeAll()
            selectedAnnotation = nil
        }
        .onChange(of: visits) { _, _ in
            buildAnnotations()
        }
    }
    
    // MARK: - Map Content
    
    private var mapContent: some View {
        Map(coordinateRegion: $region, annotationItems: annotations) { annotation in
            MapAnnotation(coordinate: annotation.coordinate) {
                annotationView(for: annotation)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
    
    // MARK: - Annotation View
    
    private func annotationView(for annotation: ProfileMapAnnotation) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                if selectedAnnotation?.id == annotation.id {
                    selectedAnnotation = nil
                } else {
                    selectedAnnotation = annotation
                }
            }
        } label: {
            VStack(spacing: 0) {
                // Info card (shown when selected)
                if selectedAnnotation?.id == annotation.id {
                    infoCard(for: annotation)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Pin
                ZStack {
                    Circle()
                        .fill(GourneyColors.coral)
                        .frame(width: 32, height: 32)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    
                    Image(systemName: "fork.knife")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Info Card
    
    private func infoCard(for annotation: ProfileMapAnnotation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(annotation.placeName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            if annotation.rating > 0 {
                RatingStarsView(
                    rating: annotation.rating,
                    size: 10,
                    spacing: 1,
                    filledColor: GourneyColors.coral,
                    emptyColor: .gray.opacity(0.3)
                )
            }
            
            if let ward = annotation.ward {
                Text(ward)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        )
        .padding(.bottom, 4)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 40))
                .foregroundColor(GourneyColors.coral.opacity(0.5))
            
            Text("No visits to display")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGray6))
    }
    
    // MARK: - Build Annotations
    
    private func buildAnnotations() {
        // Convert visits to annotations
        let newAnnotations = visits.compactMap { visit -> ProfileMapAnnotation? in
            guard let place = visit.place,
                  let lat = place.lat,
                  let lng = place.lng else { return nil }
            
            return ProfileMapAnnotation(
                id: visit.id,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                placeName: place.displayName,
                ward: place.ward,
                rating: visit.rating ?? 0,
                hasPhoto: visit.hasPhotos
            )
        }
        
        annotations = newAnnotations
        
        // Set region to fit all annotations
        if !hasSetInitialRegion && !newAnnotations.isEmpty {
            setRegionToFit(newAnnotations)
            hasSetInitialRegion = true
        }
    }
    
    // MARK: - Set Region to Fit
    
    private func setRegionToFit(_ annotations: [ProfileMapAnnotation]) {
        guard !annotations.isEmpty else { return }
        
        if annotations.count == 1 {
            // Single annotation - center on it with reasonable zoom
            region = MKCoordinateRegion(
                center: annotations[0].coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
            return
        }
        
        // Multiple annotations - fit all
        var minLat = annotations[0].coordinate.latitude
        var maxLat = annotations[0].coordinate.latitude
        var minLng = annotations[0].coordinate.longitude
        var maxLng = annotations[0].coordinate.longitude
        
        for annotation in annotations {
            minLat = min(minLat, annotation.coordinate.latitude)
            maxLat = max(maxLat, annotation.coordinate.latitude)
            minLng = min(minLng, annotation.coordinate.longitude)
            maxLng = max(maxLng, annotation.coordinate.longitude)
        }
        
        let centerLat = (minLat + maxLat) / 2
        let centerLng = (minLng + maxLng) / 2
        let spanLat = (maxLat - minLat) * 1.3 // Add padding
        let spanLng = (maxLng - minLng) * 1.3
        
        // Ensure minimum span
        let finalSpanLat = max(spanLat, 0.01)
        let finalSpanLng = max(spanLng, 0.01)
        
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng),
            span: MKCoordinateSpan(latitudeDelta: finalSpanLat, longitudeDelta: finalSpanLng)
        )
    }
}

// MARK: - Annotation Model

struct ProfileMapAnnotation: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let placeName: String
    let ward: String?
    let rating: Int
    let hasPhoto: Bool
}

#Preview {
    ProfileMapView(visits: [
        ProfileVisit(
            id: "1",
            rating: 4,
            comment: "Great!",
            photoUrls: ["https://example.com/1.jpg"],
            visibility: "public",
            visitedAt: "2024-01-15T12:00:00Z",
            createdAt: "2024-01-15T12:00:00Z",
            place: ProfilePlace(
                id: "p1",
                nameEn: "Ichiran Shibuya",
                nameJa: nil,
                nameZh: nil,
                city: "Tokyo",
                ward: "Shibuya",
                categories: nil,
                lat: 35.659,
                lng: 139.700
            )
        ),
        ProfileVisit(
            id: "2",
            rating: 5,
            comment: "Amazing!",
            photoUrls: nil,
            visibility: "public",
            visitedAt: "2024-01-14T18:00:00Z",
            createdAt: "2024-01-14T18:00:00Z",
            place: ProfilePlace(
                id: "p2",
                nameEn: "Sushi Saito",
                nameJa: nil,
                nameZh: nil,
                city: "Tokyo",
                ward: "Roppongi",
                categories: nil,
                lat: 35.664,
                lng: 139.731
            )
        )
    ])
    .frame(height: 400)
    .padding()
}