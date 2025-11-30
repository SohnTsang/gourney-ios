// Views/Components/PlaceDetailSheet.swift
// ✅ FIXED: Always prioritize visit rating from DB

import SwiftUI
import CoreLocation

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
    @State private var cachedPhotoUrls: [String]? = nil
    @State private var openNow: Bool? = nil
    @State private var openingHours: [String]? = nil
    
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
                                .padding(.bottom, 4)
                                
                                if let address = placeAddress ?? formattedAddress, !address.isEmpty {
                                    AddressView(address: address)
                                        .padding(.bottom, 16)
                                }
                                
                                HStack(alignment: .center) {
                                    VisitStatusView(visitCount: visitCount, isLoading: false)
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
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                    }
                                }
                                .padding(.bottom, 20)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            
                            if let photos = cachedPhotoUrls, !photos.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(Array(photos.enumerated()), id: \.offset) { index, photoUrl in
                                            AsyncImage(url: URL(string: photoUrl)) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 160, height: 213)
                                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                                case .failure(_):
                                                    EmptyView()
                                                case .empty:
                                                    ProgressView()
                                                        .frame(width: 160, height: 213)
                                                @unknown default:
                                                    EmptyView()
                                                }
                                            }
                                            .id("\(photoUrl)-\(index)")
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                                .frame(height: 213)
                                .padding(.bottom, 20)
                            } else {
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
                            
                            if let hours = openingHours, !hours.isEmpty {
                                Divider()
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 20)
                                
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
                            
                            VStack(alignment: .leading, spacing: 0) {
                                Divider()
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 16)
                                
                                DirectionsButton(
                                    placeName: placeName ?? displayName,
                                    address: placeAddress ?? formattedAddress ?? ""
                                )
                                .padding(.horizontal, 20)
                                
                                Divider()
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                
                                if let phone = placePhone ?? phoneNumber, !phone.isEmpty {
                                    PhoneButton(phone: phone)
                                        .padding(.horizontal, 20)
                                    Divider()
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                }
                                
                                if let web = placeWebsite ?? website, !web.isEmpty {
                                    WebsiteButton(website: web)
                                        .padding(.horizontal, 20)
                                    Divider()
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                }
                            }
                            
                            Spacer().frame(height: 100)
                        }
                    }
                    
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
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
            cachedPhotoUrls = nil
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
            cachedPhotoUrls = nil
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
        
        // ✅ ALWAYS fetch DB data first (contains visit avgRating)
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
            cachedPhotoUrls = computeTopVisitPhotos(from: fetchedVisits)
            print("✅ [PlaceDetail] Set visits: \(count), photos: \(cachedPhotoUrls?.count ?? 0)")
        }
        
        let isStub = displayName == "Unknown Place" || displayName.isEmpty
        print("🔍 [PlaceDetail] isStub: \(isStub)")
        
        if isStub, let googleId = googlePlaceId {
            // Fetch Google for name, address, phone, website, hours
            print("🔍 [PlaceDetail] Fetching from Google API...")
            do {
                let googleData = try await GooglePlaceDetailFetcher.shared.fetchDetails(googlePlaceId: googleId)
                
                placeName = googleData.name
                placeAddress = googleData.address
                placePhone = googleData.phone
                placeWebsite = googleData.website
                openNow = googleData.openingHours?.openNow
                openingHours = googleData.openingHours?.weekdayText
                
                // ✅ Rating priority: DB avgRating (visits) > Google rating
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
            // Non-stub: use all DB data
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
    
    private func computeTopVisitPhotos(from visits: [EdgeFunctionVisit]) -> [String] {
        let visitsWithPhotos = visits.filter { !$0.photoUrls.isEmpty }
        let sortedVisits = visitsWithPhotos.sorted { ($0.likesCount ?? 0) > ($1.likesCount ?? 0) }
        let topVisits = Array(sortedVisits.prefix(10))
        return topVisits.compactMap { $0.photoUrls.first }
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
