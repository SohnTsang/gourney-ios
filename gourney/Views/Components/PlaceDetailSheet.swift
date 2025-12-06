// Views/Components/PlaceDetailSheet.swift
// ✅ FIX 1: Address left-aligned (not centered)
// ✅ FIX 2: Bottom button gaps reduced (spacing: 8)
// ✅ FIX 3: SaveToListSheet integration with proper bottom sheet UX

import SwiftUI
import CoreLocation

// MARK: - Photo with Rating (for grid display)

struct VisitPhotoData: Identifiable {
    let id: String
    let visitId: String
    let photoUrl: String
    let rating: Int?
    let visit: EdgeFunctionVisit
    
    init(photoUrl: String, rating: Int?, index: Int, visitId: String, visit: EdgeFunctionVisit) {
        self.id = "\(photoUrl)-\(index)"
        self.visitId = visitId
        self.photoUrl = photoUrl
        self.rating = rating
        self.visit = visit
    }
}

struct PlaceDetailSheet: View {
    let placeId: String
    let displayName: String
    let lat: Double
    let lng: Double
    let formattedAddress: String?
    let phoneNumber: String?
    let website: String?
    let photoUrls: [String]?
    let googlePlaceId: String?
    
    let primaryButtonTitle: String
    let primaryButtonAction: () -> Void
    let onDismiss: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var locationManager = LocationManager.shared
    
    @State private var isLoading = true
    @State private var visits: [EdgeFunctionVisit] = []
    @State private var visitCount: Int = 0
    @State private var avgRating: Double? = nil
    @State private var placeAddress: String? = nil
    @State private var placePhone: String? = nil
    @State private var placeWebsite: String? = nil
    @State private var placeName: String? = nil
    @State private var cachedVisitPhotos: [VisitPhotoData] = []
    @State private var openNow: Bool? = nil
    @State private var openingHours: [String]? = nil
    @State private var showAllVisits = false
    
    // Navigation state for photo tap -> FeedDetailView
    @State private var selectedPhotoFeedItem: FeedItem?
    
