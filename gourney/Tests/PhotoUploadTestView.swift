// Tests/PhotoUploadTestView.swift
// Test view to verify photo upload functionality
// TEMPORARY - Remove after testing

import SwiftUI
import PhotosUI

struct PhotoUploadTestView: View {
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var uploadedUrls: [String] = []
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var uploadProgress: [(index: Int, progress: Double)] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Photo Picker
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 5,
                        matching: .images
                    ) {
                        Label("Select Photos (Max 5)", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .onChange(of: selectedItems) { _, newItems in
                        Task {
                            await loadImages(from: newItems)
                        }
                    }
                    
                    // Selected Images Preview
                    if !selectedImages.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected: \(selectedImages.count) photos")
                                .font(.headline)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(selectedImages.indices, id: \.self) { index in
                                        Image(uiImage: selectedImages[index])
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 100, height: 100)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    // Upload Button
                    if !selectedImages.isEmpty && !isUploading {
                        Button {
                            Task {
                                await uploadPhotos()
                            }
                        } label: {
                            Label("Upload Photos", systemImage: "arrow.up.circle.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                        }
                    }
                    
                    // Upload Progress
                    if isUploading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            
                            Text("Uploading photos...")
                                .font(.headline)
                            
                            ForEach(uploadProgress, id: \.index) { item in
                                HStack {
                                    Text("Photo \(item.index + 1)")
                                        .font(.caption)
                                    Spacer()
                                    Text("\(Int(item.progress * 100))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                ProgressView(value: item.progress)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    // Uploaded URLs
                    if !uploadedUrls.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Upload Successful!")
                                    .font(.headline)
                                    .foregroundColor(.green)
                            }
                            
                            Text("Uploaded \(uploadedUrls.count) photos")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            ForEach(uploadedUrls, id: \.self) { url in
                                Text(url)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.blue)
                                    .lineLimit(2)
                                    .padding(8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(6)
                            }
                            
                            Button("Copy All URLs") {
                                UIPasteboard.general.string = uploadedUrls.joined(separator: "\n")
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Error Message
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Photo Upload Test")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Load Images
    
    private func loadImages(from items: [PhotosPickerItem]) async {
        selectedImages = []
        
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                // Resize immediately to reduce memory
                let resized = resizeImageForPreview(image)
                selectedImages.append(resized)
            }
        }
    }
    
    // Resize for preview to save memory
    private func resizeImageForPreview(_ image: UIImage) -> UIImage {
        let maxSize: CGFloat = 1024 // Max 1024px for preview
        let originalWidth = image.size.width
        let originalHeight = image.size.height
        
        if originalWidth <= maxSize && originalHeight <= maxSize {
            return image
        }
        
        let scale = min(maxSize / originalWidth, maxSize / originalHeight)
        let newSize = CGSize(width: originalWidth * scale, height: originalHeight * scale)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    // MARK: - Upload Photos
    
    private func uploadPhotos() async {
        guard let userId = AuthManager.shared.currentUser?.id else {
            errorMessage = "Not authenticated"
            return
        }
        
        isUploading = true
        errorMessage = nil
        uploadedUrls = []
        uploadProgress = selectedImages.indices.map { (index: $0, progress: 0.0) }
        
        do {
            let urls = try await PhotoUploadService.shared.uploadPhotos(
                selectedImages,
                userId: userId
            ) { index, progress in
                DispatchQueue.main.async {
                    if let i = uploadProgress.firstIndex(where: { $0.index == index }) {
                        uploadProgress[i].progress = progress
                    }
                }
            }
            
            await MainActor.run {
                uploadedUrls = urls
                isUploading = false
                
                // Clean up to free memory
                selectedImages = []
                selectedItems = []
                
                print("✅ Upload successful!")
                print("URLs: \(urls)")
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isUploading = false
                print("❌ Upload failed: \(error)")
            }
        }
    }
}

#Preview {
    PhotoUploadTestView()
}
