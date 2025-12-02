// Views/Rank/RankView.swift
// ✅ Production-grade with Instagram-style avatar loading
// ✅ Fixed: Seamless tab switching with proper loading states
// ✅ Updated: Location selector now uses slide-up sheet (same as ListDetailView)
// Avatar taps now navigate via NavigationCoordinator

import SwiftUI

struct RankView: View {
    @StateObject private var viewModel = RankViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @State private var showLocationSheet = false
    
    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                customNavBar
                
                timeframeFilter
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                
                // ✅ Show loading spinner whenever isLoading is true
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .tint(Color(red: 1.0, green: 0.4, blue: 0.4))
                    Spacer()
                } else {
                    ZStack(alignment: .bottom) {
                        ScrollView {
                            VStack(spacing: 16) {
                                if let error = viewModel.errorMessage {
                                    errorView(error)
                                } else if viewModel.entries.isEmpty {
                                    emptyView
                                } else {
                                    leaderboardContent
                                }
                            }
                            .padding(.top, 8)
                        }
                        .refreshable {
                            await viewModel.loadLeaderboard()
                        }
                        
                        // Show rank card when we have data
                        if !viewModel.entries.isEmpty {
                            fixedMyRankCard
                        }
                    }
                }
            }
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .sheet(isPresented: $showLocationSheet) {
            LocationMenuSheet(
                selectedScope: viewModel.selectedScope,
                homeCity: viewModel.homeCity,
                homeCountry: viewModel.homeCountry,
                currentCity: viewModel.currentCity,
                currentCountry: viewModel.currentCountry,
                canSelectHome: viewModel.canSelectHome,
                canSelectCurrent: viewModel.canSelectCurrent,
                onSelect: { scope in
                    viewModel.selectedScope = scope
                    viewModel.clearAndReload()
                }
            )
        }
    }
    
    // MARK: - Navigation Bar
    
    private var customNavBar: some View {
        HStack {
            Text("Leaderboard")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.primary)
            
            Spacer()
            
            Button {
                showLocationSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.displayLocationIcon)
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text(viewModel.displayLocationText)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    // MARK: - Timeframe Filter
    
    private var timeframeFilter: some View {
        Picker("", selection: $viewModel.selectedTimeframe) {
            ForEach(RankTimeframe.allCases, id: \.self) { timeframe in
                Text(timeframe.localizedTitle).tag(timeframe)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: viewModel.selectedTimeframe) { _, _ in
            viewModel.clearAndReload()
        }
    }
    
    // MARK: - Leaderboard Content
    
    private var leaderboardContent: some View {
        LazyVStack(spacing: 0) {
            if viewModel.entries.count >= 3 {
                podiumView
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                
                Divider().padding(.leading, 16)
                
                ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                    if entry.rank > 3 {
                        LeaderboardRow(
                            entry: entry,
                            currentUserId: AuthManager.shared.currentUser?.id,
                            selectedTimeframe: viewModel.selectedTimeframe
                        )
                        .onAppear {
                            if index == viewModel.entries.count - 5 {
                                Task { await viewModel.loadLeaderboard(loadMore: true) }
                            }
                        }
                        
                        if index < viewModel.entries.count - 1 {
                            Divider().padding(.leading, 72)
                        }
                    }
                }
            } else {
                ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                    LeaderboardRow(
                        entry: entry,
                        currentUserId: AuthManager.shared.currentUser?.id,
                        selectedTimeframe: viewModel.selectedTimeframe
                    )
                    .onAppear {
                        if index == viewModel.entries.count - 5 {
                            Task { await viewModel.loadLeaderboard(loadMore: true) }
                        }
                    }
                    
                    if index < viewModel.entries.count - 1 {
                        Divider().padding(.leading, 72)
                    }
                }
            }
            
            if viewModel.isLoadingMore {
                ProgressView()
                    .tint(Color(red: 1.0, green: 0.4, blue: 0.4))
                    .padding()
            }
            
            Spacer().frame(height: 80)
        }
    }
    
    // MARK: - Podium View
    
    private var podiumView: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if viewModel.entries.count > 1 {
                PodiumCard(entry: viewModel.entries[1], position: 2, selectedTimeframe: viewModel.selectedTimeframe, currentUserId: AuthManager.shared.currentUser?.id)
            }
            if viewModel.entries.count > 0 {
                PodiumCard(entry: viewModel.entries[0], position: 1, selectedTimeframe: viewModel.selectedTimeframe, currentUserId: AuthManager.shared.currentUser?.id)
            }
            if viewModel.entries.count > 2 {
                PodiumCard(entry: viewModel.entries[2], position: 3, selectedTimeframe: viewModel.selectedTimeframe, currentUserId: AuthManager.shared.currentUser?.id)
            }
        }
    }
    
    // MARK: - Fixed My Rank Card (Always Visible)
    
    private var fixedMyRankCard: some View {
        let hasRank = viewModel.userRank?.rank != nil
        let rank = viewModel.userRank?.rank ?? 0
        let points = currentPoints
        
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(hasRank ? Color(red: 1.0, green: 0.4, blue: 0.4) : Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                
                if hasRank {
                    Text("#\(rank)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("—")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Rank")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                
                Text("\(points) points")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            if !hasRank {
                Text("Not ranked yet")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                .shadow(color: .black.opacity(0.1), radius: 8, y: -2)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    private var currentPoints: Int {
        guard let userRank = viewModel.userRank else { return 0 }
        switch viewModel.selectedTimeframe {
        case .weekly: return userRank.weeklyPoints
        case .monthly: return userRank.monthlyPoints ?? 0
        case .allTime: return userRank.lifetimePoints
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text(message)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                viewModel.clearAndReload()
            } label: {
                Text("Retry")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(red: 1.0, green: 0.4, blue: 0.4))
                    )
            }
        }
        .padding(.top, 60)
    }
    
    // MARK: - Empty View
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy")
                .font(.system(size: 48))
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.5))
            
            Text("No rankings yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("Be the first to earn points\nin this area!")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }
}

