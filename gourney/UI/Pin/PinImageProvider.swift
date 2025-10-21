// Utils/PinImageProvider.swift
// Generates custom pin images for map annotations

import UIKit

class PinImageProvider {
    
    // MARK: - Generate Pin Image
    
    static func original(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            let ctx = context.cgContext
            
            // Pin colors
            let pinColor = UIColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)
            let shadowColor = UIColor.black.withAlphaComponent(0.3)
            
            // Pin shape path
            let pinPath = UIBezierPath()
            
            // Start from bottom point
            pinPath.move(to: CGPoint(x: size.width / 2, y: size.height))
            
            // Draw pin body (teardrop shape)
            let radius = size.width / 2
            let center = CGPoint(x: size.width / 2, y: radius)
            
            // Left curve
            pinPath.addLine(to: CGPoint(x: size.width / 2 - radius * 0.3, y: size.height - radius * 0.5))
            
            // Top circle arc (left side)
            pinPath.addArc(
                withCenter: center,
                radius: radius,
                startAngle: CGFloat.pi * 0.7,
                endAngle: CGFloat.pi * 2.3,
                clockwise: true
            )
            
            // Right curve
            pinPath.addLine(to: CGPoint(x: size.width / 2 + radius * 0.3, y: size.height - radius * 0.5))
            
            pinPath.close()
            
            // Draw shadow
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: shadowColor.cgColor)
            pinColor.setFill()
            pinPath.fill()
            ctx.restoreGState()
            
            // Draw inner white circle
            let innerCircleRadius = radius * 0.4
            let innerCircle = UIBezierPath(
                arcCenter: center,
                radius: innerCircleRadius,
                startAngle: 0,
                endAngle: CGFloat.pi * 2,
                clockwise: true
            )
            UIColor.white.setFill()
            innerCircle.fill()
            
            // Draw fork & knife icon
            let iconSize: CGFloat = innerCircleRadius * 1.2
            let iconRect = CGRect(
                x: center.x - iconSize / 2,
                y: center.y - iconSize / 2,
                width: iconSize,
                height: iconSize
            )
            
            // Simple fork & knife representation
            ctx.saveGState()
            ctx.setLineWidth(1.5)
            pinColor.setStroke()
            
            // Fork (left)
            let forkX = iconRect.minX + iconRect.width * 0.3
            ctx.move(to: CGPoint(x: forkX, y: iconRect.minY + 2))
            ctx.addLine(to: CGPoint(x: forkX, y: iconRect.maxY - 2))
            ctx.strokePath()
            
            // Fork prongs
            for i in 0..<3 {
                let prongX = forkX - 2 + CGFloat(i) * 2
                ctx.move(to: CGPoint(x: prongX, y: iconRect.minY + 2))
                ctx.addLine(to: CGPoint(x: prongX, y: iconRect.minY + 5))
                ctx.strokePath()
            }
            
            // Knife (right)
            let knifeX = iconRect.maxX - iconRect.width * 0.3
            ctx.move(to: CGPoint(x: knifeX, y: iconRect.minY + 2))
            ctx.addLine(to: CGPoint(x: knifeX, y: iconRect.maxY - 2))
            ctx.strokePath()
            
            // Knife blade
            ctx.move(to: CGPoint(x: knifeX, y: iconRect.minY + 2))
            ctx.addLine(to: CGPoint(x: knifeX + 2, y: iconRect.minY + 4))
            ctx.strokePath()
            
            ctx.restoreGState()
        }
    }
    
    // MARK: - Cache (Optional)
    
    private static var cache: [String: UIImage] = [:]
    
    static func cached(size: CGSize) -> UIImage {
        let key = "\(Int(size.width))x\(Int(size.height))"
        
        if let cached = cache[key] {
            return cached
        }
        
        let image = original(size: size)
        cache[key] = image
        return image
    }
    
    static func clearCache() {
        cache.removeAll()
    }
}
