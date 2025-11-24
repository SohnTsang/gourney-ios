// Views/Rank/RankView.swift
// ✅ Production-grade with Instagram-style avatar loading

import SwiftUI

struct RankView: View {
    @StateObject private var viewModel = RankViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @State private var showLocationDropdown = false
    
    var body: some View {
        ZStack {
            Color(colorScheme == .dark ? .black : .white)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                customNavBar
                
                timeframeFilter
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                
                if viewModel.isLoading && viewModel.entries.isEmpty {
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
                        
                        // Always visible rank card
                        fixedMyRankCard
                    }
                }
            }
            
            if showLocationDropdown {
                LocationDropdownOverlay(
                    selectedScope: $viewModel.selectedScope,
                    homeCity: viewModel.homeCity,
                    homeCountry: viewModel.homeCountry,
                    currentCity: viewModel.currentCity,
                    currentCountry: viewModel.currentCountry,
                    isPresented: $showLocationDropdown,
                    onSelect: {
                        viewModel.clearAndReload()
                    }
                )
            }
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .task {
            if viewModel.entries.isEmpty && !viewModel.isLoading {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if viewModel.currentCity != nil || viewModel.homeCity != nil || viewModel.selectedScope == .global {
                    await viewModel.loadLeaderboard()
                }
            }
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showLocationDropdown.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.displayLocationIcon)
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text(viewModel.displayLocationText)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(showLocationDropdown ? 180 : 0))
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
                    Text("N/A")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.gray)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Rank")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(hasRank ? .secondary : .secondary.opacity(0.6))
                
                Text(scopeLabel)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            
            Spacer()
            
            Text("\(points) pts")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(hasRank ? Color(red: 1.0, green: 0.4, blue: 0.4) : .gray)
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
        guard let rank = viewModel.userRank else { return 0 }
        switch viewModel.selectedTimeframe {
        case .weekly: return rank.weeklyPoints
        case .monthly: return rank.monthlyPoints ?? 0
        case .allTime: return rank.lifetimePoints
        }
    }
    
    private var scopeLabel: String {
        switch viewModel.selectedScope {
        case .home: return "in \(viewModel.homeCity ?? "Home")"
        case .current: return "in \(viewModel.currentCity ?? "Current")"
        case .global: return "Worldwide"
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text(error)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                Task { await viewModel.loadLeaderboard() }
            } label: {
                Text("Retry")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 140, height: 44)
                    .background(Color(red: 1.0, green: 0.4, blue: 0.4))
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: UIScreen.main.bounds.height * 0.5)
    }
    
    // MARK: - Empty View
    
    private var emptyView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "trophy")
                .font(.system(size: 64))
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3))
            VStack(spacing: 8) {
                Text("No rankings yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                Text(emptyStateSubtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: UIScreen.main.bounds.height * 0.5)
    }
    
    private var emptyStateSubtitle: String {
        switch viewModel.selectedScope {
        case .home: return "No one in your home city has earned points yet. Be the first!"
        case .current: return "No one in your current city has earned points yet. Be the first!"
        case .global: return "Be the first to earn points and claim the top spot!"
        }
    }
}

// MARK: - Location Dropdown Overlay

struct LocationDropdownOverlay: View {
    @Binding var selectedScope: LocationScope
    let homeCity: String?
    let homeCountry: String?
    let currentCity: String?
    let currentCountry: String?
    @Binding var isPresented: Bool
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
                }
            
            VStack(spacing: 0) {
                if homeCity != nil {
                    LocationOption(
                        icon: "house.fill",
                        title: "Home",
                        subtitle: formatLocation(city: homeCity, country: homeCountry),
                        isSelected: selectedScope == .home,
                        action: { selectedScope = .home; dismissAndSelect() }
                    )
                }
                
                if currentCity != nil {
                    if homeCity != nil { Divider().padding(.leading, 16) }
                    LocationOption(
                        icon: "location.fill",
                        title: "Current",
                        subtitle: formatLocation(city: currentCity, country: currentCountry),
                        isSelected: selectedScope == .current,
                        action: { selectedScope = .current; dismissAndSelect() }
                    )
                }
                
                if homeCity != nil || currentCity != nil { Divider().padding(.leading, 16) }
                
                LocationOption(
                    icon: "globe.americas.fill",
                    title: "Global",
                    subtitle: "Worldwide rankings",
                    isSelected: selectedScope == .global,
                    action: { selectedScope = .global; dismissAndSelect() }
                )
            }
            .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .frame(width: 240)
            .padding(.trailing, 20)
            .padding(.top, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
        }
    }
    
    private func formatLocation(city: String?, country: String?) -> String {
        guard let city = city else { return "Not set" }
        return country != nil ? "\(city), \(country!)" : city
    }
    
    private func dismissAndSelect() {
        withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { onSelect() }
    }
}

// MARK: - Location Option

struct LocationOption: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? Color(red: 1.0, green: 0.4, blue: 0.4) : .secondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Podium Card

struct PodiumCard: View {
    let entry: LeaderboardEntry
    let position: Int
    var selectedTimeframe: RankTimeframe = .allTime
    var currentUserId: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    
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
}

// MARK: - Leaderboard Row

struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let currentUserId: String?
    var selectedTimeframe: RankTimeframe = .allTime
    @Environment(\.colorScheme) private var colorScheme
    
    private var isCurrentUser: Bool { entry.userId == currentUserId }
    
    private var displayPoints: Int {
        switch selectedTimeframe {
        case .weekly: return entry.weeklyPoints
        case .monthly: return entry.monthlyPoints ?? 0
        case .allTime: return entry.lifetimePoints
        }
    }
    
    var body: some View {
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
