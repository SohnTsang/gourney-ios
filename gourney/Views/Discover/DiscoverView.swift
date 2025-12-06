// Views/Discover/DiscoverView.swift
// ✅ FIXED: Initial load centers on user location properly
// ✅ FIXED: Memory management - proper cleanup on disappear
// ✅ FIXED: CPU optimization - debounced map updates, limited pins
// ✅ FIXED: Map region preserved on list/map toggle
// ✅ FIXED: Compiler type-check complexity - broken into smaller views

import SwiftUI
import MapKit

struct DiscoverView: View {
    @StateObject private var viewModel = DiscoverViewModel()
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var toastManager = ToastManager.shared
    @State private var searchText = ""
    @Environment(\.colorScheme) private var colorScheme
    
    // Map state
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var mapPosition: MapCameraPosition = .automatic
    
    // Track if we've centered on user location
    @State private var hasInitializedLocation = false
    
    // Store region before switching to list view
    @State private var savedRegionBeforeList: MKCoordinateRegion?
    
    // UI state
    @State private var showLocationPermissionAlert = false
    @State private var selectedPinId: String?
    @State private var showListView = false
    @State private var showResearchButton = false
    @State private var showFilterSheet = false
    
    // PERFORMANCE: Use shared PinAnnotation
    @State private var visiblePins: [PinAnnotation] = []
    
    // PERFORMANCE: Debounce tasks with proper cancellation
    @State private var mapUpdateTask: Task<Void, Never>?
    @State private var pinUpdateTask: Task<Void, Never>?
    @State private var locationWaitTask: Task<Void, Never>?
    
    // Constants
    private let maxVisiblePins = 30
    
    var body: some View {
        NavigationStack {
            mainContentView
        }
    }
    
    // MARK: - Main Content (Broken up to reduce complexity)
    
    private var mainContentView: some View {
        ZStack(alignment: .top) {
            mapOrListContent
            topSection
            controlsOverlay
            loadingOverlayIfNeeded
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $viewModel.showPlaceInfo) { sheetContent }
        .overlay { filterPopupOverlay }
        .animation(.easeOut(duration: 0.2), value: showFilterSheet)
        .modifier(DiscoverOnChangeModifier(
            viewModel: viewModel,
            toastManager: toastManager,
            locationManager: locationManager,
            selectedPinId: $selectedPinId,
            hasInitializedLocation: $hasInitializedLocation,
            region: $region,
            mapPosition: $mapPosition,
            updateVisiblePins: updateVisiblePins,
            scheduleVisiblePinUpdate: scheduleVisiblePinUpdate
        ))
        .onChange(of: showListView) { oldValue, newValue in
            if oldValue && !newValue {
                restoreMapRegion()
            }
        }
        .alert("Location Permission Required", isPresented: $showLocationPermissionAlert) {
            alertButtons
        } message: {
            Text("Please enable location access to see nearby places")
        }
        .task { await initialLoad() }
        .onAppear {
            // ✅ Re-entering view: search at current region
            if hasInitializedLocation {
                Task {
                    await viewModel.fetchBeenToPlaces(in: region)
                    updateVisiblePins()
                }
            }
        }
        .onDisappear { cleanup() }
    }
    
    @ViewBuilder
    private var mapOrListContent: some View {
        if showListView {
            listView
        } else {
            optimizedMapView
        }
    }
    
    @ViewBuilder
    private var controlsOverlay: some View {
        researchButtonIfNeeded
        viewToggleButton
        mapControlsIfNeeded
    }
    
    @ViewBuilder
    private var researchButtonIfNeeded: some View {
        if showResearchButton && !showListView {
            researchButton
        }
    }
    
    @ViewBuilder
    private var mapControlsIfNeeded: some View {
        if !showListView {
            mapControls
        }
    }
    
    @ViewBuilder
    private var loadingOverlayIfNeeded: some View {
        if viewModel.isLoading {
            loadingOverlay
        }
    }
    
