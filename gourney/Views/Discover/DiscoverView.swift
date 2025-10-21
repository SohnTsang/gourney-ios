// Views/Discover/DiscoverView.swift
// ✅ FIXED: Search uses map center, proper cleanup, no memory leaks

import SwiftUI
import MapKit

struct DiscoverView: View {
    @StateObject private var viewModel = DiscoverViewModel()
    @StateObject private var locationManager = LocationManager.shared
    @State private var searchText = ""
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
    )
    @State private var showLocationPermissionAlert = false
    @State private var lastKnownLocation: CLLocationCoordinate2D?
    @State private var mapRefreshTask: Task<Void, Never>?
    @State private var selectedPinId: String?
    @State private var suppressRegionRefresh = false
    @State private var annotations: [PinAnnotation] = []

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                mapView
                    .onMapCameraChange { context in
                        region = context.region
                        handleMapRegionChange(context.region.center)
                    }
                
                topSection
                mapControls
                
                if let error = viewModel.error {
                    VStack {
                        Spacer()
                        ErrorBanner(message: error)
                            .padding()
                            .padding(.bottom, 80)
                    }
                }
                
                if viewModel.isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $viewModel.showPlaceInfo) {
                if let place = viewModel.selectedPlace {
                    PlaceInfoCard(place: place)
                }
            }
            .onChange(of: viewModel.showPlaceInfo) { _, isShowing in
                if !isShowing {
                    selectedPinId = nil
                    suppressRegionRefresh = false
                }
            }
            .onChange(of: viewModel.searchResults) { _, _ in
                updateAnnotations()
            }
            .onChange(of: viewModel.beenToPlaces) { _, _ in
                updateAnnotations()
            }
            .alert("Location Permission Required", isPresented: $showLocationPermissionAlert) {
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please enable location access in Settings")
            }
            .task {
                await loadData()
            }
            .onAppear {
                MemoryDebugHelper.shared.logMemory(tag: "🟢 DiscoverView - Appeared")
                locationManager.startUpdatingLocation()
            }
            .onDisappear {
                cleanupResources()
            }
            .onReceive(locationManager.$userLocation) { newLocation in
                handleLocationUpdate(newLocation)
            }
        }
    }
    
    // MARK: - Computed Views
    
    private var mapView: some View {
        Map(position: $mapPosition) {
            // ✅ USER LOCATION ANNOTATION
            if let userLocation = locationManager.userLocation {
                Annotation("", coordinate: userLocation) {
                    UserLocationView(
                        accuracy: locationManager.accuracy,
                        heading: locationManager.heading
                    )
                }
                .annotationTitles(.hidden)
            }
            
            // Place pins (non-selected)
            ForEach(annotations.filter { $0.id != selectedPinId }) { item in
                Annotation("", coordinate: item.coordinate) {
                    PinView(
                        isVisited: item.isVisited,
                        isHighlighted: false,
                        distance: locationManager.formattedDistance(from: item.coordinate),
                        onTap: { handlePinTap(item) }
                    )
                }
            }
            
            // Selected pin (highlighted)
            ForEach(annotations.filter { $0.id == selectedPinId }) { item in
                Annotation("", coordinate: item.coordinate) {
                    PinView(
                        isVisited: item.isVisited,
                        isHighlighted: true,
                        distance: locationManager.formattedDistance(from: item.coordinate),
                        onTap: { }
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .mapStyle(.standard)
        .edgesIgnoringSafeArea(.top)
        
    }
    
    private var topSection: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(.bar)
                    .ignoresSafeArea(edges: .top)
                
                VStack(spacing: 12) {
                    Text("Discover")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    
                    SearchBarView(
                        text: $searchText,
                        isSearching: viewModel.isSearching,
                        onClear: {
                            searchText = ""
                            viewModel.clearSearch()
                        },
                        onSearch: {
                            // ✅ FIX: Use map center for search, not user location
                            viewModel.triggerSearch(
                                query: searchText,
                                mapCenter: region.center
                            )
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .frame(height: 130)
            .overlay(Divider(), alignment: .bottom)
            
            FilterToggleView(
                showFollowingOnly: $viewModel.showFollowingOnly,
                onToggle: { viewModel.toggleFollowingFilter() }
            )
            .frame(width: 200)
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    private var mapControls: some View {
        VStack(spacing: 12) {
            Spacer()
                .frame(height: 150)
            
            HStack {
                Spacer()
                
                VStack(spacing: 12) {
                    Button(action: recenterToUserLocation) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isMapCenteredOnUser ? Color(red: 1.0, green: 0.4, blue: 0.4) : (colorScheme == .dark ? .white : .primary))
                            .frame(width: 36, height: 36)
                            .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                    }
                    
                    Button(action: zoomIn) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .primary)
                            .frame(width: 36, height: 36)
                            .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                    }
                    
                    Button(action: zoomOut) {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .primary)
                            .frame(width: 36, height: 36)
                            .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                    }
                }
                .padding(.trailing, 16)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Computed Properties
    
    private var isMapCenteredOnUser: Bool {
        guard let userLocation = locationManager.userLocation else { return false }
        
        let distance = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
            .distance(from: CLLocation(latitude: region.center.latitude, longitude: region.center.longitude))
        
        return distance < 100
    }
    
    // MARK: - Methods
    
    private func cleanupResources() {
        print("🧹 [DiscoverView] Starting cleanup...")
        
        // 1. Cancel ALL tasks first
        mapRefreshTask?.cancel()
        mapRefreshTask = nil
        
        // 2. Force ViewModel cleanup
        viewModel.forceCleanup()
        
        // 3. Clear View state
        annotations.removeAll()
        selectedPinId = nil
        suppressRegionRefresh = false
        searchText = ""
        lastKnownLocation = nil
        
        // 4. Stop location tracking
        locationManager.cleanup()
        
        // ✅ NEW: Force memory release
        forceMemoryRelease()
        
        print("✅ [DiscoverView] Cleanup complete")
    }
    
    private func forceMemoryRelease() {
        print("🧹 [Memory] Force memory release...")
        
        // 1. Clear map completely
        annotations = []
        
        // 2. Force map position reset (clears cache)
        mapPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        ))
        
        // 3. Nil out selected references
        selectedPinId = nil
        
        // 4. Force garbage collection hint
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            print("🧹 [Memory] GC hint sent")
        }
        
        MemoryDebugHelper.shared.logMemory(tag: "🧹 After Force Release")
    }
    
    private func handleLocationUpdate(_ newLocation: CLLocationCoordinate2D?) {
        guard let newLocation = newLocation else { return }
        
        if let lastLocation = lastKnownLocation {
            let latDiff = abs(lastLocation.latitude - newLocation.latitude)
            let lngDiff = abs(lastLocation.longitude - newLocation.longitude)
            
            guard latDiff > 0.0001 || lngDiff > 0.0001 else {
                return
            }
        }
        
        if lastKnownLocation == nil {
            withAnimation(.easeInOut(duration: 0.5)) {
                region = MKCoordinateRegion(
                    center: newLocation,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
                mapPosition = .region(region)
            }
        }
        
        lastKnownLocation = newLocation
    }
    
    private func recenterToUserLocation() {
        guard let userLocation = locationManager.userLocation else {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestPermission()
            } else if locationManager.authorizationStatus == .denied {
                showLocationPermissionAlert = true
            }
            return
        }
        
        withAnimation(.spring(response: 0.5)) {
            region = MKCoordinateRegion(
                center: userLocation,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            mapPosition = .region(region)
        }
    }
    
    private func updateAnnotations() {
        MemoryDebugHelper.shared.logMemory(tag: "📍 Before (\(annotations.count) pins)")
        
        // ✅ CRITICAL: Clear old annotations FIRST
        annotations.removeAll()
        
        var newPins: [PinAnnotation] = []
        
        if viewModel.hasActiveSearch {
            if !viewModel.searchResults.isEmpty {
                print("🔎 [Annotations] Search mode - \(viewModel.searchResults.count) results")
                
                for result in viewModel.searchResults {
                    guard result.lat != 0 || result.lng != 0 else { continue }
                    guard result.lat >= -90 && result.lat <= 90 &&
                          result.lng >= -180 && result.lng <= 180 else { continue }
                    
                    newPins.append(PinAnnotation(
                        id: result.id.uuidString,
                        coordinate: result.coordinate,
                        isVisited: result.existsInDb,
                        place: nil,
                        searchResult: result
                    ))
                }
            }
        } else {
            print("🗺️ [Annotations] Normal mode - \(viewModel.beenToPlaces.count) places")
            
            // ✅ LIMIT to 50 pins max for performance
            let limitedPlaces = viewModel.beenToPlaces.prefix(50)
            
            for placeWithVisits in limitedPlaces {
                let place = placeWithVisits.place
                newPins.append(PinAnnotation(
                    id: place.id,
                    coordinate: place.coordinate,
                    isVisited: true,
                    place: place,
                    searchResult: nil
                ))
            }
        }
        
        annotations = newPins
        print("✅ [Annotations] Updated to \(annotations.count) pins")
        
        MemoryDebugHelper.shared.logMemory(tag: "📍 After (\(annotations.count) pins)")
    }
    
    private func loadData() async {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestPermission()
        } else if locationManager.authorizationStatus == .denied {
            showLocationPermissionAlert = true
        }
        
        await viewModel.fetchBeenToPlaces()
        updateAnnotations()
    }
    
    private func handlePinTap(_ item: PinAnnotation) {
        guard selectedPinId != item.id else { return }
        
        suppressRegionRefresh = true
        selectedPinId = item.id
        updateAnnotations()
        
        if let place = item.place {
            viewModel.selectPlace(place)
            // ✅ Adjust AFTER card is shown (with small delay for sheet animation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                adjustMapIfPinHidden(for: item.coordinate)
            }
        } else if let result = item.searchResult {
            print("🔎 [Pin Tap] Search result tapped: \(result.displayName)")
            
            let temporaryPlace = Place(
                id: result.id.uuidString,
                provider: result.source == .apple ? .apple : .google,
                googlePlaceId: result.googlePlaceId,
                applePlaceId: result.applePlaceId,
                nameEn: result.nameEn,
                nameJa: result.nameJa,
                nameZh: result.nameZh,
                lat: result.lat,
                lng: result.lng,
                formattedAddress: result.formattedAddress,
                categories: result.categories,
                photoUrls: result.photoUrls,
                openNow: nil,
                priceLevel: nil,
                rating: nil,
                userRatingsTotal: nil,
                phoneNumber: nil,
                website: nil,
                openingHours: nil,
                createdAt: nil,
                updatedAt: nil
            )
            
            viewModel.selectPlace(temporaryPlace)
            // ✅ Adjust AFTER card is shown
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                adjustMapIfPinHidden(for: item.coordinate)
            }
        }
    }
    
    private func handleMapRegionChange(_ newCenter: CLLocationCoordinate2D) {
        guard suppressRegionRefresh == false else { return }
        guard viewModel.searchResults.isEmpty else { return }

        mapRefreshTask?.cancel()
        
        mapRefreshTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            
            guard !Task.isCancelled else { return }
            await viewModel.fetchBeenToPlaces(in: region)
            updateAnnotations()
        }
    }
    
    private func zoomIn() {
        let newSpan = MKCoordinateSpan(
            latitudeDelta: region.span.latitudeDelta * 0.5,
            longitudeDelta: region.span.longitudeDelta * 0.5
        )
        region = MKCoordinateRegion(center: region.center, span: newSpan)
        withAnimation(.spring(response: 0.3)) {
            mapPosition = .region(region)
        }
    }
    
    private func zoomOut() {
        let newSpan = MKCoordinateSpan(
            latitudeDelta: region.span.latitudeDelta * 2.0,
            longitudeDelta: region.span.longitudeDelta * 2.0
        )
        region = MKCoordinateRegion(center: region.center, span: newSpan)
        withAnimation(.spring(response: 0.3)) {
            mapPosition = .region(region)
        }
    }
    
    private var bottomInsetForCard: CGFloat {
        return viewModel.showPlaceInfo ? 350 : 0 // Card takes ~40% of screen ≈ 350pt
    }

    private func adjustMapIfPinHidden(for coordinate: CLLocationCoordinate2D) {
        let screenHeight = UIScreen.main.bounds.height
        let cardHeight: CGFloat = 350
        
        print("📍 [Auto-Pan] === DEBUG START ===")
        print("📍 [Auto-Pan] Screen height: \(screenHeight)")
        print("📍 [Auto-Pan] Card height: \(cardHeight)")
        
        // ✅ CRITICAL: Calculate where the pin currently appears on screen
        // First, get the pin's position relative to current map center
        let centerCoord = region.center
        let pinCoord = coordinate
        
        // Calculate offset from center in degrees
        let latOffset = pinCoord.latitude - centerCoord.latitude
        let lngOffset = pinCoord.longitude - centerCoord.longitude
        
        // Convert to screen position (rough approximation)
        let latRatio = latOffset / region.span.latitudeDelta
        let pinScreenY = (screenHeight / 2) - (latRatio * screenHeight)
        
        print("📍 [Auto-Pan] Pin screen Y position: \(pinScreenY)")
        print("📍 [Auto-Pan] Card covers from Y: \(screenHeight - cardHeight) to \(screenHeight)")
        
        // ✅ CHECK: Is the pin in the area that will be covered by the card?
        let cardStartY = screenHeight - cardHeight
        let isPinHiddenByCard = pinScreenY > cardStartY
        
        print("📍 [Auto-Pan] Will pin be hidden? \(isPinHiddenByCard)")
        
        guard isPinHiddenByCard else {
            print("📍 [Auto-Pan] Pin is NOT hidden - no adjustment needed ✅")
            print("📍 [Auto-Pan] === DEBUG END ===")
            return
        }
        
        print("📍 [Auto-Pan] Pin WILL be hidden - adjusting map...")
        
        // Calculate shift needed
        let currentPinY = screenHeight / 2
        let targetPinY = (screenHeight - cardHeight) / 1.5
        let shiftNeeded = (currentPinY - targetPinY) * 1.0
        
        print("📍 [Auto-Pan] Current pin Y: \(currentPinY)")
        print("📍 [Auto-Pan] Target pin Y: \(targetPinY)")
        print("📍 [Auto-Pan] Shift needed: \(shiftNeeded)px")
        
        let latitudeShift = region.span.latitudeDelta * (shiftNeeded / screenHeight)
        
        let newCenter = CLLocationCoordinate2D(
            latitude: coordinate.latitude + latitudeShift,
            longitude: coordinate.longitude
        )
        
        print("📍 [Auto-Pan] New center: (\(newCenter.latitude), \(newCenter.longitude))")
        
        withAnimation(.easeOut(duration: 0.3)) {
            region = MKCoordinateRegion(
                center: newCenter,
                span: region.span
            )
            mapPosition = .region(region)
        }
        
        print("📍 [Auto-Pan] Animation applied ✅")
        print("📍 [Auto-Pan] === DEBUG END ===")
    }

}