// MARK: - Location Menu Sheet (Slide up - same pattern as ListDetailMenuSheet)

struct LocationMenuSheet: View {
    let selectedScope: LocationScope
    let homeCity: String?
    let homeCountry: String?
    let currentCity: String?
    let currentCountry: String?
    let canSelectHome: Bool
    let canSelectCurrent: Bool
    let onSelect: (LocationScope) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    private var sheetHeight: CGFloat {
        // Base height for header + 3 options
        180
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color(.systemGray3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 20)
            
            VStack(spacing: 0) {
                // Home option
                locationRow(
                    scope: .home,
                    title: "Home",
                    subtitle: formatLocation(city: homeCity, country: homeCountry),
                    icon: "house.fill",
                    isSelected: selectedScope == .home,
                    isDisabled: !canSelectHome
                )
                
                Divider().padding(.leading, 56)
                
                // Current location option
                locationRow(
                    scope: .current,
                    title: "Current Location",
                    subtitle: formatLocation(city: currentCity, country: currentCountry),
                    icon: "location.fill",
                    isSelected: selectedScope == .current,
                    isDisabled: !canSelectCurrent
                )
                
                Divider().padding(.leading, 56)
                
                // Global option
                locationRow(
                    scope: .global,
                    title: "Global",
                    subtitle: "Worldwide rankings",
                    icon: "globe.americas.fill",
                    isSelected: selectedScope == .global,
                    isDisabled: false
                )
            }
            
            Spacer()
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
    }
    
    private func locationRow(
        scope: LocationScope,
        title: String,
        subtitle: String?,
        icon: String,
        isSelected: Bool,
        isDisabled: Bool
    ) -> some View {
        Button {
            guard !isDisabled else { return }
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onSelect(scope)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isDisabled ? .gray : (isSelected ? Color(red: 1.0, green: 0.4, blue: 0.4) : .primary))
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isDisabled ? .gray : .primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(isDisabled ? .gray.opacity(0.6) : .secondary)
                    } else if isDisabled {
                        Text(scope == .home ? "Set in profile" : "Location unavailable")
                            .font(.system(size: 13))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
    
    private func formatLocation(city: String?, country: String?) -> String? {
        guard let city = city else { return nil }
        return country != nil ? "\(city), \(country!)" : city
    }
}

// MARK: - Podium Card (Tappable for profile navigation)

struct PodiumCard: View {
    let entry: LeaderboardEntry
    let position: Int
    var selectedTimeframe: RankTimeframe = .allTime
    let currentUserId: String?
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var navigator = NavigationCoordinator.shared
    
