// Views/Shared/PlaceholderViews.swift
// Reusable empty, error, and loading state components
// Gourney design system - coral theme

import SwiftUI

// MARK: - Empty State View

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    private let coralColor = Color(red: 1.0, green: 0.4, blue: 0.4)
    
    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: 70))
                .foregroundColor(coralColor.opacity(0.5))
            
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            Text(message)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [coralColor, Color(red: 0.95, green: 0.3, blue: 0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(25)
                }
                .padding(.top, 10)
            }
            
            Spacer()
        }
    }
}

// MARK: - Error State View

struct ErrorStateView: View {
    let title: String
    let message: String
    let retryAction: (() -> Void)?
    
    private let coralColor = Color(red: 1.0, green: 0.4, blue: 0.4)
    
    init(
        title: String = "Something went wrong",
        message: String,
        retryAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.retryAction = retryAction
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if let retryAction = retryAction {
                Button(action: retryAction) {
                    Text("Try Again")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(coralColor)
                }
                .padding(.top, 8)
            }
            
            Spacer()
        }
    }
}

// MARK: - Loading State View

struct LoadingStateView: View {
    let message: String?
    
    private let coralColor = Color(red: 1.0, green: 0.4, blue: 0.4)
    
    init(message: String? = nil) {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: coralColor))
                .scaleEffect(1.2)
            
            if let message = message {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - All Caught Up View

struct AllCaughtUpView: View {
    let message: String
    
    private let coralColor = Color(red: 1.0, green: 0.4, blue: 0.4)
    
    init(message: String = "You've seen all new posts from the last 3 days.") {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundColor(coralColor)
            
            Text("You're all caught up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }
}

// MARK: - No Results View

struct NoResultsView: View {
    let searchTerm: String?
    let message: String?
    
    init(searchTerm: String? = nil, message: String? = nil) {
        self.searchTerm = searchTerm
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.secondary.opacity(0.5))
            
            if let term = searchTerm, !term.isEmpty {
                Text("No results for \"\(term)\"")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
            } else {
                Text("No results found")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Text(message ?? "Try adjusting your search or filters")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
}

// MARK: - Skeleton Loading Views

struct SkeletonBox: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    
    @State private var isAnimating = false
    
    init(width: CGFloat? = nil, height: CGFloat, cornerRadius: CGFloat = 4) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .frame(width: width, height: height)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Color.white.opacity(0.4), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: isAnimating ? 300 : -300)
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

struct SkeletonCircle: View {
    let size: CGFloat
    
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(Color(.systemGray5))
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Color.white.opacity(0.4), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: isAnimating ? size : -size)
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Previews

#Preview("Empty State") {
    EmptyStateView(
        icon: "fork.knife.circle",
        title: "Welcome to Gourney!",
        message: "Follow friends to see their restaurant visits, or discover new places from the community.",
        actionTitle: "Find Friends",
        action: {}
    )
}

#Preview("Error State") {
    ErrorStateView(
        message: "Unable to load data. Please check your connection.",
        retryAction: {}
    )
}

#Preview("Loading State") {
    LoadingStateView(message: "")
}

#Preview("All Caught Up") {
    AllCaughtUpView()
}

#Preview("No Results") {
    NoResultsView(searchTerm: "sushi")
}