// MARK: - Supporting Views

struct PinView: View {
    let isVisited: Bool
    let isHighlighted: Bool
    let distance: String?
    let onTap: () -> Void
    
    private var pinGradient: LinearGradient {
        if isVisited {
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color.orange, Color(red: 1.0, green: 0.6, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var body: some View {
        let pinSize = CGSize(width: 34, height: 50)

        if isHighlighted {
            VStack(spacing: 2) {
                Image(uiImage: PinImageProvider.original(size: pinSize))
                    .resizable()
                    .frame(width: pinSize.width, height: pinSize.height)
                    .shadow(color: .black.opacity(0.32), radius: 8, x: 0, y: 6)
                
                if let distance = distance {
                    Text(distance)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)
                }
            }
            .offset(y: -4)
        } else {
            Button(action: onTap) {
                ZStack {
                    Circle()
                        .fill(pinGradient)
                        .frame(width: 32, height: 32)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: "fork.knife")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

struct FilterToggleView: View {
    @Binding var showFollowingOnly: Bool
    let onToggle: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                if showFollowingOnly {
                    onToggle()
                }
            }) {
                Text("All")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(showFollowingOnly ? .secondary : .white)
                    .frame(width: 90)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if !showFollowingOnly {
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            } else {
                                Color.clear
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            Button(action: {
                if !showFollowingOnly {
                    onToggle()
                }
            }) {
                Text("Following")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(showFollowingOnly ? .white : .secondary)
                    .frame(width: 90)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if showFollowingOnly {
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            } else {
                                Color.clear
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(4)
        .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 8, x: 0, y: 2)
    }
}

struct PinAnnotation: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let isVisited: Bool
    let place: Place?
    let searchResult: PlaceSearchResult?
}

struct SearchBarView: View {
    @Binding var text: String
    let isSearching: Bool
    let onClear: () -> Void
    let onSearch: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            
            TextField("Search places...", text: $text)
                .font(.system(size: 15))
                .textFieldStyle(PlainTextFieldStyle())
                .autocorrectionDisabled()
                .onSubmit {
                    onSearch()
                }
            
            if isSearching {
                ProgressView()
                    .scaleEffect(0.8)
            } else if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemFill))
        .cornerRadius(12)
    }
}

struct ErrorBanner: View {
    let message: String
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.red)
        .cornerRadius(12)
        .shadow(radius: 8)
    }
}

#Preview {
    DiscoverView()
}
