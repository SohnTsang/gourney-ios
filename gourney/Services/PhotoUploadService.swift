// Services/PhotoUploadService.swift
// Production-grade photo upload with Instagram-level memory optimization
// Week 7 Day 4: Add Visit Flow - Photo Upload

import Foundation
import UIKit

class PhotoUploadService {
    static let shared = PhotoUploadService()
    
    private let supabaseUrl = Config.supabaseURL
    private let storageUrl: String
    private let bucketName = "user-photos"
    
    // Temporary directory for disk-based processing
    private let tempDirectory: URL
    
    private init() {
        storageUrl = "\(supabaseUrl)/storage/v1/object/\(bucketName)"
        
        // Create temp directory for disk-based processing
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("photo_upload", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        self.tempDirectory = temp
    }
    
    // MARK: - Upload Multiple Photos (Memory Optimized)
    
    /// Upload multiple photos with aggressive memory management
    /// Uses Instagram-style disk-based processing to minimize RAM usage
    func uploadPhotos(
        _ images: [UIImage],
        userId: String,
        progressHandler: ((Int, Double) -> Void)? = nil
    ) async throws -> [String] {
        guard !images.isEmpty else {
            throw PhotoUploadError.noPhotos
        }
        
        guard images.count <= 5 else {
            throw PhotoUploadError.tooManyPhotos
        }
        
        var uploadedUrls: [String] = []
        
        // Upload photos sequentially with aggressive memory cleanup
        for (index, image) in images.enumerated() {
            progressHandler?(index, 0.0)
            
            // Upload and immediately release memory
            let url = try await uploadSinglePhoto(
                image,
                userId: userId,
                index: index,
                progressHandler: { progress in
                    progressHandler?(index, progress)
                }
            )
            
            uploadedUrls.append(url)
            progressHandler?(index, 1.0)
            
            // Small delay to allow memory cleanup
            if index < images.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
        
        // Clean up temp directory
        cleanupTempFiles()
        
        return uploadedUrls
    }
    
    // MARK: - Upload Single Photo (Progressive Resizing - Instagram Style)
    
    private func uploadSinglePhoto(
        _ image: UIImage,
        userId: String,
        index: Int,
        progressHandler: ((Double) -> Void)?
    ) async throws -> String {
        progressHandler?(0.1)
        
        // Instagram-style progressive resizing: try smaller sizes until compression succeeds
        let sizes: [CGFloat] = [1200, 1000, 800, 600]
        
        for (attempt, maxWidth) in sizes.enumerated() {
            let resized = resizeImage(image, maxWidth: maxWidth)
            
            progressHandler?(0.2)
            
            do {
                let fileURL = try await compressAndSaveToDisk(resized, targetSize: 600 * 1024)
                progressHandler?(0.4)
                
                let publicUrl = try await uploadFromDisk(fileURL, userId: userId, index: index, progressHandler: progressHandler)
                
                try? FileManager.default.removeItem(at: fileURL)
                progressHandler?(1.0)
                
                if attempt > 0 {
                    print("✅ Success at \(Int(maxWidth))px after \(attempt) resize attempts")
                }
                
                return publicUrl
            } catch PhotoUploadError.compressionFailed {
                if attempt < sizes.count - 1 {
                    print("⚠️ Compression failed at \(Int(maxWidth))px, trying \(Int(sizes[attempt + 1]))px...")
                    continue
                } else {
                    // Last attempt failed
                    throw PhotoUploadError.compressionFailed
                }
            }
        }
        
        throw PhotoUploadError.compressionFailed
    }
    
    // MARK: - Compress and Save to Disk (Memory-Efficient)
    
    private func compressAndSaveToDisk(_ image: UIImage, targetSize: Int) async throws -> URL {
        return try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { throw PhotoUploadError.compressionFailed }
            
            var quality: CGFloat = 0.7
            var imageData: Data?
            
            // Iteratively compress until under target size
            while quality >= 0.2 {  // Allow down to 0.2 quality for complex images
                // Each compression attempt in its own scope
                imageData = image.jpegData(compressionQuality: quality)
                
                if let data = imageData, data.count <= targetSize {
                    break
                }
                
                quality -= 0.1
                imageData = nil // Release previous attempt
            }
            
            guard let finalData = imageData else {
                throw PhotoUploadError.compressionFailed
            }
            
            let originalSize = image.jpegData(compressionQuality: 1.0)?.count ?? 0
            
            print("📦 Compressed: \(originalSize) → \(finalData.count) bytes (\(Double(finalData.count) / 1024 / 1024) MB) [quality: \(quality)]")
            
            // Save to temp file
            let fileName = UUID().uuidString + ".jpg"
            let fileURL = self.tempDirectory.appendingPathComponent(fileName)
            
            try finalData.write(to: fileURL)
            
            // Clear data from memory immediately
            return fileURL
            
        }.value
    }
    
    // MARK: - Upload from Disk (Streaming with Retry)
    
    private func uploadFromDisk(
        _ fileURL: URL,
        userId: String,
        index: Int,
        progressHandler: ((Double) -> Void)?
    ) async throws -> String {
        let maxRetries = 3
        var lastError: Error?
        
        // Retry up to 3 times
        for attempt in 1...maxRetries {
            do {
                return try await performUpload(fileURL: fileURL, userId: userId, index: index, progressHandler: progressHandler, attempt: attempt)
            } catch let error as NSError where error.code == -1017 {
                print("⚠️ Attempt \(attempt)/\(maxRetries) failed with -1017")
                lastError = error
                
                if attempt < maxRetries {
                    // Wait before retry (exponential backoff)
                    let delay = UInt64(attempt * 1_000_000_000) // 1s, 2s, 3s
                    try? await Task.sleep(nanoseconds: delay)
                }
            } catch PhotoUploadError.uploadFailed(let statusCode) where (statusCode == 401 || statusCode == 403) {
                // Token expired - try refresh
                print("⚠️ Upload failed with \(statusCode) (token expired)")
                
                if attempt < maxRetries {
                    if let refreshHandler = SupabaseClient.shared.authRefreshHandler {
                        print("🔄 Refreshing token...")
                        let refreshed = await refreshHandler()
                        
                        if refreshed {
                            print("✅ Token refreshed, retrying upload...")
                            let delay = UInt64(500_000_000) // 0.5s
                            try? await Task.sleep(nanoseconds: delay)
                            continue
                        } else {
                            print("❌ Token refresh failed")
                            throw PhotoUploadError.notAuthenticated
                        }
                    } else {
                        throw PhotoUploadError.notAuthenticated
                    }
                } else {
                    throw PhotoUploadError.uploadFailed(statusCode: statusCode)
                }
            } catch {
                // Other errors don't retry
                throw error
            }
        }
        
        throw lastError ?? PhotoUploadError.uploadFailed(statusCode: -1017)
    }
    
    private func performUpload(
        fileURL: URL,
        userId: String,
        index: Int,
        progressHandler: ((Double) -> Void)?,
        attempt: Int
    ) async throws -> String {
        // Get file size without loading to memory
        let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int ?? 0
        
        // Generate unique filename with UUID to prevent duplicates
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let uniqueId = UUID().uuidString.prefix(8)  // First 8 chars of UUID
        let filename = "\(timestamp)-\(index)-\(uniqueId).jpg"
        let fullPath = "\(userId)/visits/\(filename)"
        
        progressHandler?(0.5)
        
        // Get auth token
        guard let token = await getAuthToken() else {
            throw PhotoUploadError.notAuthenticated
        }
        
        // Create upload request
        let uploadUrl = "\(storageUrl)/\(fullPath)"
        
        print("📤 Uploading from disk (attempt \(attempt)/3): \(uploadUrl)")
        print("📤 File size: \(Double(fileSize) / 1024 / 1024) MB")
        
        var request = URLRequest(url: URL(string: uploadUrl)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        // Configure session for streaming
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.httpMaximumConnectionsPerHost = 1
        let session = URLSession(configuration: config)
        
        progressHandler?(0.7)
        
        // Upload from file (streaming - file is read in chunks, not all at once)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.upload(for: request, fromFile: fileURL)
        } catch let error as NSError {
            // Handle Supabase response parsing bug
            if error.code == -1017 {
                print("⚠️ Response parsing failed (error -1017), verifying upload...")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                
                let publicUrl = "\(supabaseUrl)/storage/v1/object/public/\(bucketName)/\(fullPath)"
                var headRequest = URLRequest(url: URL(string: publicUrl)!)
                headRequest.httpMethod = "HEAD"
                headRequest.timeoutInterval = 10
                
                if let (_, headResponse) = try? await URLSession.shared.data(for: headRequest),
                   let httpHead = headResponse as? HTTPURLResponse,
                   httpHead.statusCode == 200 {
                    print("✅ Upload verified via HEAD request")
                    progressHandler?(1.0)
                    print("✅ Photo uploaded: \(publicUrl)")
                    return publicUrl
                }
            }
            throw error
        }
        
        progressHandler?(0.9)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoUploadError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Upload failed (\(httpResponse.statusCode)): \(errorMessage)")
            throw PhotoUploadError.uploadFailed(statusCode: httpResponse.statusCode)
        }
        
        let publicUrl = "\(supabaseUrl)/storage/v1/object/public/\(bucketName)/\(fullPath)"
        print("✅ Photo uploaded: \(publicUrl)")
        
        return publicUrl
    }
    
