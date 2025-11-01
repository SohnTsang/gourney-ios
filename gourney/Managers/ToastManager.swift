// Managers/ToastManager.swift
// Global toast notification system (Instagram-style)

import SwiftUI
import Combine

@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var toast: Toast?
    
    private init() {}
    
    func show(_ message: String, icon: String = "checkmark.circle.fill", duration: TimeInterval = 2.0) {
        // Dismiss any existing toast
        toast = nil
        
        // Show new toast
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            toast = Toast(message: message, icon: icon)
        }
        
        // Auto-dismiss
        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    self.toast = nil
                }
            }
        }
    }
    
    func showSuccess(_ message: String) {
        show(message, icon: "checkmark.circle.fill")
    }
    
    func showError(_ message: String) {
        show(message, icon: "exclamationmark.circle.fill")
    }
    
    func dismiss() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            toast = nil
        }
    }
}

struct Toast: Identifiable {
    let id = UUID()
    let message: String
    let icon: String
}

// MARK: - Toast View Component

struct ToastView: View {
    let toast: Toast
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            
            Text(toast.message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        )
    }
}

// MARK: - View Modifier

struct ToastModifier: ViewModifier {
    @StateObject private var toastManager = ToastManager.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            // Toast overlay (top of screen)
            if let toast = toastManager.toast {
                VStack {
                    ToastView(toast: toast)
                        .padding(.top, 60)  // Below status bar
                        .transition(.move(edge: .top).combined(with: .opacity))
                    
                    Spacer()
                }
                .zIndex(999)
            }
        }
    }
}

extension View {
    func withToast() -> some View {
        modifier(ToastModifier())
    }
}
