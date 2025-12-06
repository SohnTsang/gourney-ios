//
//  PinImageProvider.swift
//  gourney
//
//  ✅ FIXED: Grey for non-visited, Red for visited
//  ✅ OPTIMIZED: Cached images, minimal memory
//

import UIKit

enum PinImageProvider {
    
    // ✅ PERFORMANCE: Static cached images
    private static var cachedVisited: UIImage?
    private static var cachedNonVisited: UIImage?
    
    /// Red/Coral teardrop pin for VISITED places
    static func original(size: CGSize = CGSize(width: 34, height: 50)) -> UIImage {
        if let cached = cachedVisited { return cached }
        
        let image = createTeardropPin(
            size: size,
            topColor: UIColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0),
            bottomColor: UIColor(red: 0.95, green: 0.3, blue: 0.35, alpha: 1.0)
        )
        cachedVisited = image
        return image
    }
    
    /// ✅ GREY teardrop pin for NON-VISITED places
    static func nonVisited(size: CGSize = CGSize(width: 34, height: 50)) -> UIImage {
        if let cached = cachedNonVisited { return cached }
        
        let image = createTeardropPin(
            size: size,
            topColor: .systemGray3,
            bottomColor: .systemGray4
        )
        cachedNonVisited = image
        return image
    }
    
    /// Clear cached images (call on memory warning)
    static func clearCache() {
        cachedVisited = nil
        cachedNonVisited = nil
    }
    
    // MARK: - Private
    
    private static func createTeardropPin(size: CGSize, topColor: UIColor, bottomColor: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            let path = UIBezierPath()
            let width = size.width
            let height = size.height
            let circleRadius = width / 2
            let tipY = height
            
            // Teardrop shape
            path.move(to: CGPoint(x: width / 2, y: tipY))
            
            path.addQuadCurve(
                to: CGPoint(x: 0, y: circleRadius),
                controlPoint: CGPoint(x: 0, y: height * 0.65)
            )
            
            path.addArc(
                withCenter: CGPoint(x: width / 2, y: circleRadius),
                radius: circleRadius,
                startAngle: .pi,
                endAngle: 0,
                clockwise: true
            )
            
            path.addQuadCurve(
                to: CGPoint(x: width / 2, y: tipY),
                controlPoint: CGPoint(x: width, y: height * 0.65)
            )
            
            path.close()
            
            // Gradient fill
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [topColor.cgColor, bottomColor.cgColor] as CFArray,
                locations: [0.0, 1.0]
            ) else { return }
            
            context.cgContext.saveGState()
            path.addClip()
            
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: width, y: height),
                options: []
            )
            
            context.cgContext.restoreGState()
            
            // Fork.knife icon
            let iconSize: CGFloat = 16
            let iconRect = CGRect(
                x: (width - iconSize) / 2,
                y: circleRadius - iconSize / 2,
                width: iconSize,
                height: iconSize
            )
            
            let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
            if let icon = UIImage(systemName: "fork.knife", withConfiguration: config) {
                icon.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: iconRect)
            }
        }
    }
}
