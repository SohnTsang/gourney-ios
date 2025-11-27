//
//  LoadingSpinner.swift
//  gourney
//
//  Created by æ›¾å®¶æµ© on 2025/11/27.
//


// Views/Shared/SharedLoadingComponents.swift
// Reusable loading components for DRY principle
// Used across ListsView, ProfileView, FeedView, etc.

import SwiftUI

// MARK: - Loading Spinner (Coral themed)

struct LoadingSpinner: View {
    var size: CGFloat = 20
    
    var body: some View {
        ProgressView()
            .tint(GourneyColors.coral)
            .scaleEffect(size / 20)
    }
}

// MARK: - Centered Loading View (for full-screen loading states)

struct CenteredLoadingView: View {
    var body: some View {
        VStack {
            Spacer()
            LoadingSpinner()
            Spacer()
        }
    }
}

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(0.3),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 400
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Skeleton Rectangle (for placeholder content)

struct SkeletonRect: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 4
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .frame(width: width, height: height)
            .shimmer()
    }
}

// MARK: - Grid Skeleton Cell (for profile visits grid)

struct GridSkeletonCell: View {
    var aspectRatio: CGFloat = 4/5
    
    var body: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .aspectRatio(aspectRatio, contentMode: .fill)
            .shimmer()
    }
}

// MARK: - Preview

#Preview("Loading Spinner") {
    VStack(spacing: 30) {
        LoadingSpinner()
        LoadingSpinner(size: 30)
    }
}

#Preview("Centered Loading") {
    CenteredLoadingView()
}

#Preview("Shimmer Effect") {
    VStack(spacing: 12) {
        SkeletonRect(width: 200, height: 20)
        SkeletonRect(width: 150, height: 14)
        SkeletonRect(height: 100, cornerRadius: 8)
    }
    .padding()
}

#Preview("Grid Skeleton") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 2) {
        ForEach(0..<6, id: \.self) { _ in
            GridSkeletonCell()
        }
    }
    .padding(2)
}
