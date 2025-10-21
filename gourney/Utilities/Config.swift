//
//  Config.swift
//  gourney
//
//  Created by 曾家浩 on 2025/10/16.
//

// Utilities/Config.swift
// Week 7 Day 1: Configuration file for Supabase and API keys

import Foundation

enum Config {
    // MARK: - Supabase Configuration
    static let supabaseURL = "https://jelbrfbhwwcosmuckjqm.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImplbGJyZmJod3djb3NtdWNranFtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyMTg4NDAsImV4cCI6MjA3NDc5NDg0MH0.7NXWal1FeZVjWx3u19-ePDhzdRqp-jfde5pi_racKck"
    
    // MARK: - API Configuration
    static let apiVersion = "v1"
    static let acceptLanguageHeader = "Accept-Language"
    
    // MARK: - Environment
    #if DEBUG
    static let isDebug = true
    #else
    static let isDebug = false
    #endif
    
    // MARK: - Rate Limits (from backend)
    static let maxVisitsPerDay = 30
    static let maxPhotosPerVisit = 3
    static let maxCommentLength = 1000
    static let maxListsPerUser = 50
    
    // MARK: - Validation
    static let minHandleLength = 3
    static let maxHandleLength = 20
    static let handleRegex = "^[a-z0-9_]{3,20}$"
    
    static let reservedHandles = [
        "admin", "api", "app", "help", "support", "settings",
        "about", "terms", "privacy", "feed", "discover", "explore",
        "trending", "popular", "new", "profile", "user", "users",
        "visit", "visits", "list", "lists", "place", "places",
        "auth", "login", "signup", "signout", "register"
    ]
}