    // States for bottom action buttons
    @State private var showSaveToList = false
    @State private var showReportSheet = false
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 36, height: 5)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(placeName ?? displayName)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .padding(.bottom, 8)
                                
                                RatingWithDistanceView(
                                    rating: avgRating,
                                    distance: calculateDistance()
                                )
                                .padding(.bottom, 8)
                                
                                // Visit count row with "View All" next to it
                                HStack(alignment: .center) {
                                    VisitStatusView(visitCount: visitCount, isLoading: false)
                                    
                                    if visitCount > 0 {
                                        Text("·")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.secondary)
                                        
                                        Button {
                                            showAllVisits = true
                                        } label: {
                                            Text("View All")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if let isOpen = openNow {
                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(isOpen ? Color.green : Color.red)
                                                .frame(width: 7, height: 7)
                                            Text(isOpen ? "Open" : "Closed")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(isOpen ? .green : .red)
                                        }
                                    }
                                }
                                .padding(.bottom, 20)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            
                            // Photo grid - iPhone ratio with rating overlay - NOW TAPPABLE
                            if !cachedVisitPhotos.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(cachedVisitPhotos) { photoData in
                                            VisitPhotoGridItem(photoData: photoData)
                                                .onTapGesture {
                                                    handlePhotoTap(photoData: photoData)
                                                }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                                .frame(height: 213)
                                .padding(.bottom, 20)
                            } else {
                                // Empty state
                                VStack(spacing: 12) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary.opacity(0.3))
                                    Text("Add the first photo here!")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 213)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                            }
                            
                            // ✅ FIX 1: Address section - LEFT ALIGNED
                            if let address = placeAddress ?? formattedAddress, !address.isEmpty {
                                Divider()
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 16)
                                
                                // Address button with left alignment
                                AddressButton(
                                    address: address,
                                    placeName: placeName ?? displayName
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)  // ✅ Left align
                                .padding(.horizontal, 20)
                            }
                            
                            if let hours = openingHours, !hours.isEmpty {
                                Divider()
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "clock")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                                        Text("Hours")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundColor(.primary)
                                    }
                                    
                                    VStack(spacing: 10) {
                                        ForEach(hours, id: \.self) { hourLine in
                                            HStack(alignment: .top, spacing: 0) {
                                                Text(extractDay(from: hourLine))
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(.primary)
                                                    .frame(width: 90, alignment: .leading)
                                                
                                                Text(extractTime(from: hourLine))
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.secondary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                            }
                            
                            // Phone and website buttons
                            VStack(alignment: .leading, spacing: 0) {
                                if let phone = placePhone ?? phoneNumber, !phone.isEmpty {
                                    Divider()
                                        .padding(.horizontal, 20)
                                        .padding(.bottom, 16)
                                    
                                    PhoneButton(phone: phone)
                                        .frame(maxWidth: .infinity, alignment: .leading)  // ✅ Left align
                                        .padding(.horizontal, 20)
                                }
                                
                                if let web = placeWebsite ?? website, !web.isEmpty {
                                    Divider()
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                    
                                    WebsiteButton(website: web)
                                        .frame(maxWidth: .infinity, alignment: .leading)  // ✅ Left align
                                        .padding(.horizontal, 20)
                                }
                            }
                            
                            Spacer().frame(height: 100)
                        }
                    }
                    
                    // ✅ FIX 2: Bottom action bar - REDUCED SPACING (8 instead of 12)
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {  // ← Changed from 12 to 8
                            // Add Visit button (widest)
                            Button {
                                primaryButtonAction()
                            } label: {
                                Text(primaryButtonTitle)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        LinearGradient(
                                            colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(12)
                            }
                            
                            // Save to List button (icon only)
                            Button {
                                showSaveToList = true
                            } label: {
                                Image(systemName: "bookmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 48, height: 48)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                            }
                            
                            // Share button (icon only)
                            Button {
                                sharePlace()
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 48, height: 48)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                            }
                            
                            // Report button (icon only)
                            Button {
                                showReportSheet = true
                            } label: {
                                Image(systemName: "flag")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .frame(width: 48, height: 48)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                        .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
                    }
                }
            }
            .opacity(isLoading ? 0 : 1)
            
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading place info...")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
                .transition(.opacity)
            }
        }
        .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
        .presentationDetents([.fraction(0.4), .large])
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
        .id(placeId)
        .onChange(of: placeId) { _ in
            isLoading = true
            cachedVisitPhotos = []
            visits = []
            avgRating = nil
            placeAddress = nil
            placePhone = nil
            placeWebsite = nil
            placeName = nil
            openNow = nil
            openingHours = nil
        }
        .task(id: placeId) {
            await loadAllData()
        }
        .onDisappear {
            cachedVisitPhotos = []
            visits = []
            avgRating = nil
            placeAddress = nil
            placePhone = nil
            placeWebsite = nil
            placeName = nil
            openNow = nil
            openingHours = nil
            MemoryDebugHelper.shared.logMemory(tag: "💾 [PlaceDetail] Memory cleared")
        }
        .fullScreenCover(isPresented: $showAllVisits) {
            PlaceVisitsListView(
                placeId: placeId,
                placeName: placeName ?? displayName
            )
        }
        // Navigation to FeedDetailView when photo tapped
        .fullScreenCover(item: $selectedPhotoFeedItem) { feedItem in
            NavigationStack {
                FeedDetailView(feedItem: feedItem, feedViewModel: nil)
            }
        }
        // ✅ FIX 3: Save to List sheet - bottom sheet presentation
        .sheet(isPresented: $showSaveToList) {
            SaveToListSheet(placeId: placeId, placeName: placeName ?? displayName)
        }
        // Report sheet (placeholder)
        .sheet(isPresented: $showReportSheet) {
            ReportPlaceSheet(placeId: placeId, placeName: placeName ?? displayName)
        }
    }
    
    // MARK: - Handle Photo Tap -> FeedDetailView
    
    private func handlePhotoTap(photoData: VisitPhotoData) {
        let feedItem = convertToFeedItem(visit: photoData.visit)
        selectedPhotoFeedItem = feedItem
    }
    
    private func convertToFeedItem(visit: EdgeFunctionVisit) -> FeedItem {
        FeedItem(
            id: visit.id,
            rating: visit.rating,
            comment: visit.comment,
            photoUrls: visit.photoUrls.isEmpty ? nil : visit.photoUrls,
            visibility: "public",
            createdAt: visit.visitedAt,
            visitedAt: visit.visitedAt,
            likeCount: visit.likesCount ?? 0,
            commentCount: 0,
            isLiked: false,
            isFollowing: false,
            user: FeedUser(
                id: visit.userId,
                handle: visit.userHandle,
                displayName: visit.userDisplayName,
                avatarUrl: visit.userAvatarUrl
            ),
            place: FeedPlace(
                id: placeId,
                nameEn: placeName ?? displayName,
                nameJa: nil,
                nameZh: nil,
                city: nil,
                ward: nil,
                country: nil,
                categories: nil
            )
        )
    }
    
    // MARK: - Load All Data
    
    private func loadAllData() async {
        print("🔍 [PlaceDetail] Starting loadAllData")
        print("🔍 [PlaceDetail] placeId: \(placeId)")
        print("🔍 [PlaceDetail] displayName: \(displayName)")
        print("🔍 [PlaceDetail] lat: \(lat), lng: \(lng)")
        print("🔍 [PlaceDetail] googlePlaceId: \(googlePlaceId ?? "nil")")
        
        let visitsData = await fetchVisits()
        print("🔍 [PlaceDetail] visitsData: \(visitsData != nil ? "loaded \(visitsData!.visitCount) visits" : "nil")")
        
        let placeData = try? await fetchPlaceData(placeId: placeId)
        print("🔍 [PlaceDetail] placeData from DB: \(placeData != nil ? "loaded" : "nil")")
        if let placeData = placeData {
            print("🔍 [PlaceDetail] DB name: \(placeData.name ?? "nil")")
            print("🔍 [PlaceDetail] DB address: \(placeData.address ?? "nil")")
            print("🔍 [PlaceDetail] DB avgRating: \(placeData.avgRating ?? 0)")
        }
        
        if let (fetchedVisits, count) = visitsData {
            visits = fetchedVisits
            visitCount = count
            cachedVisitPhotos = computeTopVisitPhotos(from: fetchedVisits)
            print("✅ [PlaceDetail] Set visits: \(count), photos: \(cachedVisitPhotos.count)")
        }
        
        let isStub = displayName == "Unknown Place" || displayName.isEmpty
        print("🔍 [PlaceDetail] isStub: \(isStub)")
        
        if isStub, let googleId = googlePlaceId {
            print("🔍 [PlaceDetail] Fetching from Google API...")
            do {
                let googleData = try await GooglePlaceDetailFetcher.shared.fetchDetails(googlePlaceId: googleId)
                
                placeName = googleData.name
                placeAddress = googleData.address
                placePhone = googleData.phone
                placeWebsite = googleData.website
                openNow = googleData.openingHours?.openNow
                openingHours = googleData.openingHours?.weekdayText
                
                if let dbRating = placeData?.avgRating {
                    avgRating = dbRating
                    print("✅ [PlaceDetail] Using DB visit rating: \(dbRating)")
                } else {
                    avgRating = googleData.rating
                    print("✅ [PlaceDetail] Using Google rating: \(googleData.rating ?? 0.0)")
                }
            } catch {
                print("❌ [PlaceDetail] Google API failed: \(error)")
            }
        } else if let placeData = placeData {
            print("✅ [PlaceDetail] Using DB data (non-stub)")
            avgRating = placeData.avgRating
            placeAddress = placeData.address
            placePhone = placeData.phone
            placeWebsite = placeData.website
            openNow = placeData.openNow
            openingHours = placeData.openingHours
            
            if let name = placeData.name, !name.isEmpty {
                placeName = name
            }
            print("✅ [PlaceDetail] Set - name: \(placeName ?? "nil"), address: \(placeAddress ?? "nil"), rating: \(avgRating ?? 0)")
        } else {
            print("⚠️ [PlaceDetail] No data loaded - placeData is nil and not a stub")
        }
        
        isLoading = false
        print("✅ [PlaceDetail] Loading complete, isLoading = false")
        MemoryDebugHelper.shared.logMemory(tag: "✅ PlaceDetail Loaded")
    }
    
    private func fetchVisits() async -> (visits: [EdgeFunctionVisit], visitCount: Int)? {
        do {
            let url = "\(Config.supabaseURL)/functions/v1/places-get-visits/\(placeId)?limit=10&friends_only=false"
            guard let requestURL = URL(string: url) else { return nil }
            
            var request = URLRequest(url: requestURL)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("v1", forHTTPHeaderField: "X-API-Version")
            
            if let token = SupabaseClient.shared.getAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            let decoder = JSONDecoder()
            let result = try decoder.decode(PlaceVisitsResponse.self, from: data)
            
            return (result.visits, result.visitCount)
        } catch {
            return nil
        }
    }
    
    private func computeTopVisitPhotos(from visits: [EdgeFunctionVisit]) -> [VisitPhotoData] {
        var photoDataList: [VisitPhotoData] = []
        var index = 0
        
        let sortedVisits = visits
            .filter { !$0.photoUrls.isEmpty }
            .sorted { ($0.likesCount ?? 0) > ($1.likesCount ?? 0) }
        
        for visit in sortedVisits.prefix(10) {
            if let firstPhoto = visit.photoUrls.first {
                photoDataList.append(VisitPhotoData(
                    photoUrl: firstPhoto,
                    rating: visit.rating,
                    index: index,
                    visitId: visit.id,
                    visit: visit
                ))
                index += 1
            }
        }
        
        return photoDataList
    }
    
    private func calculateDistance() -> String? {
        guard let userLocation = locationManager.userLocation else { return nil }
        
        let placeLocation = CLLocation(latitude: lat, longitude: lng)
        let userCLLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let distance = userCLLocation.distance(from: placeLocation)
        
        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
    
    private func sharePlace() {
        guard let url = URL(string: website ?? placeWebsite ?? "https://gourney.app/place/\(placeId)") else { return }
        
        let activityVC = UIActivityViewController(
            activityItems: [
                "\(placeName ?? displayName)\n\(placeAddress ?? formattedAddress ?? "")",
                url
            ],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func extractDay(from hourLine: String) -> String {
        if let colonIndex = hourLine.firstIndex(of: ":") {
            return String(hourLine[..<colonIndex])
        }
        return hourLine
    }
    
    private func extractTime(from hourLine: String) -> String {
        if let colonIndex = hourLine.firstIndex(of: ":") {
            let afterColon = hourLine.index(after: colonIndex)
            return String(hourLine[afterColon...]).trimmingCharacters(in: .whitespaces)
        }
        return ""
    }
    
    private func fetchPlaceData(placeId: String) async throws -> (name: String?, address: String?, phone: String?, website: String?, avgRating: Double?, openNow: Bool?, openingHours: [String]?)? {
        let url = "\(Config.supabaseURL)/functions/v1/places-detail/\(placeId)"
        guard let requestURL = URL(string: url) else { return nil }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("v1", forHTTPHeaderField: "X-API-Version")
        
        if let token = SupabaseClient.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        
        struct PlaceDetailResponse: Codable {
            let place: PlaceObject
            
            struct PlaceObject: Codable {
                let nameEn: String?
                let address: String?
                let phone: String?
                let website: String?
                let avgRating: Double?
                let openNow: Bool?
                let openingHours: [String]?
                let attributes: PlaceAttributes?
                
                enum CodingKeys: String, CodingKey {
                    case nameEn = "name_en"
                    case address, phone, website
                    case avgRating = "avg_rating"
                    case openNow = "open_now"
                    case openingHours = "opening_hours"
                    case attributes
                }
            }
        }
        
        struct PlaceAttributes: Codable {
            let formattedAddress: String?
            let phone: String?
            let website: String?
            
            enum CodingKeys: String, CodingKey {
                case formattedAddress = "formatted_address"
                case phone, website
            }
        }
        
        let decoder = JSONDecoder()
        let placeResponse = try decoder.decode(PlaceDetailResponse.self, from: data)
        let placeDetail = placeResponse.place
        
        let finalName = placeDetail.nameEn
        let finalAddress = placeDetail.address ?? placeDetail.attributes?.formattedAddress
        let finalPhone = placeDetail.phone ?? placeDetail.attributes?.phone
        let finalWebsite = placeDetail.website ?? placeDetail.attributes?.website
        
        return (
            name: finalName,
            address: finalAddress,
            phone: finalPhone,
            website: finalWebsite,
            avgRating: placeDetail.avgRating,
            openNow: placeDetail.openNow,
            openingHours: placeDetail.openingHours
        )
    }
}

// MARK: - Visit Photo Grid Item (Square with Rating Overlay)

struct VisitPhotoGridItem: View {
    let photoData: VisitPhotoData
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: photoData.photoUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 213)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                case .failure(_):
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(width: 160, height: 213)
                case .empty:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(width: 160, height: 213)
                        .overlay {
                            ProgressView()
                        }
                @unknown default:
                    EmptyView()
                }
            }
            
            if let rating = photoData.rating, rating > 0 {
                HStack(spacing: 2) {
                    ForEach(0..<5) { index in
                        Image(systemName: index < rating ? "star.fill" : "star")
                            .font(.system(size: 8))
                            .foregroundColor(index < rating ? .yellow : .white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.5))
                .cornerRadius(4)
                .padding(8)
            }
        }
        .frame(width: 160, height: 213)
        .contentShape(Rectangle())
    }
}

