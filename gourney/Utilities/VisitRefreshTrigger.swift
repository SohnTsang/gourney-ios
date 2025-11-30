// Utilities/VisitRefreshTrigger.swift
// Simple static flag for cross-view visit refresh
// No ObservableObject - just a simple flag checked on onAppear

import Foundation

@MainActor
enum VisitRefreshTrigger {
    static var needsRefresh = false
    
    static func trigger() {
        needsRefresh = true
    }
    
    static func reset() {
        needsRefresh = false
    }
}
