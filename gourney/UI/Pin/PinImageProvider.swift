//
//  PinImageProvider.swift
//  gourney
//
//  Provides teardrop-shaped pin images for map annotations
//

import UIKit
import SwiftUI

enum PinImageProvider {
    
    /// Creates a teardrop-shaped pin image
    /// - Parameter size: Size of the pin (width, height)
    /// - Returns: UIImage of the teardrop pin
    static func original(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            
            // Define teardrop path
            let path = UIBezierPath()
            
            // Pin dimensions
            let width = size.width
            let height = size.height
            let circleRadius = width / 2
            let tipY = height
            
            // Start at bottom tip
            path.move(to: CGPoint(x: width / 2, y: tipY))
            
            // Left curve to top circle
            path.addQuadCurve(
                to: CGPoint(x: 0, y: circleRadius),
                controlPoint: CGPoint(x: 0, y: height * 0.65)
            )
            
            // Top semicircle (left to right)
            path.addArc(
                withCenter: CGPoint(x: width / 2, y: circleRadius),
                radius: circleRadius,
                startAngle: .pi,
                endAngle: 0,
                clockwise: true
            )
            
            // Right curve back to tip
            path.addQuadCurve(
                to: CGPoint(x: width / 2, y: tipY),
                controlPoint: CGPoint(x: width, y: height * 0.65)
            )
            
            path.close()
            
            // Fill with red gradient
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0).cgColor,
                    UIColor(red: 0.95, green: 0.3, blue: 0.35, alpha: 1.0).cgColor
                ] as CFArray,
                locations: [0.0, 1.0]
            )!
            
            context.cgContext.saveGState()
            path.addClip()
            
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: width, y: height),
                options: []
            )
            
            context.cgContext.restoreGState()
            
            // Add white fork.knife icon
            let iconSize: CGFloat = 16
            let iconRect = CGRect(
                x: (width - iconSize) / 2,
                y: (circleRadius - iconSize / 2),
                width: iconSize,
                height: iconSize
            )
            
            // Draw fork.knife symbol
            let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
            if let iconImage = UIImage(systemName: "fork.knife", withConfiguration: config) {
                iconImage.withTintColor(.white, renderingMode: .alwaysOriginal)
                    .draw(in: iconRect)
            }
        }
    }
    
    /// Creates an orange teardrop pin for non-visited places
    static func nonVisited(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            
            // Define teardrop path
            let path = UIBezierPath()
            
            let width = size.width
            let height = size.height
            let circleRadius = width / 2
            let tipY = height
            
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
            
            // Fill with orange gradient
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 1.0, green: 0.5, blue: 0.3, alpha: 1.0).cgColor,
                    UIColor(red: 1.0, green: 0.4, blue: 0.2, alpha: 1.0).cgColor
                ] as CFArray,
                locations: [0.0, 1.0]
            )!
            
            context.cgContext.saveGState()
            path.addClip()
            
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: width, y: height),
                options: []
            )
            
            context.cgContext.restoreGState()
            
            // Add white fork.knife icon
            let iconSize: CGFloat = 16
            let iconRect = CGRect(
                x: (width - iconSize) / 2,
                y: (circleRadius - iconSize / 2),
                width: iconSize,
                height: iconSize
            )
            
            let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
            if let iconImage = UIImage(systemName: "fork.knife", withConfiguration: config) {
                iconImage.withTintColor(.white, renderingMode: .alwaysOriginal)
                    .draw(in: iconRect)
            }
        }
    }
}