// MARK: - Report Place Sheet (Placeholder)

struct ReportPlaceSheet: View {
    let placeId: String
    let placeName: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "flag.circle")
                    .font(.system(size: 60))
                    .foregroundColor(GourneyColors.coral.opacity(0.5))
                
                Text("Report \(placeName)")
                    .font(.system(size: 18, weight: .semibold))
                    .multilineTextAlignment(.center)
                
                Text("Report functionality will be added soon.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Spacer()
            }
            .padding(.top, 60)
            .padding(.horizontal, 20)
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(GourneyColors.coral)
                }
            }
        }
    }
}

// MARK: - Place Visits List View (for "View All")

struct PlaceVisitsListView: View {
    let placeId: String
    let placeName: String
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var visits: [VisitRowData] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var error: String?
    @State private var hasMore = true
    @State private var nextCursor: String?
    
    @State private var selectedProfileUserId: String?
    @State private var selectedVisitForDetail: FeedItem?
    
    private let pageSize = 20
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                backgroundColor.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Color.clear.frame(height: 52)
                    
                    if isLoading && visits.isEmpty {
                        Spacer()
                        LoadingSpinner()
                        Spacer()
                    } else if let errorMessage = error, visits.isEmpty {
                        Spacer()
                        errorView(errorMessage)
                        Spacer()
                    } else if visits.isEmpty {
                        Spacer()
                        emptyStateView
                        Spacer()
                    } else {
                        visitsScrollView
                    }
                }
                
                topBar
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $selectedProfileUserId) { userId in
                ProfileView(userId: userId)
            }
            .navigationDestination(item: $selectedVisitForDetail) { feedItem in
                FeedDetailView(feedItem: feedItem, feedViewModel: nil)
            }
        }
        .task {
            await loadVisits(refresh: true)
        }
    }
    
    private var topBar: some View {
        DetailTopBar(
            title: placeName,
            onBack: { dismiss() }
        )
        .background(backgroundColor)
    }
    
    private var visitsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach($visits) { $visit in
                    let userId = visit.visitorId
                    let visitCopy = visit
                    
                    VStack(spacing: 0) {
                        VisitRowView(
                            visit: $visit,
                            onAvatarTap: {
                                handleAvatarTap(userId: userId)
                            },
                            onRowTap: {
                                handleRowTap(visit: visitCopy)
                            }
                        )
                        .onAppear {
                            loadMoreIfNeeded(currentVisit: visit)
                        }
                        
                        Divider()
                    }
                }
                
                if isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView().tint(GourneyColors.coral)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            }
            .padding(.bottom, 20)
        }
        .refreshable {
            await loadVisits(refresh: true)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 48))
                .foregroundColor(GourneyColors.coral.opacity(0.5))
            
            Text("No visits yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("Be the first to share your experience!")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 48))
                .foregroundColor(GourneyColors.coral.opacity(0.5))
            
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            
            Button {
                Task { await loadVisits(refresh: true) }
            } label: {
                Text("Try Again")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(GourneyColors.coral)
                    .cornerRadius(8)
            }
        }
    }
    
    private func handleAvatarTap(userId: String) {
        selectedProfileUserId = userId
    }
    
    private func handleRowTap(visit: VisitRowData) {
        selectedVisitForDetail = visit.toFeedItem()
    }
    
    private func loadMoreIfNeeded(currentVisit: VisitRowData) {
        guard let index = visits.firstIndex(where: { $0.id == currentVisit.id }) else { return }
        
        if index >= visits.count - 3 && hasMore && !isLoadingMore {
            Task {
                await loadVisits(refresh: false)
            }
        }
    }
    
    private func loadVisits(refresh: Bool) async {
        if refresh {
            isLoading = visits.isEmpty
            nextCursor = nil
            hasMore = true
        } else {
            guard hasMore && !isLoadingMore else { return }
            isLoadingMore = true
        }
        
        error = nil
        
        do {
            var url = "\(Config.supabaseURL)/functions/v1/places-get-visits/\(placeId)?limit=\(pageSize)&friends_only=false"
            if let cursor = nextCursor, !refresh {
                if let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    url += "&cursor=\(encoded)"
                }
            }
            
            guard let requestURL = URL(string: url) else {
                await MainActor.run {
                    error = "Invalid URL"
                    isLoading = false
                    isLoadingMore = false
                }
                return
            }
            
            var request = URLRequest(url: requestURL)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("v1", forHTTPHeaderField: "X-API-Version")
            
            if let token = SupabaseClient.shared.getAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    error = "Invalid response"
                    isLoading = false
                    isLoadingMore = false
                }
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                await MainActor.run {
                    error = "Server error (\(httpResponse.statusCode))"
                    isLoading = false
                    isLoadingMore = false
                }
                return
            }
            
            let decoder = JSONDecoder()
            let result = try decoder.decode(PlaceVisitsResponse.self, from: data)
            
            await MainActor.run {
                let newVisits = result.visits.map { visit in
                    VisitRowData(from: visit, placeId: placeId, placeName: placeName)
                }
                
                if refresh {
                    visits = newVisits
                } else {
                    let existingIds = Set(visits.map { $0.id })
                    let uniqueNewVisits = newVisits.filter { !existingIds.contains($0.id) }
                    visits.append(contentsOf: uniqueNewVisits)
                }
                
                nextCursor = result.nextCursor
                hasMore = result.nextCursor != nil
                isLoading = false
                isLoadingMore = false
                
                print("📸 [PlaceVisits] Loaded \(newVisits.count) visits, total: \(visits.count), hasMore: \(hasMore)")
            }
            
        } catch {
            print("❌ [PlaceVisitsList] Error: \(error)")
            await MainActor.run {
                self.error = "Failed to load visits"
                isLoading = false
                isLoadingMore = false
            }
        }
    }
}
