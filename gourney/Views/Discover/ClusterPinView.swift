//
//  ClusterPinView.swift
//  gourney
//
//  Cluster pin view matching current design with count number
//

import SwiftUI

struct ClusterPinView: View {
    let count: Int
    let isVisited: Bool
    let onTap: () -> Void
    
    // ✅ PERFORMANCE: Cache gradient computation
    private var pinGradient: LinearGradient {
        isVisited ? visitedGradient : unvisitedGradient
    }
    
    private let visitedGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.35)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    private let unvisitedGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.5, blue: 0.3), Color(red: 1.0, green: 0.4, blue: 0.2)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // ✅ WHITE BORDER (outer circle)
                Circle()
                    .fill(Color.white)
                    .frame(width: clusterSize + 4, height: clusterSize + 4)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                
                // Inner colored circle
                Circle()
                    .fill(pinGradient)
                    .frame(width: clusterSize, height: clusterSize)
                
                // Count number in center
                Text("\(count)")
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Adaptive Sizing
    
    /// Size scales with count (larger clusters = bigger pins)
    private var clusterSize: CGFloat {
        switch count {
        case 2...5:
            return 38  // Slightly larger than single pin (32)
        case 6...10:
            return 44
        case 11...20:
            return 50
        case 21...50:
            return 56
        default:
            return 62  // Max size for 50+ pins
        }
    }
    
    /// Font size scales with cluster size
    private var fontSize: CGFloat {
        switch count {
        case 2...5:
            return 14
        case 6...10:
            return 16
        case 11...20:
            return 18
        case 21...50:
            return 20
        default:
            return 22
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ClusterPinView(count: 3, isVisited: true, onTap: {})
        ClusterPinView(count: 8, isVisited: true, onTap: {})
        ClusterPinView(count: 15, isVisited: false, onTap: {})
        ClusterPinView(count: 45, isVisited: true, onTap: {})
    }
    .padding()
}
