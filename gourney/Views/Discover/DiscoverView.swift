// Views/Discover/DiscoverView.swift
// ✅ WITH PIN CLUSTERING: Loose clustering logic, zoom-adaptive, performance optimized

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
    @State private var savedMapRegion: MKCoordinateRegion?
    @State private var showLocationPermissionAlert = false
    @State private var lastKnownLocation: CLLocationCoordinate2D?
    @State private var mapRefreshTask: Task<Void, Never>?
    @State private var selectedPinId: String?
    @State private var suppressRegionRefresh = false
    @State private var isResearching = false  // ✅ NEW: Prevent zoom during research
    @State private var annotations: [PinAnnotation] = []
    @State private var showListView = false
    @State private var showResearchButton = false
    
    // ✅ NEW: Clustering state
    @State private var clusterItems: [ClusterItem] = []
    @State private var lastClusteringRegion: MKCoordinateRegion?
    @State private var clusterDebounceTask: Task<Void, Never>?
    
    var body: some View {
        
        
        NavigationStack {
            
            ZStack(alignment: .top) {
                // ✅ Map or List View
                if showListView {
                    listView
                        .id("listView")
                } else {
                    mapView
                        .id("mapView")
                        .onMapCameraChange { context in
                            guard !isResearching else { return }  // ✅ Don't update during research
                            region = context.region
                            handleMapRegionChange(context.region.center)
                            
                            // ✅ NEW: Re-cluster when zoom changes significantly
                            updateClustersIfNeeded(for: context.region)
                        }
                }
                
                topSection
                
                // ✅ Research button (below search bar)
                if showResearchButton && !showListView {
                    researchButton
                }
                
                // ✅ List/Map Toggle Button (Top-Left)
                viewToggleButton
                
                // ✅ Map controls (only show in map view)
                if !showListView {
                    mapControls
                }
                
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
                    PlaceInfoCard(place: place, viewModel: viewModel)
                }
            }
            .onChange(of: viewModel.showPlaceInfo) { _, isShowing in
                if !isShowing {
                    selectedPinId = nil
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
                Text("Please enable location access to see nearby places")
            }
            .task {
                await loadData()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                print("⚠️ MEMORY WARNING - Force cleanup")
                clusterItems = []
                annotations = []
                URLCache.shared.removeAllCachedResponses()
            }
            .onDisappear {
                // ✅ FIX: Cleanup when view disappears
                cleanup()
            }
        }
    }
    
    // ✅ NEW: Memory warning handler
    private func handleMemoryWarning() {
        print("⚠️ [Memory] Warning received - cleaning up...")
        
        // Clear clusters
        clusterItems.removeAll(keepingCapacity: false)
        lastClusteringRegion = nil
        
        // Cancel tasks
        mapRefreshTask?.cancel()
        
        // Force cleanup
        MemoryDebugHelper.shared.logMemory(tag: "⚠️ Before Cleanup")
        
        // Give system time to reclaim
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MemoryDebugHelper.shared.logMemory(tag: "✅ After Cleanup")
        }
    }
    
    // ✅ NEW: View cleanup
    private func cleanup() {
        mapRefreshTask?.cancel()
        clusterItems.removeAll(keepingCapacity: false)
        annotations.removeAll(keepingCapacity: false)
        lastClusteringRegion = nil
    }
    
    // MARK: - Top Section
    private var topSection: some View {
        VStack(spacing: 0) {
            // ✅ Top bar with filter tabs only
            ZStack {
                Rectangle()
                    .fill(.bar)
                    .ignoresSafeArea(edges: .top)
                
                HStack(spacing: 40) {
                    // All Tab
                    Button(action: {
                        if viewModel.showFollowingOnly {
                            viewModel.showFollowingOnly = false
                            Task {
                                await viewModel.fetchBeenToPlaces(in: region)
                                updateAnnotations()
                            }
                        }
                    }) {
                        VStack(spacing: 4) {
                            Text("All")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(viewModel.showFollowingOnly ? .secondary : Color(red: 1.0, green: 0.4, blue: 0.4))
                            
                            Rectangle()
                                .fill(viewModel.showFollowingOnly ? Color.clear : Color(red: 1.0, green: 0.4, blue: 0.4))
                                .frame(height: 2)
                        }
                    }
                    .frame(width: 100)
                    
                    // Following Tab
                    Button(action: {
                        if !viewModel.showFollowingOnly {
                            viewModel.showFollowingOnly = true
                            Task {
                                await viewModel.fetchBeenToPlaces(in: region)
                                updateAnnotations()
                            }
                        }
                    }) {
                        VStack(spacing: 4) {
                            Text("Following")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(viewModel.showFollowingOnly ? Color(red: 1.0, green: 0.4, blue: 0.4) : .secondary)
                            
                            Rectangle()
                                .fill(viewModel.showFollowingOnly ? Color(red: 1.0, green: 0.4, blue: 0.4) : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .frame(width: 100)
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .frame(height: 45)
            
            // ✅ Search bar below (narrower, solid background, reduced height)
            SearchBarView(
                text: $searchText,
                isSearching: viewModel.isSearching,
                onClear: {
                    searchText = ""
                    viewModel.clearSearch()
                },
                onSearch: {
                    viewModel.triggerSearch(
                        query: searchText,
                        mapCenter: region.center
                    )
                }
            )
            .padding(.horizontal, 70)
            .padding(.top, 12)
            .padding(.bottom, 12)  // ✅ Increased bottom padding
            
            Spacer()
        }
    }
    
    // MARK: - Research Button
    
    private var researchButton: some View {
        VStack {
            Spacer()
                .frame(height: 110)
            
            Button(action: {
                // ✅ LOG: Zoom level BEFORE search
                print("🔍 [Search This Area] CLICKED")
                print("   BEFORE - Center: \(String(format: "%.6f", region.center.latitude)), \(String(format: "%.6f", region.center.longitude))")
                print("   BEFORE - Span: latΔ=\(String(format: "%.6f", region.span.latitudeDelta)), lngΔ=\(String(format: "%.6f", region.span.longitudeDelta))")
                print("   BEFORE - Zoom Level: \(String(format: "%.2f", log2(360.0 / region.span.longitudeDelta)))")
                
                showResearchButton = false
                isResearching = true  // ✅ Block map updates
                
                let savedRegion = region  // ✅ Save EXACT region state
                
                Task {
                    await viewModel.fetchBeenToPlaces(in: savedRegion)
                    
                    await MainActor.run {
                        // ✅ Force restore saved region (ignore any changes during fetch)
                        region = savedRegion
                        mapPosition = .region(savedRegion)
                        
                        print("   ✅ RESTORED - Center: \(String(format: "%.6f", savedRegion.center.latitude)), \(String(format: "%.6f", savedRegion.center.longitude))")
                        print("   ✅ RESTORED - Span: latΔ=\(String(format: "%.6f", savedRegion.span.latitudeDelta)), lngΔ=\(String(format: "%.6f", savedRegion.span.longitudeDelta))")
                        print("   ✅ RESTORED - Zoom Level: \(String(format: "%.2f", log2(360.0 / savedRegion.span.longitudeDelta)))")
                        
                        updateAnnotations()  // Update pins
                        
                        isResearching = false  // ✅ Unblock AFTER everything done
                        
                        print("   ✅ Search complete\n")
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text(getLocalizedResearchText())
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
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
        GeometryReader { geometry in
            VStack {
                Spacer()
                    .frame(height: geometry.size.height * 0.079)
                
                HStack {
                    Button(action: {
                        print("🔄 [Toggle] Switching view")
                        print("   Current view: \(showListView ? "List" : "Map")")
                        
                        if !showListView {
                            // ✅ SAVE map position before switching to list
                            savedMapRegion = region
                            print("   💾 Saved map region: \(region.center.latitude), \(region.center.longitude)")
                            print("   💾 Saved span: \(region.span.latitudeDelta), \(region.span.longitudeDelta)")
                        }
                        
                        showListView.toggle()  // ✅ No animation
                        showResearchButton = false  // ✅ Hide button when switching views

                        if !showListView {
                            // ✅ RESTORE map position when switching back to map
                            if let saved = savedMapRegion {
                                print("   📍 Restoring map region")
                                region = saved
                                mapPosition = .region(saved)
                            }
                        }
                        
                        print("   New view: \(showListView ? "List" : "Map")")
                    }) {
                        Image(systemName: showListView ? "map.fill" : "list.bullet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                            .frame(width: 44, height: 44)
                            .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                    }
                    .padding(.leading, 16)
                    
                    Spacer()
                }
                
                Spacer()
            }
        }
    }
    
    // MARK: - Map Controls
    
    private var mapControls: some View {
        VStack(spacing: 12) {
            Spacer()
                .frame(height: 50)  // ✅ Reduced from 150 (same as toggle button)
            
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
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                            .frame(width: 36, height: 36)
                            .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
                    }
                    
                    Button(action: zoomOut) {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
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
    
    // ✅ NEW: List View
    private var listView: some View {
        let allPlaces = convertToListItems()
        
        return ZStack {
            Color(colorScheme == .dark ? .systemBackground : .systemGroupedBackground)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 140)  // Space for top section
                
                PlacesListView(places: allPlaces) { item in
                    handleListItemTap(item)
                }
            }
        }
    }
    
    // ✅ UPDATED: Map View with Clustering
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

            // ✅ NEW: Render clusters and single pins
            ForEach(clusterItems) { item in
                switch item {
                case .single(let pin):
                    // Regular single pin
                    Annotation("", coordinate: pin.coordinate) {
                        PinView(
                            isVisited: pin.isVisited,
                            isHighlighted: pin.id == selectedPinId,
                            distance: locationManager.formattedDistance(from: pin.coordinate),
                            onTap: { handlePinTap(pin) }
                        )
                        .allowsHitTesting(pin.id != selectedPinId)
                    }
                    
                case .cluster(let cluster):
                    // Cluster pin with count
                    Annotation("", coordinate: cluster.coordinate) {
                        ClusterPinView(
                            count: cluster.count,
                            isVisited: cluster.isVisited,
                            onTap: { handleClusterTap(cluster) }
                        )
                    }
                }
            }
        }
        .mapStyle(.standard)
        .edgesIgnoringSafeArea(.top)
        .onTapGesture {
            if viewModel.showPlaceInfo {
                viewModel.showPlaceInfo = false
                selectedPinId = nil
            }
        }
    }
    
    // MARK: - Clustering Logic
    
    /// Update clusters when zoom level changes significantly
    private func updateClustersIfNeeded(for newRegion: MKCoordinateRegion) {
        // Check if we should re-cluster (zoom changed significantly)
        if let lastRegion = lastClusteringRegion {
            let spanChange = abs(newRegion.span.latitudeDelta - lastRegion.span.latitudeDelta)
            let threshold = lastRegion.span.latitudeDelta * 0.8  // ✅ Increased: Less frequent updates
            
            guard spanChange > threshold else { return }
        }
        
        // ✅ PERFORMANCE: Debounce clustering - wait for zoom to settle
        clusterDebounceTask?.cancel()
        clusterDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // ✅ 0.4s - let zoom animation finish
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                updateClusters(for: newRegion)
            }
        }
    }
    
    /// Perform clustering on current annotations
    private func updateClusters(for region: MKCoordinateRegion) {
        guard !annotations.isEmpty else {
            if !clusterItems.isEmpty {
                clusterItems.removeAll(keepingCapacity: false)
                lastClusteringRegion = nil
            }
            return
        }
        
        // Use clustering helper
        let clusters = MapClusteringHelper.clusterPins(annotations, in: region)

        // Update state smoothly
        clusterItems = clusters
        lastClusteringRegion = region
    }
    
    /// Handle cluster tap - zoom into cluster area
    private func handleClusterTap(_ cluster: ClusterAnnotation) {
        print("📍 [Cluster] Tapped cluster with \(cluster.count) pins")
        
        // Find all pins in this cluster
        let pinsInCluster = annotations.filter { cluster.pinIds.contains($0.id) }
        
        guard !pinsInCluster.isEmpty else { return }
        
        // Calculate bounding box
        var minLat = pinsInCluster[0].coordinate.latitude
        var maxLat = pinsInCluster[0].coordinate.latitude
        var minLng = pinsInCluster[0].coordinate.longitude
        var maxLng = pinsInCluster[0].coordinate.longitude
        
        for pin in pinsInCluster {
            minLat = min(minLat, pin.coordinate.latitude)
            maxLat = max(maxLat, pin.coordinate.latitude)
            minLng = min(minLng, pin.coordinate.longitude)
            maxLng = max(maxLng, pin.coordinate.longitude)
        }
        
        let latDiff = maxLat - minLat
        let lngDiff = maxLng - minLng
        
        // Zoom aggressively to separate pins immediately
        let minZoomSpan = 0.003  // ~300m view
        let shouldZoomClose = latDiff < 0.001 && lngDiff < 0.001
        
        let centerLat = (minLat + maxLat) / 2
        let centerLng = (minLng + maxLng) / 2
        
        // Use aggressive zoom for tight clusters
        let paddingMultiplier = shouldZoomClose ? 3.0 : 2.0
        let spanLat = max(latDiff * paddingMultiplier, minZoomSpan)
        let spanLng = max(lngDiff * paddingMultiplier, minZoomSpan)
        
        let newRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLng),
            span: MKCoordinateSpan(
                latitudeDelta: spanLat,
                longitudeDelta: spanLng
            )
        )
        
        print("   🔍 Zooming to span: lat=\(String(format: "%.5f", spanLat)), lng=\(String(format: "%.5f", spanLng))")
        
        // Animate zoom
        withAnimation(.easeInOut(duration: 0.4)) {
            region = newRegion
            mapPosition = .region(newRegion)
        }
        
        // Re-cluster once after zoom completes (NO RECURSION)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            updateClusters(for: newRegion)
        }
    }
    
    // MARK: - Search
    
    private func handleSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        hideKeyboard()
        
        let mapCenter = region.center
        viewModel.triggerSearch(query: searchText, mapCenter: mapCenter)
    }
    
    private func handleSearchClear() {
        searchText = ""
        hideKeyboard()
        viewModel.clearSearch()
        selectedPinId = nil
    }
    
    // MARK: - Pin Selection
    
    private func handlePinTap(_ item: PinAnnotation) {
        guard selectedPinId != item.id else { return }
        
        selectedPinId = item.id
        // ✅ FIX: Don't call updateClusters - it refreshes entire map!
        // The pin will highlight automatically via isHighlighted binding
        
        // Pan map if needed
        let screenHeight = UIScreen.main.bounds.height
        let cardHeight = screenHeight * 0.4
        let mapCenterY = screenHeight / 2
        let pinLatDiff = item.coordinate.latitude - region.center.latitude
        let screenPinY = mapCenterY - (pinLatDiff / region.span.latitudeDelta) * screenHeight
        
        if screenPinY > (screenHeight - cardHeight) {
            let offsetLat = region.span.latitudeDelta * 0.15
            let newCenter = CLLocationCoordinate2D(
                latitude: item.coordinate.latitude + offsetLat,
                longitude: item.coordinate.longitude
            )
            
            suppressRegionRefresh = true  // ✅ Prevent research button from showing
            withAnimation(.easeOut(duration: 0.3)) {
                let newRegion = MKCoordinateRegion(
                    center: newCenter,
                    span: region.span
                )
                region = newRegion
                mapPosition = .region(newRegion)
            }
            
            // Re-enable after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                suppressRegionRefresh = false
            }
        }
        
        if let place = item.place {
            viewModel.selectPlace(place)
        } else if let searchResult = item.searchResult {
            Task {
                await viewModel.selectSearchResult(searchResult)
            }
        }
    }
    
    private func handleListItemTap(_ item: PlaceListItem) {
        if let place = item.place {
            viewModel.selectPlace(place)
        } else if let searchResult = item.searchResult {
            Task {
                await viewModel.selectSearchResult(searchResult)
            }
        }
        
        withAnimation {
            showListView = false
            
            if let saved = savedMapRegion {
                region = saved
                mapPosition = .region(saved)
            }
        }
    }
    
    // MARK: - Map Updates
    
    private var isMapCenteredOnUser: Bool {
        guard let userLocation = locationManager.userLocation else { return false }
        let distance = region.center.distance(to: userLocation)
        return distance < 50
    }
    
    private func zoomIn() {
        withAnimation(.easeInOut(duration: 0.3)) {
            region.span.latitudeDelta *= 0.5
            region.span.longitudeDelta *= 0.5
            mapPosition = .region(region)
        }
    }
    
    private func zoomOut() {
        withAnimation(.easeInOut(duration: 0.3)) {
            region.span.latitudeDelta *= 2.0
            region.span.longitudeDelta *= 2.0
            mapPosition = .region(region)
        }
        
        // Add this:
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.cleanupAfterZoom()
        }
    }
    
    private func cleanupAfterZoom() {
        // Force cleanup after zoom operations
        if clusterItems.count > 50 {
            let temp = clusterItems
            clusterItems = []
            clusterItems = temp
        }
    }
    
    private func handleMapRegionChange(_ center: CLLocationCoordinate2D) {
        guard !suppressRegionRefresh else { return }
        
        if let last = lastKnownLocation {
            let distance = last.distance(to: center)
            if distance < 100 {
                return
            }
        }
        
        lastKnownLocation = center
        
        mapRefreshTask?.cancel()
        mapRefreshTask = nil  // Release old task

        mapRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            
            guard !Task.isCancelled else { return }
            
            showResearchButton = true
        }
    }
    
    private func convertToListItems() -> [PlaceListItem] {
        if !viewModel.searchResults.isEmpty {
            return viewModel.searchResults.map { PlaceListItem(from: $0) }
        } else {
            return viewModel.beenToPlaces.map { PlaceListItem(from: $0.place) }
        }
    }
    
    // ✅ UPDATED: Update annotations and trigger clustering
    private func updateAnnotations() {
        let hasSearch = !viewModel.searchResults.isEmpty || viewModel.hasActiveSearch
        let currentSearchCount = viewModel.searchResults.count
        let currentBeenToCount = viewModel.beenToPlaces.count
        
        if hasSearch && currentSearchCount == 0 && currentBeenToCount == 0 {
            annotations.removeAll(keepingCapacity: false)
            clusterItems = []
            return
        }
        
        if annotations.count == (hasSearch ?
            currentSearchCount : min(currentBeenToCount, 50)) {
            return
        }
        
        var newPins: [PinAnnotation] = []
        newPins.reserveCapacity(50)
        
        if hasSearch {
            if !viewModel.searchResults.isEmpty {
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
        
        // ✅ Trigger clustering after annotation update
        updateClusters(for: region)
    }
    
    private func loadData() async {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestPermission()
        } else if locationManager.authorizationStatus == .denied {
            showLocationPermissionAlert = true
        }
        
        // ✅ FIX: Pass current region to only fetch visible places
        await viewModel.fetchBeenToPlaces(in: region)
        updateAnnotations()
        showResearchButton = false
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Supporting Views (unchanged from original)

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
                colors: [Color(red: 1.0, green: 0.5, blue: 0.3), Color(red: 1.0, green: 0.4, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var body: some View {
        // ✅ RESTORED: Teardrop design for highlighted pins
        let pinSize = CGSize(width: 34, height: 50)
        
        if isHighlighted {
            VStack(spacing: 2) {
                // Teardrop pin
                Image(uiImage: isVisited ?
                      PinImageProvider.original(size: pinSize) :
                      PinImageProvider.nonVisited(size: pinSize))
                    .resizable()
                    .frame(width: pinSize.width, height: pinSize.height)
                    .shadow(color: .black.opacity(0.32), radius: 8, x: 0, y: 6)
                
                // Distance badge
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
            // Regular circle pin (non-selected)
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
    @State private var showFilterSheet = false
    
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
                
                Button(action: {
                    showFilterSheet = true
                }) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .sheet(isPresented: $showFilterSheet) {
            Text("Filter options coming soon")
                .presentationDetents([.medium])
        }
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
