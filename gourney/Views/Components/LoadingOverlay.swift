// Views/Components/LoadingOverlay.swift
// Shared loading overlay component for consistent UX across the app

import SwiftUI

struct LoadingOverlay: View {
    let message: String
    
    init(message: String = "Loading...") {
        self.message = message
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text(message)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

// MARK: - View Extension for Easy Usage

extension View {
    func loadingOverlay(isShowing: Bool, message: String = "Loading...") -> some View {
        ZStack {
            self
            if isShowing {
                LoadingOverlay(message: message)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray
        Text("Content Behind")
    }
    .loadingOverlay(isShowing: true, message: "Saving changes...")
}
