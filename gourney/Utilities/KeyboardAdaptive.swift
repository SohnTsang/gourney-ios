//
//  KeyboardAdaptive.swift
//  gourney
//
//  Global keyboard behavior: dismiss on tap outside without blocking buttons
//

import SwiftUI

// MARK: - Keyboard Dismissing Overlay

struct KeyboardDismissingModifier: ViewModifier {
    func body(content: Content) -> some View {
            content.simultaneousGesture(
                TapGesture().onEnded { hideKeyboard() }, including: .all
            )
        }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - View Extension

extension View {
    func dismissKeyboardOnTapOutside() -> some View {
        modifier(KeyboardDismissingModifier())
    }
    
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
