//
//  SearchFilters.swift
//  gourney
//
//  ✅ Compact filter popup with modern iOS design
//  ✅ Smaller buttons and fonts for better mobile UX
//  ✅ Spring animations, haptic feedback
//  ✅ No handle bar - cleaner look
//  ✅ More horizontal padding for comfortable touch targets

import SwiftUI

// MARK: - Filter Model

struct SearchFilters: Equatable {
    enum PlaceType: String, CaseIterable, Identifiable {
        case all = "filter.place_type.all"
        case visited = "filter.place_type.visited"
        case new = "filter.place_type.new"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .visited: return "checkmark.circle"
            case .new: return "sparkles"
            }
        }
    }
    
    enum MinRating: String, CaseIterable, Identifiable {
        case any = "filter.rating.any"
        case threeUp = "filter.rating.3up"
        case fourUp = "filter.rating.4up"
        
        var id: String { rawValue }
        
        var minValue: Double? {
            switch self {
            case .any: return nil
            case .threeUp: return 3.0
            case .fourUp: return 4.0
            }
        }
        
        var displayStars: Int {
            switch self {
            case .any: return 0
            case .threeUp: return 3
            case .fourUp: return 4
            }
        }
    }
    
    var placeType: PlaceType = .all
    var minRating: MinRating = .any
    
    var isActive: Bool {
        placeType != .all || minRating != .any
    }
    
    var activeCount: Int {
        var count = 0
        if placeType != .all { count += 1 }
        if minRating != .any { count += 1 }
        return count
    }
    
    static let `default` = SearchFilters()
}

// MARK: - Filter Popup View (Compact Design)

struct SearchFilterPopup: View {
    @Binding var isPresented: Bool
    @Binding var filters: SearchFilters
    var onApply: () -> Void
    
    @State private var tempFilters: SearchFilters = .default
    @State private var appearAnimation = false
    @Environment(\.colorScheme) private var colorScheme
    
    // Gourney theme
    private let coralGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.3)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(.systemGray6) : .white
    }
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(appearAnimation ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismissPopup() }
            
            // Card - Compact design, no handle bar
            VStack(spacing: 0) {
                // Header (compact)
                headerSection
                
                // Content (compact spacing)
                VStack(spacing: 16) {
                    placeTypeSection
                    ratingSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 16)
                
                // Actions (compact)
                actionButtons
            }
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
            .padding(.horizontal, 32)
            .scaleEffect(appearAnimation ? 1 : 0.92)
            .opacity(appearAnimation ? 1 : 0)
        }
        .onAppear {
            tempFilters = filters
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                appearAnimation = true
            }
        }
    }
    
    // MARK: - Header (Compact)
    
    private var headerSection: some View {
        HStack {
            Text("filter.title")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Button {
                dismissPopup()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            .buttonStyle(CompactScaleButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
    
    // MARK: - Place Type Section (Compact)
    
    private var placeTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("filter.place_type.title")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            
            HStack(spacing: 6) {
                ForEach(SearchFilters.PlaceType.allCases) { type in
                    CompactFilterChip(
                        title: LocalizedStringKey(type.rawValue),
                        icon: type.icon,
                        isSelected: tempFilters.placeType == type
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            tempFilters.placeType = type
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
        }
    }
    
    // MARK: - Rating Section (Compact)
    
    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("filter.rating.title")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            
            HStack(spacing: 6) {
                ForEach(SearchFilters.MinRating.allCases) { rating in
                    CompactRatingChip(
                        rating: rating,
                        isSelected: tempFilters.minRating == rating
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            tempFilters.minRating = rating
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
        }
    }
    
    // MARK: - Action Buttons (Compact)
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Reset button (text only, no background)
            Button {
                resetFilters()
            } label: {
                Text("filter.reset")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tempFilters.isActive ? Color(red: 1.0, green: 0.4, blue: 0.4) : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
            }
            .buttonStyle(CompactScaleButtonStyle())
            .disabled(!tempFilters.isActive)
            .opacity(tempFilters.isActive ? 1.0 : 0.5)
            
            // Apply button (primary)
            Button {
                applyFilters()
            } label: {
                HStack(spacing: 4) {
                    Text("filter.apply")
                        .font(.system(size: 14, weight: .semibold))
                    
                    if tempFilters.activeCount > 0 {
                        Text("(\(tempFilters.activeCount))")
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.85)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(coralGradient)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(CompactScaleButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
    
    // MARK: - Actions
    
    private func dismissPopup() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            appearAnimation = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
    
    private func applyFilters() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        filters = tempFilters
        onApply()
        dismissPopup()
    }
    
    private func resetFilters() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            tempFilters = .default
        }
    }
}

// MARK: - Compact Filter Chip

private struct CompactFilterChip: View {
    let title: LocalizedStringKey
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var selectedGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if isSelected {
                        selectedGradient
                    } else {
                        colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color(.systemGray4).opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(CompactScaleButtonStyle())
    }
}

// MARK: - Compact Rating Chip

private struct CompactRatingChip: View {
    let rating: SearchFilters.MinRating
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var selectedGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.95, green: 0.3, blue: 0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if rating.displayStars > 0 {
                    Text("\(rating.displayStars)")
                        .font(.system(size: 12, weight: .semibold))
                    
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                    
                    Text("+")
                        .font(.system(size: 10, weight: .medium))
                } else {
                    Text(LocalizedStringKey(rating.rawValue))
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if isSelected {
                        selectedGradient
                    } else {
                        colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color(.systemGray4).opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(CompactScaleButtonStyle())
    }
}

// MARK: - Compact Scale Button Style

private struct CompactScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Filter Popup - Light") {
    ZStack {
        Color.gray.opacity(0.3).ignoresSafeArea()
        
        SearchFilterPopup(
            isPresented: .constant(true),
            filters: .constant(.default),
            onApply: {}
        )
    }
}

#Preview("Filter Popup - Dark") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        SearchFilterPopup(
            isPresented: .constant(true),
            filters: .constant(.default),
            onApply: {}
        )
    }
    .preferredColorScheme(.dark)
}
