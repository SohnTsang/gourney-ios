// Views/Shared/CustomDeleteAlert.swift
// Custom alert matching Gourney's coral/pink theme

import SwiftUI

struct CustomDeleteAlert: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
            
            // Alert Card - CENTER OF SCREEN
            VStack(spacing: 0) {
                // Title
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                
                // Message
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                
                // Divider
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 0.5)
                
                // Buttons
                HStack(spacing: 0) {
                    // Cancel
                    Button {
                        onCancel()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 17))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    
                    // Divider
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 0.5)
                    
                    // Confirm Delete
                    Button {
                        onConfirm()
                    } label: {
                        Text(confirmTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
            }
            .frame(width: 270)
            .fixedSize(horizontal: false, vertical: true)
            .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.25), radius: 40, x: 0, y: 15)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - View Extension for Easy Use

extension View {
    func customDeleteAlert(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        confirmTitle: String = "Delete",
        onConfirm: @escaping () -> Void
    ) -> some View {
        ZStack {
            self
            
            if isPresented.wrappedValue {
                CustomDeleteAlert(
                    title: title,
                    message: message,
                    confirmTitle: confirmTitle,
                    onConfirm: {
                        onConfirm()
                        isPresented.wrappedValue = false
                    },
                    onCancel: {
                        isPresented.wrappedValue = false
                    }
                )
                .transition(.opacity)
                .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPresented.wrappedValue)
    }
}
