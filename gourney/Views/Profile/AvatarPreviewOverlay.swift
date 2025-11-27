// Views/Shared/AvatarPreviewOverlay.swift
// Full screen avatar preview with blur background
// Instagram-style: opens FROM avatar position, closes back TO avatar position

import SwiftUI

struct AvatarPreviewOverlay: View {
    let image: UIImage?
    let imageUrl: String?
    let sourceFrame: CGRect
    @Binding var isPresented: Bool
    
    @State private var animationProgress: CGFloat = 0
    
    private let targetSize: CGFloat = 280
    
    var body: some View {
        GeometryReader { geometry in
            let screenCenter = CGPoint(
                x: geometry.size.width / 2,
                y: geometry.size.height / 2
            )
            
            let currentSize = lerp(from: sourceFrame.width, to: targetSize, progress: animationProgress)
            let currentX = lerp(from: sourceFrame.midX, to: screenCenter.x, progress: animationProgress)
            let currentY = lerp(from: sourceFrame.midY, to: screenCenter.y, progress: animationProgress)
            
            ZStack {
                // Blur background
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(animationProgress)
                    .ignoresSafeArea()
                
                // Avatar
                avatarImage(size: currentSize)
                    .position(x: currentX, y: currentY)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                close()
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                animationProgress = 1.0
            }
        }
    }
    
    @ViewBuilder
    private func avatarImage(size: CGFloat) -> some View {
        if let uiImage = image {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if let urlString = imageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                case .failure, .empty:
                    placeholder(size: size)
                @unknown default:
                    placeholder(size: size)
                }
            }
        } else {
            placeholder(size: size)
        }
    }
    
    private func placeholder(size: CGFloat) -> some View {
        Circle()
            .fill(GourneyColors.coralLight)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundColor(GourneyColors.coral)
            )
    }
    
    private func close() {
        withAnimation(.easeOut(duration: 0.25)) {
            animationProgress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isPresented = false
        }
    }
    
    private func lerp(from: CGFloat, to: CGFloat, progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }
}

#Preview {
    ZStack {
        Color.blue.ignoresSafeArea()
        AvatarPreviewOverlay(
            image: nil,
            imageUrl: nil,
            sourceFrame: CGRect(x: 200, y: 300, width: 72, height: 72),
            isPresented: .constant(true)
        )
    }
}