    @ViewBuilder
    private var sheetContent: some View {
        if let place = viewModel.selectedPlace {
            PlaceInfoCard(place: place, viewModel: viewModel)
        }
    }
    
    @ViewBuilder
    private var filterPopupOverlay: some View {
        if showFilterSheet {
            SearchFilterPopup(
                isPresented: $showFilterSheet,
                filters: $viewModel.filters,
                onApply: {
                    viewModel.applyFilters()
                    updateVisiblePins()
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .zIndex(100)
        }
    }
    
    @ViewBuilder
    private var alertButtons: some View {
        Button("Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        Button("Cancel", role: .cancel) {}
    }
    
    // MARK: - Initial Load
    
    private func initialLoad() async {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestPermission()
        }
        
        if let userLocation = locationManager.userLocation {
            centerOnUserLocation(userLocation)
        } else {
            locationWaitTask = Task {
                for _ in 0..<30 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if Task.isCancelled { return }
                    
                    if let location = locationManager.userLocation {
                        await MainActor.run {
                            centerOnUserLocation(location)
                        }
                        return
                    }
                }
                
                await MainActor.run {
                    if !hasInitializedLocation {
                        hasInitializedLocation = true
                        mapPosition = .region(region)
                        Task {
                            await viewModel.fetchBeenToPlaces(in: region)
                            updateVisiblePins()
                        }
                    }
                }
            }
        }
    }
    
    private func centerOnUserLocation(_ location: CLLocationCoordinate2D) {
        guard !hasInitializedLocation else { return }
        
        hasInitializedLocation = true
        
        region = MKCoordinateRegion(
            center: location,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        mapPosition = .region(region)
        
        print("📍 [Discover] Centered on user: (\(String(format: "%.4f", location.latitude)), \(String(format: "%.4f", location.longitude)))")
        
        Task {
            await viewModel.fetchBeenToPlaces(in: region)
            updateVisiblePins()
        }
    }
    
    // MARK: - Optimized Map View
    
    private var optimizedMapView: some View {
        Map(position: $mapPosition) {
            userLocationAnnotation
            pinAnnotations
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            handleMapCameraChange(context.region)
        }
        .ignoresSafeArea(edges: .top)
        .onTapGesture { dismissSelection() }
    }
    
    @MapContentBuilder
    private var userLocationAnnotation: some MapContent {
        if let userLocation = locationManager.userLocation {
            Annotation("", coordinate: userLocation) {
                UserLocationDot()
            }
            .annotationTitles(.hidden)
        }
    }
    
    @MapContentBuilder
    private var pinAnnotations: some MapContent {
        ForEach(visiblePins) { pin in
            Annotation("", coordinate: pin.coordinate) {
                SimplePinView(
                    isVisited: pin.isVisited,
                    isSelected: pin.id == selectedPinId,
                    onTap: { handlePinTap(pin) }
                )
            }
            .annotationTitles(.hidden)
        }
    }
    
    private func panToRegion(_ newRegion: MKCoordinateRegion) {
        print("🗺️ [Pan] Moving map to show results")
        
        withAnimation(.easeInOut(duration: 0.5)) {
            region = newRegion
            mapPosition = .region(newRegion)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            viewModel.shouldPanToResults = false
            viewModel.suggestedRegion = nil
            updateVisiblePins()
        }
    }
    
    private func restoreMapRegion() {
        guard let savedRegion = savedRegionBeforeList else { return }
        
        print("🗺️ [Restore] Restoring map region after list view")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            region = savedRegion
            mapPosition = .region(savedRegion)
            savedRegionBeforeList = nil
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                updateVisiblePins()
            }
        }
    }
    
    // MARK: - Simple Pin View
    
    private struct SimplePinView: View {
        let isVisited: Bool
        let isSelected: Bool
        let onTap: () -> Void
        
