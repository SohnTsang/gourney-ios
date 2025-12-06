//
//  RelativeTimeFormatter.swift
//  gourney
//
//  Created by 曾家浩 on 2025/12/06.
//


// Utils/RelativeTimeFormatter.swift
// Instagram-style relative time formatting
// Shows "x mins/hours/days ago" for recent, exact date for older

import Foundation

struct RelativeTimeFormatter {
    
    /// Instagram-style relative time
    /// - Recent: "2m", "5h", "3d", "2w"
    /// - Older than ~3 months: "Mar 15" or "Mar 15, 2023" if different year
    static func format(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.minute, .hour, .day, .weekOfYear], from: date, to: now)
        
        // Future dates (shouldn't happen but handle gracefully)
        if date > now {
            return "Just now"
        }
        
        // Less than 1 minute
        if let minutes = components.minute, minutes < 1 {
            return "Just now"
        }
        
        // Minutes (< 60 min)
        if let minutes = components.minute, let hours = components.hour, hours == 0 {
            return "\(minutes)m"
        }
        
        // Hours (< 24 hours)
        if let hours = components.hour, let days = components.day, days == 0 {
            return "\(hours)h"
        }
        
        // Days (< 7 days)
        if let days = components.day, days < 7 {
            return "\(days)d"
        }
        
        // Weeks (< ~12 weeks / 3 months)
        if let weeks = components.weekOfYear, weeks < 12 {
            return "\(weeks)w"
        }
        
        // Older: show date
        let dateFormatter = DateFormatter()
        let dateYear = calendar.component(.year, from: date)
        let currentYear = calendar.component(.year, from: now)
        
        if dateYear == currentYear {
            dateFormatter.dateFormat = "MMM d"  // "Mar 15"
        } else {
            dateFormatter.dateFormat = "MMM d, yyyy"  // "Mar 15, 2023"
        }
        
        return dateFormatter.string(from: date)
    }
    
    /// Parse ISO8601 string and format
    static func format(from isoString: String) -> String {
        // Try with fractional seconds first
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: isoString) {
            return format(date)
        }
        
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: isoString) {
            return format(date)
        }
        
        // Fallback
        return isoString
    }
    
    /// Longer format: "2 minutes ago", "5 hours ago", etc.
    static func formatLong(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.minute, .hour, .day, .weekOfYear, .month], from: date, to: now)
        
        if date > now {
            return "Just now"
        }
        
        if let minutes = components.minute, let hours = components.hour, hours == 0 {
            if minutes < 1 {
                return "Just now"
            } else if minutes == 1 {
                return "1 minute ago"
            } else {
                return "\(minutes) minutes ago"
            }
        }
        
        if let hours = components.hour, let days = components.day, days == 0 {
            if hours == 1 {
                return "1 hour ago"
            } else {
                return "\(hours) hours ago"
            }
        }
        
        if let days = components.day, days < 7 {
            if days == 1 {
                return "1 day ago"
            } else {
                return "\(days) days ago"
            }
        }
        
        if let weeks = components.weekOfYear, weeks < 5 {
            if weeks == 1 {
                return "1 week ago"
            } else {
                return "\(weeks) weeks ago"
            }
        }
        
        // Older: show full date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        return dateFormatter.string(from: date)
    }
    
    /// Parse ISO8601 string and format long
    static func formatLong(from isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: isoString) {
            return formatLong(date)
        }
        
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: isoString) {
            return formatLong(date)
        }
        
        return isoString
    }
}