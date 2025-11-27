//
//  SettingsView.swift
//  gourney
//
//  Created by 曾家浩 on 2025/11/27.
//


// Views/Profile/SettingsView.swift
// Placeholder settings screen
// TODO: Implement full settings functionality

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background
            backgroundColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Spacer for top bar
                Color.clear.frame(height: 44)
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        // Placeholder content
                        VStack(spacing: 16) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 60))
                                .foregroundColor(GourneyColors.coral.opacity(0.3))
                            
                            Text("Settings")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.primary)
                            
                            Text("Coming soon...")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                        
                        // Sign Out Button (functional)
                        Button {
                            signOut()
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 18))
                                Text("Sign Out")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 40)
                    }
                }
            }
            
            // Fixed Top Bar
            DetailTopBar(
                title: "Settings",
                onBack: { dismiss() }
            )
        }
        .navigationBarHidden(true)
    }
    
    private func signOut() {
        Task {
            await AuthManager.shared.signOut()
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