        var body: some View {
            Button(action: onTap) {
                Circle()
                    .fill(isVisited ? Color(red: 1.0, green: 0.4, blue: 0.4) : Color.gray)
                    .frame(width: isSelected ? 36 : 28, height: isSelected ? 36 : 28)
                    .overlay(
                        Image(systemName: "fork.knife")
                            .font(.system(size: isSelected ? 14 : 11, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .shadow(color: .black.opacity(0.3), radius: isSelected ? 6 : 3, y: 2)
            }
            .buttonStyle(.plain)
            .animation(.easeOut(duration: 0.15), value: isSelected)
        }
    }
    
    // MARK: - User Location Dot
    
    private struct UserLocationDot: View {
        var body: some View {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 40, height: 40)
                Circle()
                    .fill(Color.blue)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }
        }
    }
    
    // MARK: - Top Section
    
    private var topSection: some View {
        VStack(spacing: 0) {
            tabBarSection
            searchBarSection
        }
    }
    
    private var tabBarSection: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea(edges: .top)
            
            // ✅ Tabs aligned to bottom so underline touches bar bottom
            HStack(spacing: 40) {
                FilterTab(title: "All", isSelected: !viewModel.showFollowingOnly) {
                    if viewModel.showFollowingOnly {
                        viewModel.showFollowingOnly = false
                        Task { await refreshPlaces() }
                    }
                }
                
                FilterTab(title: "Following", isSelected: viewModel.showFollowingOnly) {
                    if !viewModel.showFollowingOnly {
                        viewModel.showFollowingOnly = true
                        Task { await refreshPlaces() }
                    }
                }
            }
            .padding(.bottom, 0)  // ✅ Underline at very bottom
        }
        .frame(height: 44)
    }
    
    private var searchBarSection: some View {
        SearchBarWithFilter(
            text: $searchText,
            isSearching: viewModel.isSearching,
            isFilterActive: viewModel.filters.isActive,
            onClear: handleSearchClear,
            onSearch: handleSearch,
            onFilter: { showFilterSheet = true }
        )
        .padding(.horizontal, 70)
        .padding(.top, 14)  // ✅ More space after tab underline
        .padding(.bottom, 12)
    }
    
    // MARK: - Filter Tab
    
    private struct FilterTab: View {
        let title: String
        let isSelected: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? Color(red: 1.0, green: 0.4, blue: 0.4) : .secondary)
                    
                    // ✅ Underline at bottom
                    Rectangle()
                        .fill(isSelected ? Color(red: 1.0, green: 0.4, blue: 0.4) : Color.clear)
                        .frame(height: 2)
                }
            }
            .frame(width: 100)
        }
    }
    
    // MARK: - Research Button
    
    private var researchButton: some View {
        VStack {
            Spacer().frame(height: 110)
            
            Button(action: handleResearchArea) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                    Text(getLocalizedResearchText())
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(red: 1.0, green: 0.4, blue: 0.4))
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
            
            Spacer()
        }
    }
    
    private func getLocalizedResearchText() -> String {
        let locale = Locale.current.identifier
        if locale.hasPrefix("ja") {
            return "このエリアを検索"
        } else if locale.hasPrefix("zh") {
            return "搜尋此區域"
        } else {
            return "Search this area"
        }
    }
    
    // MARK: - View Toggle Button
    
    private var viewToggleButton: some View {
        VStack {
            Spacer().frame(height: 62)
            
            HStack {
                Button(action: toggleView) {
                    Image(systemName: showListView ? "map.fill" : "list.bullet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                        .frame(width: 40, height: 40)
                        .background(colorScheme == .dark ? Color(.systemGray6) : .white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                }
                .padding(.leading, 16)
                
                Spacer()
            }
            
            Spacer()
        }
    }
    
    // MARK: - Map Controls
    
    private var mapControls: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 50)
            
            HStack {
                Spacer()
                
                VStack(spacing: 12) {
                    MapControlButton(icon: "location.fill", action: recenterToUser)
                    MapControlButton(icon: "plus", action: zoomIn)
                    MapControlButton(icon: "minus", action: zoomOut)
                }
                .padding(.trailing, 16)
            }
            
            Spacer()
        }
    }
    
    private struct MapControlButton: View {
        let icon: String
        let action: () -> Void
        @Environment(\.colorScheme) private var colorScheme
        
        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    .frame(width: 36, height: 36)
                    .background(colorScheme == .dark ? Color(.systemGray6) : .white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            }
        }
    }
    
    // MARK: - List View
    
    private var listView: some View {
        ZStack {
            Color(colorScheme == .dark ? .systemBackground : .systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer().frame(height: 110)
                
                PlacesListView(places: convertToListItems()) { item in
                    handleListItemTap(item)
                }
            }
        }
    }
    
    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
        }
    }
    
    // MARK: - Map Camera Change
    
    private func handleMapCameraChange(_ newRegion: MKCoordinateRegion) {
        region = newRegion
        
        mapUpdateTask?.cancel()
        
        mapUpdateTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                showResearchButton = true
                scheduleVisiblePinUpdate()
            }
        }
    }
    
    private func scheduleVisiblePinUpdate() {
        pinUpdateTask?.cancel()
        
        pinUpdateTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                updateVisiblePins()
            }
        }
    }
    
    private func updateVisiblePins() {
        var newPins: [PinAnnotation] = []
        newPins.reserveCapacity(maxVisiblePins)
        
        let hasSearch = !viewModel.filteredResults.isEmpty
        
        if hasSearch {
            for result in viewModel.filteredResults.prefix(maxVisiblePins) {
                newPins.append(PinAnnotation(
                    id: result.id.uuidString,
                    coordinate: CLLocationCoordinate2D(latitude: result.lat, longitude: result.lng),
                    isVisited: result.existsInDb,
                    place: nil,
                    searchResult: result
                ))
            }
        } else {
            for placeWithVisits in viewModel.beenToPlaces {
                let place = placeWithVisits.place
                guard isInViewport(lat: place.lat, lng: place.lng) else { continue }
                
                newPins.append(PinAnnotation(
                    id: place.id,
                    coordinate: CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng),
                    isVisited: true,
                    place: place,
                    searchResult: nil
                ))
                
                if newPins.count >= maxVisiblePins { break }
            }
        }
        
        if newPins.map({ $0.id }) != visiblePins.map({ $0.id }) {
            visiblePins = newPins
        }
    }
    
    private func isInViewport(lat: Double, lng: Double) -> Bool {
        let latMin = region.center.latitude - region.span.latitudeDelta
        let latMax = region.center.latitude + region.span.latitudeDelta
        let lngMin = region.center.longitude - region.span.longitudeDelta
        let lngMax = region.center.longitude + region.span.longitudeDelta
        return lat >= latMin && lat <= latMax && lng >= lngMin && lng <= lngMax
    }
    
    // MARK: - Actions
    
    private func handlePinTap(_ pin: PinAnnotation) {
        guard selectedPinId != pin.id else { return }
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        selectedPinId = pin.id
        
        if let searchResult = pin.searchResult {
            Task { await viewModel.selectSearchResult(searchResult) }
        } else if let place = pin.place {
            viewModel.selectPlace(place)
        }
    }
    
    private func handleListItemTap(_ item: PlaceListItem) {
        if let place = item.place {
            viewModel.selectPlace(place)
        } else if let searchResult = item.searchResult {
            Task { await viewModel.selectSearchResult(searchResult) }
        }
    }
    
    private func handleSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        hideKeyboard()
        viewModel.triggerSearch(query: query, mapCenter: region.center, mapSpan: region.span)
    }
    
    private func handleSearchClear() {
        searchText = ""
        hideKeyboard()
        viewModel.clearSearch()
        selectedPinId = nil
        
        Task {
            await viewModel.fetchBeenToPlaces(in: region)
            updateVisiblePins()
        }
    }
    
    private func handleResearchArea() {
        showResearchButton = false
        
        let activeQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !activeQuery.isEmpty {
            print("🔄 [Search This Area] Re-searching '\(activeQuery)'")
            viewModel.triggerSearchThisArea(mapCenter: region.center, mapSpan: region.span)
        } else if !viewModel.lastSearchQuery.isEmpty {
            print("🔄 [Search This Area] Re-searching last query '\(viewModel.lastSearchQuery)'")
            searchText = viewModel.lastSearchQuery
            viewModel.triggerSearchThisArea(mapCenter: region.center, mapSpan: region.span)
        } else {
            print("🔄 [Search This Area] Fetching places")
            Task {
                await viewModel.fetchBeenToPlaces(in: region)
                updateVisiblePins()
            }
        }
    }
    
    private func toggleView() {
        if !showListView {
            savedRegionBeforeList = region
            print("🗺️ [Save] Saved map region before list view")
        }
        
        showListView.toggle()
        showResearchButton = false
    }
    
    private func dismissSelection() {
        if viewModel.showPlaceInfo {
            viewModel.showPlaceInfo = false
            selectedPinId = nil
        }
    }
    
    private func recenterToUser() {
        guard let userLocation = locationManager.userLocation else {
            if locationManager.authorizationStatus == .denied {
                showLocationPermissionAlert = true
            }
            return
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            region = MKCoordinateRegion(
                center: userLocation,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
            mapPosition = .region(region)
        }
    }
    
    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            region.span.latitudeDelta *= 0.5
            region.span.longitudeDelta *= 0.5
            mapPosition = .region(region)
        }
    }
    
    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            region.span.latitudeDelta = min(region.span.latitudeDelta * 2, 10)
            region.span.longitudeDelta = min(region.span.longitudeDelta * 2, 10)
            mapPosition = .region(region)
        }
    }
    
    private func refreshPlaces() async {
        await viewModel.fetchBeenToPlaces(in: region)
        updateVisiblePins()
    }
    
    private func convertToListItems() -> [PlaceListItem] {
        if !viewModel.filteredResults.isEmpty {
            return viewModel.filteredResults.prefix(50).map { PlaceListItem(from: $0) }
        } else {
            return viewModel.beenToPlaces.prefix(50).map { PlaceListItem(from: $0.place) }
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        print("🧹 [Discover] Cleaning up...")
        
        mapUpdateTask?.cancel()
        mapUpdateTask = nil
        
        pinUpdateTask?.cancel()
        pinUpdateTask = nil
        
        locationWaitTask?.cancel()
        locationWaitTask = nil
        
        visiblePins.removeAll(keepingCapacity: false)
        viewModel.forceCleanup()
        
        print("🧹 [Discover] Cleanup complete")
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - onChange Handlers Modifier

private struct DiscoverOnChangeModifier: ViewModifier {
    @ObservedObject var viewModel: DiscoverViewModel
    @ObservedObject var toastManager: ToastManager
    @ObservedObject var locationManager: LocationManager
    @Binding var selectedPinId: String?
    @Binding var hasInitializedLocation: Bool
    @Binding var region: MKCoordinateRegion
    @Binding var mapPosition: MapCameraPosition
    let updateVisiblePins: () -> Void
    let scheduleVisiblePinUpdate: () -> Void
    
    func body(content: Content) -> some View {
        content
            .modifier(PlaceInfoChangeModifier(viewModel: viewModel, selectedPinId: $selectedPinId))
            .modifier(SearchResultsChangeModifier(viewModel: viewModel, scheduleUpdate: scheduleVisiblePinUpdate))
            .modifier(PanChangeModifier(viewModel: viewModel, region: $region, mapPosition: $mapPosition, updateVisiblePins: updateVisiblePins))
            .modifier(ToastChangeModifier(viewModel: viewModel, toastManager: toastManager))
            .modifier(LocationChangeModifier(
                locationManager: locationManager,
                viewModel: viewModel,
                hasInitializedLocation: $hasInitializedLocation,
                region: $region,
                mapPosition: $mapPosition,
                updateVisiblePins: updateVisiblePins
            ))
    }
}

// Split into individual modifiers to reduce type complexity
private struct PlaceInfoChangeModifier: ViewModifier {
    @ObservedObject var viewModel: DiscoverViewModel
    @Binding var selectedPinId: String?
    
    func body(content: Content) -> some View {
        content.onChange(of: viewModel.showPlaceInfo) { _, isShowing in
            if !isShowing { selectedPinId = nil }
        }
    }
}

private struct SearchResultsChangeModifier: ViewModifier {
    @ObservedObject var viewModel: DiscoverViewModel
    let scheduleUpdate: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.searchResults.count) { _, _ in scheduleUpdate() }
            .onChange(of: viewModel.filteredResults.count) { _, _ in scheduleUpdate() }
            .onChange(of: viewModel.beenToPlaces.count) { _, _ in scheduleUpdate() }
    }
}

