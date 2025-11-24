// Services/ListCoverPhotoUploader.swift
// ✅ OPTIMIZED: Instagram-level compression + disk-based processing

import Foundation
import UIKit

class ListCoverPhotoUploader {
    static let shared = ListCoverPhotoUploader()
    
    private let supabaseUrl = Config.supabaseURL
    private let storageUrl: String
    private let bucketName = "user-photos"
    private let tempDirectory: URL
    
    private init() {
        storageUrl = "\(supabaseUrl)/storage/v1/object/\(bucketName)"
        
        // Create temp directory for disk-based processing
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("cover_upload", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        self.tempDirectory = temp
    }
    
    // MARK: - Upload Cover Photo (Instagram-Style Optimized)
    
    func uploadCoverPhoto(
        _ image: UIImage,
        userId: String,
        listId: String
    ) async throws -> String {
        // Progressive sizing - try larger first, fallback to smaller if compression fails
        let sizes: [CGFloat] = [1200, 1000, 800]
        
        for (attempt, maxWidth) in sizes.enumerated() {
            do {
                // Resize to cover dimensions
                let resized = resizeForCover(image, maxWidth: maxWidth)
                
                // Compress with target 200KB (smaller than visit photos for faster grid loading)
                let fileURL = try await compressAndSaveToDisk(resized, targetSize: 200 * 1024)
                
                // Upload from disk (streaming)
                let publicUrl = try await uploadFromDisk(fileURL, userId: userId, listId: listId)
                
                // Cleanup temp file
                try? FileManager.default.removeItem(at: fileURL)
                
                if attempt > 0 {
                    print("✅ Cover upload success at \(Int(maxWidth))px after \(attempt) attempts")
                }
                
                return publicUrl
            } catch CoverPhotoError.compressionFailed {
                if attempt < sizes.count - 1 {
                    print("⚠️ Compression failed at \(Int(maxWidth))px, trying \(Int(sizes[attempt + 1]))px...")
                    continue
                } else {
                    throw CoverPhotoError.compressionFailed
                }
            }
        }
        
        throw CoverPhotoError.compressionFailed
    }
    
    // MARK: - Resize for Cover (16:9, Progressive Width)
    
    private func resizeForCover(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let targetRatio: CGFloat = 16.0 / 9.0
        
        let originalWidth = image.size.width
        let originalHeight = image.size.height
        let originalRatio = originalWidth / originalHeight
        
        // Calculate dimensions to fill 16:9 ratio
        var cropRect: CGRect
        if originalRatio > targetRatio {
            // Image is wider - crop sides
            let cropHeight = originalHeight
            let cropWidth = cropHeight * targetRatio
            let cropX = (originalWidth - cropWidth) / 2
            cropRect = CGRect(x: cropX, y: 0, width: cropWidth, height: cropHeight)
        } else {
            // Image is taller - crop top/bottom
            let cropWidth = originalWidth
            let cropHeight = cropWidth / targetRatio
            let cropY = (originalHeight - cropHeight) / 2
            cropRect = CGRect(x: 0, y: cropY, width: cropWidth, height: cropHeight)
        }
        
        // Crop to ratio
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
            return image
        }
        let croppedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        
        // Don't resize if already smaller than target
        if cropRect.width <= maxWidth {
            return croppedImage
        }
        
        // Resize to target width
        let scale = maxWidth / cropRect.width
        let newSize = CGSize(width: maxWidth, height: cropRect.height * scale)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            croppedImage.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    // MARK: - Compress and Save to Disk (Memory-Efficient)
    
    private func compressAndSaveToDisk(_ image: UIImage, targetSize: Int) async throws -> URL {
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { throw CoverPhotoError.compressionFailed }
            
            var quality: CGFloat = 0.8
            var imageData: Data?
            
            // Iteratively compress until under target size
            while quality >= 0.3 {
                imageData = image.jpegData(compressionQuality: quality)
                
                if let data = imageData, data.count <= targetSize {
                    break
                }
                
                quality -= 0.1
                imageData = nil
            }
            
            guard let finalData = imageData else {
                throw CoverPhotoError.compressionFailed
            }
            
            print("📦 Compressed to \(finalData.count) bytes (quality: \(quality))")
            
            // Save to temp file
            let fileName = UUID().uuidString + ".jpg"
            let fileURL = self.tempDirectory.appendingPathComponent(fileName)
            try finalData.write(to: fileURL)
            
            return fileURL
        }.value
    }
    
    // MARK: - Upload from Disk (Streaming with Retry)
    
    private func uploadFromDisk(
        _ fileURL: URL,
        userId: String,
        listId: String
    ) async throws -> String {
        // Try up to 2 times (original + 1 retry with refreshed token)
        for attempt in 1...2 {
            guard let token = SupabaseClient.shared.getAuthToken() else {
                throw CoverPhotoError.notAuthenticated
            }
            
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let filename = "list-cover-\(listId)-\(timestamp).jpg"
            let fullPath = "\(userId)/covers/\(filename)"
            let uploadUrl = "\(storageUrl)/\(fullPath)"
            
            var request = URLRequest(url: URL(string: uploadUrl)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30
            
            // Configure session for streaming
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            let session = URLSession(configuration: config)
            
            do {
                let (_, response) = try await session.upload(for: request, fromFile: fileURL)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CoverPhotoError.invalidResponse
                }
                
                // Success
                if httpResponse.statusCode == 200 {
                    let publicUrl = "\(supabaseUrl)/storage/v1/object/public/\(bucketName)/\(fullPath)"
                    print("✅ Cover photo uploaded: \(publicUrl)")
                    return publicUrl
                }
                
                // Token expired - try refresh on first attempt
                if (httpResponse.statusCode == 401 || httpResponse.statusCode == 403) && attempt == 1 {
                    print("⚠️ [CoverUpload] Token expired, refreshing...")
                    
                    if let refreshHandler = SupabaseClient.shared.authRefreshHandler {
                        let refreshed = await refreshHandler()
                        
                        if refreshed {
                            print("✅ [CoverUpload] Token refreshed, retrying...")
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            continue
                        }
                    }
                    
                    throw CoverPhotoError.notAuthenticated
                }
                
                throw CoverPhotoError.uploadFailed
            } catch {
                if attempt < 2 {
                    print("⚠️ Upload attempt \(attempt) failed, retrying...")
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                throw error
            }
        }
        
        throw CoverPhotoError.uploadFailed
    }
    
    // MARK: - Cleanup
    
    func cleanupTempFiles() {
        try? FileManager.default.removeItem(at: tempDirectory)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
}

// MARK: - Errors

enum CoverPhotoError: LocalizedError {
    case compressionFailed
    case notAuthenticated
    case invalidResponse
    case uploadFailed
    
    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to compress image"
        case .notAuthenticated:
            return "Not authenticated"
        case .invalidResponse:
            return "Invalid server response"
        case .uploadFailed:
            return "Upload failed"
        }
    }
}