    private var isCurrentUser: Bool { entry.userId == currentUserId }
    
    private var medalEmoji: String {
        switch position {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return ""
        }
    }
    
    private var displayPoints: Int {
        switch selectedTimeframe {
        case .weekly: return entry.weeklyPoints
        case .monthly: return entry.monthlyPoints ?? 0
        case .allTime: return entry.lifetimePoints
        }
    }
    
    private var avatarSize: CGFloat { position == 1 ? 60 : 48 }
    private var containerSize: CGFloat { position == 1 ? 64 : 52 }
    
    var body: some View {
        Button {
            navigator.showProfile(userId: entry.userId)
        } label: {
            VStack(spacing: 8) {
                // Avatar - Instagram style loading
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(isCurrentUser ? 0.3 : 0.2))
                        .frame(width: containerSize, height: containerSize)
                    
                    if isCurrentUser {
                        Circle()
                            .stroke(Color(red: 1.0, green: 0.4, blue: 0.4), lineWidth: 2)
                            .frame(width: containerSize, height: containerSize)
                    }
                    
                    AvatarImageView(
                        url: entry.avatarUrl,
                        size: avatarSize,
                        placeholder: "person.fill"
                    )
                }
                
                Text(medalEmoji).font(.system(size: 24))
                
                HStack(spacing: 4) {
                    Text(entry.displayName ?? entry.handle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if isCurrentUser {
                        Text("(You)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    }
                }
                
                Text("@\(entry.handle)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text("\(displayPoints) pts")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isCurrentUser ?
                          Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.08) :
                          Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .overlay(
                isCurrentUser ?
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3), lineWidth: 1)
                : nil
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(navigator.canNavigateToProfile(userId: entry.userId))
    }
}

// MARK: - Leaderboard Row (Tappable for profile navigation)

struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let currentUserId: String?
    var selectedTimeframe: RankTimeframe = .allTime
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var navigator = NavigationCoordinator.shared
    
    private var isCurrentUser: Bool { entry.userId == currentUserId }
    
    private var displayPoints: Int {
        switch selectedTimeframe {
        case .weekly: return entry.weeklyPoints
        case .monthly: return entry.monthlyPoints ?? 0
        case .allTime: return entry.lifetimePoints
        }
    }
    
    var body: some View {
        Button {
            navigator.showProfile(userId: entry.userId)
        } label: {
            HStack(spacing: 12) {
                Text("#\(entry.rank)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .leading)
                
                // Avatar - Instagram style
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    AvatarImageView(
                        url: entry.avatarUrl,
                        size: 40,
                        placeholder: "person.fill"
                    )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.displayName ?? entry.handle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        if isCurrentUser {
                            Text("(You)")
                                .font(.system(size: 12))
                                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                        }
                    }
                    
                    Text("@\(entry.handle)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(displayPoints) pts")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isCurrentUser ? Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(navigator.canNavigateToProfile(userId: entry.userId))
    }
}

// MARK: - Avatar Image View (Instagram-style loading)

struct AvatarImageView: View {
    let url: String?
    let size: CGFloat
    let placeholder: String
    
    var body: some View {
        if let urlString = url, let imageUrl = URL(string: urlString) {
            AsyncImage(url: imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                case .failure:
                    placeholderView
                case .empty:
                    // Gray placeholder while loading (Instagram style)
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: size, height: size)
                        .overlay(
                            ProgressView()
                                .tint(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.5))
                                .scaleEffect(0.6)
                        )
                @unknown default:
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }
    
    private var placeholderView: some View {
        Image(systemName: placeholder)
            .font(.system(size: size * 0.45))
            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
            .frame(width: size, height: size)
    }
}

#Preview {
    RankView()
}
