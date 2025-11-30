// Views/Visit/VisitFormComponents.swift
// Shared components for AddVisitView and EditVisitView
// DRY principle - reusable rating, comment, visibility, photos sections

import SwiftUI
import PhotosUI

// MARK: - Rating Section

struct VisitRatingSection: View {
    @Binding var rating: Int
    var allowDeselect: Bool = false  // EditVisit allows tap same star to deselect
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rating")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)
            
            HStack(spacing: 16) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            if allowDeselect && rating == star {
                                rating = 0
                            } else {
                                rating = star
                            }
                        }
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 28))
                            .foregroundColor(star <= rating ? GourneyColors.coral : GourneyColors.coral.opacity(0.3))
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Comment Section

struct VisitCommentSection: View {
    @Binding var comment: String
    let maxLength: Int
    var placeholder: String = "Share your experience..."
    var title: String = "Share your thoughts"
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)
            
            VStack(alignment: .trailing, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if comment.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 15))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.top, 12)
                            .padding(.leading, 14)
                    }
                    
                    TextEditor(text: $comment)
                        .font(.system(size: 15))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(8)
                        .onChange(of: comment) { _, newValue in
                            if newValue.count > maxLength {
                                comment = String(newValue.prefix(maxLength))
                            }
                        }
                }
                .background(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            comment.isEmpty ? Color.clear : GourneyColors.coral.opacity(0.5),
                            lineWidth: 1.5
                        )
                )
                
                Text("\(comment.count)/\(maxLength)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(comment.count >= maxLength - 100 ? GourneyColors.coral : .secondary)
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Visibility Section

struct VisitVisibilitySection: View {
    @Binding var visibility: VisitVisibility
    var title: String = "Who can see this?"
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)
            
            VStack(spacing: 0) {
                ForEach(VisitVisibility.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            visibility = option
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(visibility == option ? GourneyColors.coral : Color.gray.opacity(0.3))
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: option.icon)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(visibility == option ? .white : .secondary)
                                }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text(option.description)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if visibility == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(GourneyColors.coral)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(visibility == option ? GourneyColors.coral.opacity(0.06) : Color.clear)
                    }
                    
                    if option != VisitVisibility.allCases.last {
                        Divider()
                            .padding(.leading, 66)
                    }
                }
            }
            .background(colorScheme == .dark ? Color(white: 0.12) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Place Section (Read-only for EditVisit)

struct VisitPlaceReadOnlySection: View {
    let placeName: String
    let placeLocation: String
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Place")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)
            
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(GourneyColors.coral)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(placeName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    if !placeLocation.isEmpty {
                        Text(placeLocation)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Lock icon indicating not editable
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(.systemGray3))
            }
            .padding(14)
            .background(colorScheme == .dark ? Color(white: 0.12) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Photo Thumbnail (for new photos from picker)

struct VisitPhotoThumbnail: View {
    let image: UIImage
    let width: CGFloat
    let height: CGFloat
    var progress: Double? = nil
    var onRemove: (() -> Void)?
    var onTap: (() -> Void)?
    
    private var isUploading: Bool {
        progress != nil && progress! < 1.0
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Progress overlay
                if let progress = progress, progress < 1.0 {
                    ZStack {
                        Color.black.opacity(0.5)
                        
                        VStack(spacing: 8) {
                            ProgressView(value: progress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .white))
                                .frame(width: 100)
                            
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                if !isUploading {
                    onTap?()
                }
            }
            
            // Remove button - white X with shadow (matches AddVisitView)
            if let onRemove = onRemove {
                Button(action: onRemove) {
                    ZStack {
                        Circle()
                            .fill(.clear)
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 0)
                    }
                }
                .buttonStyle(.plain)
                .zIndex(10)
                .disabled(isUploading)
                .opacity(isUploading ? 0.3 : 1.0)
                .padding(8)
            }
        }
    }
}

// MARK: - Async Photo Thumbnail (for existing photo URLs)

struct VisitAsyncPhotoThumbnail: View {
    let urlString: String
    let width: CGFloat
    let height: CGFloat
    var onRemove: (() -> Void)?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                case .failure:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(width: width, height: height)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                case .empty:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(width: width, height: height)
                        .overlay(ProgressView().tint(GourneyColors.coral))
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: width, height: height)
            
            // Remove button - white X with shadow (matches AddVisitView)
            if let onRemove = onRemove {
                Button(action: onRemove) {
                    ZStack {
                        Circle()
                            .fill(.clear)
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 0)
                    }
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
    }
}

// MARK: - Add Photo Button (dashed border style)

struct VisitAddPhotoButton: View {
    let width: CGFloat
    let height: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(GourneyColors.coral.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
            .frame(width: width, height: height)
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(GourneyColors.coral.opacity(0.7))
            }
    }
}