    // MARK: - Resize Image (Memory-Efficient)
    
    private func resizeImage(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let originalWidth = image.size.width
        let originalHeight = image.size.height
        
        if originalWidth <= maxWidth {
            return image
        }
        
        let scale = maxWidth / originalWidth
        let newHeight = originalHeight * scale
        let newSize = CGSize(width: maxWidth, height: newHeight)
        
        // Use UIGraphicsImageRenderer (more efficient than UIGraphicsBeginImageContext)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Always use 1.0 scale for uploads
        format.opaque = true // Opaque JPEG rendering is faster
        
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanupTempFiles() {
        try? FileManager.default.removeItem(at: tempDirectory)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Get Auth Token
    
    private func getAuthToken() async -> String? {
        return SupabaseClient.shared.getAuthToken()
    }
}

// MARK: - Errors

enum PhotoUploadError: LocalizedError {
    case noPhotos
    case tooManyPhotos
    case compressionFailed
    case fileTooLarge(size: Int)
    case notAuthenticated
    case invalidResponse
    case uploadFailed(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .noPhotos:
            return "No photos to upload"
        case .tooManyPhotos:
            return "Maximum 5 photos allowed"
        case .compressionFailed:
            return "Failed to compress image"
        case .fileTooLarge(let size):
            let sizeMB = Double(size) / (1024 * 1024)
            return String(format: "Photo too large (%.1f MB). Maximum 5 MB per photo.", sizeMB)
        case .notAuthenticated:
            return "User not authenticated"
        case .invalidResponse:
            return "Invalid response from server"
        case .uploadFailed(let statusCode):
            return "Upload failed (Status \(statusCode))"
        }
    }
}
