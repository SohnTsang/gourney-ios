// Services/AvatarUploadService.swift
// Optimized avatar upload - square crop, small file size
// Similar to ListCoverPhotoUploader but for profile avatars

import Foundation
import UIKit

class AvatarUploadService {
    static let shared = AvatarUploadService()
    
    private let supabaseUrl = Config.supabaseURL
    private let storageUrl: String
    private let bucketName = "user-photos"
    private let tempDirectory: URL
    
    private init() {
        storageUrl = "\(supabaseUrl)/storage/v1/object/\(bucketName)"
        
        // Create temp directory for disk-based processing
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("avatar_upload", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        self.tempDirectory = temp
    }
    
    // MARK: - Upload Avatar (Square, Small Size)
    
    func uploadAvatar(_ image: UIImage, userId: String) async throws -> String {
        // Progressive sizing for avatars - smaller than cover photos
        let sizes: [CGFloat] = [400, 300, 200]
        
        for (attempt, maxSize) in sizes.enumerated() {
            do {
                // Crop to square and resize
                let cropped = cropToSquare(image, maxSize: maxSize)
                
                // Target 100KB for fast loading
                let fileURL = try await compressAndSaveToDisk(cropped, targetSize: 100 * 1024)
                
                // Upload from disk
                let publicUrl = try await uploadFromDisk(fileURL, userId: userId)
                
                // Cleanup
                try? FileManager.default.removeItem(at: fileURL)
                
                if attempt > 0 {
                    print("✅ Avatar upload success at \(Int(maxSize))px")
                }
                
                return publicUrl
            } catch AvatarUploadError.compressionFailed {
                if attempt < sizes.count - 1 {
                    print("⚠️ Avatar compression failed at \(Int(maxSize))px, trying smaller...")
                    continue
                } else {
                    throw AvatarUploadError.compressionFailed
                }
            }
        }
        
        throw AvatarUploadError.compressionFailed
    }
    
    // MARK: - Crop to Square (Center crop)
    
    private func cropToSquare(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let originalWidth = image.size.width
        let originalHeight = image.size.height
        
        // Calculate square crop (center)
        let cropSize = min(originalWidth, originalHeight)
        let cropX = (originalWidth - cropSize) / 2
        let cropY = (originalHeight - cropSize) / 2
        let cropRect = CGRect(x: cropX, y: cropY, width: cropSize, height: cropSize)
        
        // Crop
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
            return image
        }
        let croppedImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        
        // Don't resize if already smaller
        if cropSize <= maxSize {
            return croppedImage
        }
        
        // Resize to target size
        let newSize = CGSize(width: maxSize, height: maxSize)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            croppedImage.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    // MARK: - Compress and Save to Disk
    
    private func compressAndSaveToDisk(_ image: UIImage, targetSize: Int) async throws -> URL {
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { throw AvatarUploadError.compressionFailed }
            
            var quality: CGFloat = 0.8
            var imageData: Data?
            
            while quality >= 0.3 {
                imageData = image.jpegData(compressionQuality: quality)
                
                if let data = imageData, data.count <= targetSize {
                    break
                }
                
                quality -= 0.1
                imageData = nil
            }
            
            guard let finalData = imageData else {
                throw AvatarUploadError.compressionFailed
            }
            
            print("📦 Avatar compressed to \(finalData.count / 1024)KB (quality: \(String(format: "%.1f", quality)))")
            
            // Save to temp file
            let fileName = UUID().uuidString + ".jpg"
            let fileURL = self.tempDirectory.appendingPathComponent(fileName)
            try finalData.write(to: fileURL)
            
            return fileURL
        }.value
    }
    
    // MARK: - Upload from Disk
    
    private func uploadFromDisk(_ fileURL: URL, userId: String) async throws -> String {
        for attempt in 1...2 {
            guard let token = SupabaseClient.shared.getAuthToken() else {
                throw AvatarUploadError.notAuthenticated
            }
            
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let filename = "avatar-\(timestamp).jpg"
            // Store in user's avatar folder
            let fullPath = "\(userId)/avatar/\(filename)"
            let uploadUrl = "\(storageUrl)/\(fullPath)"
            
            var request = URLRequest(url: URL(string: uploadUrl)!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30
            
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 60
            let session = URLSession(configuration: config)
            
            do {
                let (_, response) = try await session.upload(for: request, fromFile: fileURL)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AvatarUploadError.invalidResponse
                }
                
                if httpResponse.statusCode == 200 {
                    let publicUrl = "\(supabaseUrl)/storage/v1/object/public/\(bucketName)/\(fullPath)"
                    print("✅ Avatar uploaded: \(publicUrl)")
                    return publicUrl
                }
                
                // Token expired - try refresh
                if (httpResponse.statusCode == 401 || httpResponse.statusCode == 403) && attempt == 1 {
                    print("⚠️ [AvatarUpload] Token expired, refreshing...")
                    
                    if let refreshHandler = SupabaseClient.shared.authRefreshHandler {
                        let refreshed = await refreshHandler()
                        if refreshed {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            continue
                        }
                    }
                    
                    throw AvatarUploadError.notAuthenticated
                }
                
                throw AvatarUploadError.uploadFailed
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                throw error
            }
        }
        
        throw AvatarUploadError.uploadFailed
    }
    
    // MARK: - Cleanup
    
    func cleanupTempFiles() {
        try? FileManager.default.removeItem(at: tempDirectory)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
}

// MARK: - Errors

enum AvatarUploadError: LocalizedError {
    case compressionFailed
    case notAuthenticated
    case invalidResponse
    case uploadFailed
    
    var errorDescription: String? {
        switch self {
        case .compressionFailed: return "Failed to compress avatar"
        case .notAuthenticated: return "Not authenticated"
        case .invalidResponse: return "Invalid server response"
        case .uploadFailed: return "Upload failed"
        }
    }
}