private struct PanChangeModifier: ViewModifier {
    @ObservedObject var viewModel: DiscoverViewModel
    @Binding var region: MKCoordinateRegion
    @Binding var mapPosition: MapCameraPosition
    let updateVisiblePins: () -> Void
    
    func body(content: Content) -> some View {
        content.onChange(of: viewModel.shouldPanToResults) { _, shouldPan in
            if shouldPan, let newRegion = viewModel.suggestedRegion {
                withAnimation(.easeInOut(duration: 0.5)) {
                    region = newRegion
                    mapPosition = .region(newRegion)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    viewModel.shouldPanToResults = false
                    viewModel.suggestedRegion = nil
                    updateVisiblePins()
                }
            }
        }
    }
}

private struct ToastChangeModifier: ViewModifier {
    @ObservedObject var viewModel: DiscoverViewModel
    @ObservedObject var toastManager: ToastManager
    
    func body(content: Content) -> some View {
        content.onChange(of: viewModel.toastMessage) { _, message in
            if let message = message {
                toastManager.showError(message)
                viewModel.toastMessage = nil
            }
        }
    }
}

private struct LocationChangeModifier: ViewModifier {
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var viewModel: DiscoverViewModel
    @Binding var hasInitializedLocation: Bool
    @Binding var region: MKCoordinateRegion
    @Binding var mapPosition: MapCameraPosition
    let updateVisiblePins: () -> Void
    
