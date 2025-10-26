// Views/Discover/PlaceInfoCard.swift
// ✅ Uses shared PlaceDetailSheet component

import SwiftUI

struct PlaceInfoCard: View {
    let place: Place
    var onDismiss: (() -> Void)?
    var onRefreshNeeded: (() -> Void)?
    
    @State private var showAddVisit = false
    
    var body: some View {
        PlaceDetailSheet(
            placeId: place.id,
            displayName: place.displayName,
            lat: place.lat,
            lng: place.lng,
            formattedAddress: place.formattedAddress,
            phoneNumber: place.phoneNumber,
            website: place.website,
            photoUrls: place.photoUrls,
            primaryButtonTitle: "Add Visit",
            primaryButtonAction: {
                showAddVisit = true
            },
            onDismiss: onDismiss
        )
        .sheet(isPresented: $showAddVisit) {
            AddVisitView(prefilledPlace: PlaceSearchResult(from: place))
        }
        .onChange(of: showAddVisit) { oldValue, newValue in
            if oldValue == true && newValue == false {
                // Refresh after adding visit
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    onRefreshNeeded?()
                }
            }
        }
    }
}

// MARK: - PlaceSearchResult Extension (for AddVisitView compatibility)

extension PlaceSearchResult {
    init(from place: Place) {
        self.init(
            source: place.provider == .apple ? .apple : .google,
            googlePlaceId: place.googlePlaceId,
            applePlaceId: place.applePlaceId,
            nameEn: place.nameEn,
            nameJa: place.nameJa,
            nameZh: place.nameZh,
            lat: place.lat,
            lng: place.lng,
            formattedAddress: place.formattedAddress,
            categories: place.categories,
            photoUrls: place.photoUrls,
            existsInDb: true,
            dbPlaceId: place.id,
            appleFullData: nil
        )
    }
}
