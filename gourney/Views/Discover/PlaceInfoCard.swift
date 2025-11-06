// Views/Discover/PlaceInfoCard.swift
// ✅ Uses shared PlaceDetailSheet component
// ✅ Efficient single-place refresh after visit posted

import SwiftUI

struct PlaceInfoCard: View {
    let place: Place
    @ObservedObject var viewModel: DiscoverViewModel
    var onDismiss: (() -> Void)?
    
    @State private var showAddVisit = false
    @State private var refreshTrigger = UUID()  // ✅ Trigger to reload PlaceDetailSheet
    
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
            googlePlaceId: place.googlePlaceId,  // ✅ Pass Google Place ID
            primaryButtonTitle: "Add Visit",
            primaryButtonAction: {
                showAddVisit = true
            },
            onDismiss: onDismiss
        )
        .id(refreshTrigger)  // ✅ Force reload when refreshTrigger changes
        .fullScreenCover(isPresented: $showAddVisit) {
            AddVisitView(
                prefilledPlace: PlaceSearchResult(from: place),
                showBackButton: true,
                onVisitPosted: { placeId in
                    // ✅ Refresh place data and reload sheet
                    Task {
                        await viewModel.refreshPlace(placeId: placeId)
                        await MainActor.run {
                            refreshTrigger = UUID()  // ✅ Trigger sheet reload
                        }
                    }
                }
            )
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