    // Use latitude as equatable proxy for location changes
    private var locationLatitude: Double? {
        locationManager.userLocation?.latitude
    }
    
    func body(content: Content) -> some View {
        content.onChange(of: locationLatitude) { _, newLat in
            guard !hasInitializedLocation,
                  let location = locationManager.userLocation else { return }
            
            hasInitializedLocation = true
            let newRegion = MKCoordinateRegion(
                center: location,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
            region = newRegion
            mapPosition = .region(newRegion)
            print("📍 [Discover] Centered via onChange")
            
            // ✅ Fetch places after centering
            Task {
                await viewModel.fetchBeenToPlaces(in: newRegion)
                await MainActor.run {
                    updateVisiblePins()
                }
            }
        }
    }
}

// MARK: - Search Bar with Filter Button

private struct SearchBarWithFilter: View {
    @Binding var text: String
    let isSearching: Bool
    let isFilterActive: Bool
    let onClear: () -> Void
    let onSearch: () -> Void
    let onFilter: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    private let coralColor = Color(red: 1.0, green: 0.4, blue: 0.4)
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            
            TextField("Search places...", text: $text)
                .font(.system(size: 15))
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .onSubmit(onSearch)
            
            trailingButtons
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color(.systemGray6) : .white)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
    
    @ViewBuilder
    private var trailingButtons: some View {
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
                    .foregroundColor(coralColor)
            }
            
            filterButton
        }
    }
    
    private var filterButton: some View {
        Button(action: onFilter) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 20))
                    .foregroundColor(coralColor)
                
                if isFilterActive {
                    Circle()
                        .fill(coralColor)
                        .frame(width: 8, height: 8)
                        .offset(x: 2, y: -2)
                }
            }
        }
    }
}

#Preview {
    DiscoverView()
}
