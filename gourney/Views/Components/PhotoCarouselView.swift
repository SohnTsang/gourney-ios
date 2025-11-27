//
//  PhotoCarouselView.swift
//  gourney
//
//  Created by 曾家浩 on 2025/11/26.
//


// Views/Shared/PhotoCarouselView.swift
// Instagram-style photo carousel with dynamic height
// Aspect ratio bounds: max 4:5 (portrait), min 1.91:1 (landscape)

import SwiftUI

struct PhotoCarouselView: View {
    let photos: [String]
    @Binding var currentIndex: Int
    var onPhotoTap: (() -> Void)?
    var showOverlay: Bool = false
    var overlayContent: AnyView? = nil
    
    @State private var photoAspectRatio: CGFloat = 1.0  // Default square
    
    // Instagram-style bounds
    private let maxRatio: CGFloat = 1.25   // 4:5 portrait max
    private let minRatio: CGFloat = 0.52   // 1.91:1 landscape min
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width * photoAspectRatio
            
            ZStack {
                // Black background
                Rectangle()
                    .fill(Color.black)
                
                // Photo TabView
                TabView(selection: $currentIndex) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, urlString in
                        AsyncImage(url: URL(string: urlString)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: width, maxHeight: height)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onPhotoTap?()
                                    }
                            case .failure:
                                photoPlaceholder
                            case .empty:
                                ProgressView()
                                    .tint(GourneyColors.coral)
                            @unknown default:
                                photoPlaceholder
                            }
                        }
                        .frame(width: width, height: height)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Optional overlay (gradient, user info, menu button)
                if showOverlay, let overlay = overlayContent {
                    overlay
                }
                
                // Page indicator dots - bottom center
                if photos.count > 1 {
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach(0..<photos.count, id: \.self) { index in
                                Circle()
                                    .fill(index == currentIndex ? Color.white : Color.white.opacity(0.4))
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
            .frame(width: width, height: height)
        }
        .frame(height: UIScreen.main.bounds.width * photoAspectRatio)
        .animation(.easeInOut(duration: 0.25), value: photoAspectRatio)
        .onAppear {
            loadFirstImageDimensions()
        }
    }
    
    private var photoPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 32))
                .foregroundColor(.gray)
            Text("Photo unavailable")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Load First Image Dimensions
    
    private func loadFirstImageDimensions() {
        guard let firstPhoto = photos.first,
              let url = URL(string: firstPhoto) else { return }
        
        // Check cache first
        if let cached = ImageDimensionCache.shared.get(for: firstPhoto) {
            let ratio = cached.height / cached.width
            photoAspectRatio = min(maxRatio, max(minRatio, ratio))
            return
        }
        
        // Load image to get dimensions
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let image = UIImage(data: data) else { return }
            
            let size = image.size
            ImageDimensionCache.shared.set(size, for: firstPhoto)
            
            let ratio = size.height / size.width
            let boundedRatio = min(maxRatio, max(minRatio, ratio))
            
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.25)) {
                    photoAspectRatio = boundedRatio
                }
            }
        }.resume()
    }
}

// MARK: - Image Dimension Cache

final class ImageDimensionCache {
    static let shared = ImageDimensionCache()
    private var cache: [String: CGSize] = [:]
    private let queue = DispatchQueue(label: "ImageDimensionCache")
    
    private init() {}
    
    func get(for url: String) -> CGSize? {
        queue.sync { cache[url] }
    }
    
    func set(_ size: CGSize, for url: String) {
        queue.async { self.cache[url] = size }
    }
    
    func clear() {
        queue.async { self.cache.removeAll() }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        PhotoCarouselView(
            photos: [
                "https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=800",
                "https://images.unsplash.com/photo-1617196034183-421b4917c92d?w=800"
            ],
            currentIndex: .constant(0)
        )
        
        Spacer()
    }
}
