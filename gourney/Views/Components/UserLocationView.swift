// Views/Components/UserLocationView.swift
// Beautiful user location indicator with pulse animation

import SwiftUI
import MapKit

struct UserLocationView: View {
    let accuracy: CLLocationAccuracy
    let heading: CLHeading?
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    
    // ✅ PERFORMANCE: Use constants
    private let dotSize: CGFloat = 16
    private let pulseAnimationDuration: Double = 2.0
    
    var body: some View {
        ZStack {
            // Layer 1: Accuracy Circle (outermost)
            if accuracy > 0 && accuracy < 100 {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: accuracyCircleSize, height: accuracyCircleSize)
            }
            
            // Layer 2: Pulsing Ring
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
                .animation(
                    .easeInOut(duration: pulseAnimationDuration)
                    .repeatForever(autoreverses: true),
                    value: pulseScale
                )
            
            // Layer 3: Outer Ring (solid)
            Circle()
                .strokeBorder(Color.white, lineWidth: 3)
                .background(Circle().fill(Color.blue))
                .frame(width: dotSize, height: dotSize)
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
            
            // Layer 4: Inner Dot
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
            
            // Layer 5: Direction Cone (if heading available)
            if let heading = heading, heading.headingAccuracy >= 0 {
                DirectionCone(heading: heading.trueHeading)
                    .frame(width: 24, height: 24)
                    .offset(y: -20)
            }
        }
        .onAppear {
            startPulseAnimation()
        }
    }
    
    // MARK: - Computed Properties
    
    private var accuracyCircleSize: CGFloat {
        // Convert meters to approximate pixels
        // Rough approximation: 1 meter ≈ 2 pixels at street level zoom
        let pixels = min(accuracy * 2, 200)
        return CGFloat(pixels)
    }
    
    // MARK: - Animation
    
    private func startPulseAnimation() {
        pulseScale = 1.5
        pulseOpacity = 0.0
    }
}

// MARK: - Direction Cone

struct DirectionCone: View {
    let heading: CLLocationDirection
    
    var body: some View {
        Triangle()
            .fill(Color.blue.opacity(0.5))
            .rotationEffect(.degrees(heading))
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Draw triangle pointing up
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        
        VStack(spacing: 40) {
            // High accuracy
            UserLocationView(accuracy: 10, heading: nil)
            Text("High Accuracy (10m)")
                .font(.caption)
            
            // Medium accuracy
            UserLocationView(accuracy: 50, heading: nil)
            Text("Medium Accuracy (50m)")
                .font(.caption)
            
            // With heading
            UserLocationView(
                accuracy: 15,
                heading: CLHeading()
            )
            Text("With Direction")
                .font(.caption)
        }
    }
}
