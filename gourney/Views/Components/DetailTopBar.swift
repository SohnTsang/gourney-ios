//
//  DetailTopBar.swift
//  gourney
//
//  Created by 曾家浩 on 2025/11/27.
//


// Views/Shared/DetailTopBar.swift
// Reusable top bar for detail screens (FeedDetailView, EditProfileView, etc.)
// Consistent design: back button, centered title, optional right action

import SwiftUI

// MARK: - Detail Top Bar

struct DetailTopBar: View {
    let title: String
    var rightButtonTitle: String? = nil
    var rightButtonIcon: String? = nil
    var rightButtonDisabled: Bool = false
    var rightButtonLoading: Bool = false
    var showRightButton: Bool = false
    var onBack: () -> Void
    var onRightAction: (() -> Void)? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    var body: some View {
        HStack {
            // Left: Back button
            DetailBackButton(action: onBack)
            
            Spacer()
            
            // Center: Title
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
            
            Spacer()
            
            // Right: Action button or spacer
            if showRightButton {
                DetailActionButton(
                    title: rightButtonTitle,
                    icon: rightButtonIcon,
                    isDisabled: rightButtonDisabled,
                    isLoading: rightButtonLoading,
                    action: onRightAction ?? {}
                )
            } else {
                // Invisible spacer to balance the back button
                Color.clear
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(backgroundColor)
    }
}

// MARK: - Detail Back Button

struct DetailBackButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Detail Action Button (Save, Post, etc.)

struct DetailActionButton: View {
    var title: String? = nil
    var icon: String? = nil
    var isDisabled: Bool = false
    var isLoading: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(GourneyColors.coral)
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    if let title = title {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .foregroundColor(isDisabled ? .gray : GourneyColors.coral)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(isDisabled || isLoading)
    }
}

// MARK: - Preview

#Preview("Detail Top Bar - Visit") {
    VStack(spacing: 0) {
        DetailTopBar(
            title: "Visit",
            onBack: {}
        )
        Divider()
        Spacer()
    }
}

#Preview("Detail Top Bar - Edit Profile") {
    VStack(spacing: 0) {
        DetailTopBar(
            title: "Edit Profile",
            rightButtonTitle: "Save",
            showRightButton: true,
            onBack: {},
            onRightAction: {}
        )
        Divider()
        Spacer()
    }
}

#Preview("Detail Top Bar - Loading") {
    VStack(spacing: 0) {
        DetailTopBar(
            title: "Edit Profile",
            rightButtonTitle: "Save",
            rightButtonLoading: true,
            showRightButton: true,
            onBack: {},
            onRightAction: {}
        )
        Divider()
        Spacer()
    }
}