// MARK: - Empty Photos Picker Placeholder

struct VisitEmptyPhotosPlaceholder: View {
    let maxPhotos: Int
    let height: CGFloat
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundColor(GourneyColors.coral.opacity(0.6))
            
            Text("Add Photos")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("Up to \(maxPhotos) photos")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(colorScheme == .dark ? Color(white: 0.15) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Photos Section (Full shared component)

struct VisitPhotosSection<ID: Hashable>: View {
    // Photo data
    let existingPhotoURLs: [String]  // For EditVisit - existing photos from server
    let loadedImages: [(id: ID, image: UIImage)]  // New photos from picker
    let maxPhotos: Int
    let uploadProgress: [ID: Double]
    
    // Bindings
    @Binding var selectedPhotos: [PhotosPickerItem]
    
    // Actions
    var onRemoveExisting: ((Int) -> Void)?
    var onRemoveNew: ((ID) -> Void)?
    var onPhotoTap: ((Int) -> Void)?  // Index in loadedImages
    var onClearAll: (() -> Void)?
    
    // Layout
    private let photoWidth: CGFloat = 160
    private let photoHeight: CGFloat = 213
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var totalPhotoCount: Int {
        existingPhotoURLs.count + loadedImages.count
    }
    
    private var remainingSlots: Int {
        maxPhotos - totalPhotoCount
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Photos")
                    .font(.system(size: 15, weight: .semibold))
                
                Text("\(totalPhotoCount)/\(maxPhotos)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Clear All button
                if totalPhotoCount > 0, let onClearAll = onClearAll {
                    Button(action: onClearAll) {
                        Text("Clear All")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(GourneyColors.coral)
                    }
                }
            }
            .padding(.horizontal, 16)
            
            // Content
            if totalPhotoCount == 0 {
                // Empty state
                emptyStatePicker
            } else {
                // Photos grid
                photosScrollView
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStatePicker: some View {
        PhotosPicker(
            selection: $selectedPhotos,
            maxSelectionCount: maxPhotos,
            matching: .images
        ) {
            VisitEmptyPhotosPlaceholder(maxPhotos: maxPhotos, height: photoHeight)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Photos Scroll View
    
    private var photosScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Existing photos (AsyncImage)
                ForEach(Array(existingPhotoURLs.enumerated()), id: \.offset) { index, urlString in
                    VisitAsyncPhotoThumbnail(
                        urlString: urlString,
                        width: photoWidth,
                        height: photoHeight,
                        onRemove: onRemoveExisting != nil ? { onRemoveExisting?(index) } : nil
                    )
                }
                
                // New photos (UIImage)
                ForEach(Array(loadedImages.enumerated()), id: \.element.id) { index, item in
                    VisitPhotoThumbnail(
                        image: item.image,
                        width: photoWidth,
                        height: photoHeight,
                        progress: uploadProgress[item.id],
                        onRemove: onRemoveNew != nil ? { onRemoveNew?(item.id) } : nil,
                        onTap: onPhotoTap != nil ? { onPhotoTap?(index) } : nil
                    )
                }
                
                // Add more button
                if remainingSlots > 0 {
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: maxPhotos,
                        matching: .images
                    ) {
                        VisitAddPhotoButton(width: photoWidth, height: photoHeight)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Previews

#Preview("Rating Section") {
    VStack {
        VisitRatingSection(rating: .constant(3))
        VisitRatingSection(rating: .constant(0), allowDeselect: true)
    }
    .padding()
}

#Preview("Comment Section") {
    VisitCommentSection(comment: .constant("Great food!"), maxLength: 1000)
        .padding()
}

#Preview("Visibility Section") {
    VisitVisibilitySection(visibility: .constant(.public))
        .padding()
}

#Preview("Place Read-Only") {
    VisitPlaceReadOnlySection(placeName: "Ichiran Ramen Shibuya", placeLocation: "Shibuya, Tokyo")
        .padding()
}
