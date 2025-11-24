// Views/Rank/RankView.swift
// ✅ SIMPLIFIED: Home/Current/Global dropdown + Timeframe picker

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
                // Custom Navigation Bar (matching ListsView)
                customNavBar
                
                // Timeframe Filter
                timeframeFilter
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                
                // Content
                if viewModel.isLoading && viewModel.entries.isEmpty {
                    Spacer()
                    ProgressView()
                        .tint(Color(red: 1.0, green: 0.4, blue: 0.4))
                    Spacer()
                } else {
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
                }
            }
            
            // Location Dropdown Overlay
            if showLocationDropdown {
                LocationDropdownOverlay(
                    selectedScope: $viewModel.selectedScope,
                    homeCity: viewModel.homeCity,
                    homeCountry: viewModel.homeCountry,
                    currentCity: viewModel.currentCity,
                    currentCountry: viewModel.currentCountry,
                    isPresented: $showLocationDropdown,
                    onSelect: {
                        viewModel.clearMemory()
                        Task {
                            await viewModel.loadLeaderboard()
                        }
                    }
                )
            }
        }
        .task {
            // Wait for location to be determined before loading
            if viewModel.entries.isEmpty && !viewModel.isLoading {
                // Give time for reverse geocoding
                try? await Task.sleep(nanoseconds: 500_000_000)
                if viewModel.currentCity != nil || viewModel.homeCity != nil || viewModel.selectedScope == .global {
                    await viewModel.loadLeaderboard()
                }
            }
        }
    }
    
    // MARK: - Custom Navigation Bar (matching ListsView)
    
    private var customNavBar: some View {
        HStack {
            // Title - Left aligned (matching ListsView)
            Text("Leaderboard")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.primary)
            
            Spacer()
            
            // Location Selector Button - no background
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
            viewModel.clearMemory()
            Task {
                await viewModel.loadLeaderboard()
            }
        }
    }
    
    // MARK: - Leaderboard Content
    
    private var leaderboardContent: some View {
        LazyVStack(spacing: 0) {
            // My Rank Card (if available and not in top list)
            if let myRank = viewModel.userRank,
               let rank = myRank.rank,
               rank > 3,
               !viewModel.entries.contains(where: { $0.rank == rank }) {
                myRankCard(myRank)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
            
            // Top 3 Podium
            if viewModel.entries.count >= 3 {
                podiumView
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
            
            // Rest of the list
            ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                if entry.rank > 3 {
                    LeaderboardRow(entry: entry, currentUserId: AuthManager.shared.currentUser?.id)
                        .onAppear {
                            // Load more when reaching end
                            if index == viewModel.entries.count - 5 {
                                Task {
                                    await viewModel.loadLeaderboard(loadMore: true)
                                }
                            }
                        }
                }
            }
            
            // Loading more indicator
            if viewModel.isLoadingMore {
                ProgressView()
                    .tint(Color(red: 1.0, green: 0.4, blue: 0.4))
                    .padding()
            }
        }
    }
    
    // MARK: - Podium View
    
    private var podiumView: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // 2nd Place
            if viewModel.entries.count > 1 {
                PodiumCard(entry: viewModel.entries[1], position: 2)
            }
            
            // 1st Place
            if viewModel.entries.count > 0 {
                PodiumCard(entry: viewModel.entries[0], position: 1)
            }
            
            // 3rd Place
            if viewModel.entries.count > 2 {
                PodiumCard(entry: viewModel.entries[2], position: 3)
            }
        }
    }
    
    // MARK: - My Rank Card
    
    private func myRankCard(_ rank: UserRank) -> some View {
        HStack(spacing: 12) {
            Text("#\(rank.rank ?? 0)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
            
            Text("Your Rank")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(pointsText(for: rank))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.1))
        )
    }
    
    private func pointsText(for rank: UserRank) -> String {
        switch viewModel.selectedTimeframe {
        case .weekly:
            return "\(rank.weeklyPoints) pts"
        case .monthly:
            return "\(rank.monthlyPoints ?? 0) pts"
        case .allTime:
            return "\(rank.lifetimePoints) pts"
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
                Task {
                    await viewModel.loadLeaderboard()
                }
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
        case .home:
            return "No one in your home city has earned points yet. Be the first!"
        case .current:
            return "No one in your current city has earned points yet. Be the first!"
        case .global:
            return "Be the first to earn points and claim the top spot!"
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
                    withAnimation(.easeOut(duration: 0.2)) {
                        isPresented = false
                    }
                }
            
            VStack(spacing: 0) {
                // Home Option
                if homeCity != nil {
                    LocationOption(
                        icon: "house.fill",
                        title: "Home",
                        subtitle: formatLocation(city: homeCity, country: homeCountry),
                        isSelected: selectedScope == .home,
                        action: {
                            selectedScope = .home
                            dismissAndSelect()
                        }
                    )
                }
                
                // Current Option
                if currentCity != nil {
                    if homeCity != nil {
                        Divider().padding(.leading, 16)
                    }
                    
                    LocationOption(
                        icon: "location.fill",
                        title: "Current",
                        subtitle: formatLocation(city: currentCity, country: currentCountry),
                        isSelected: selectedScope == .current,
                        action: {
                            selectedScope = .current
                            dismissAndSelect()
                        }
                    )
                }
                
                // Global Option
                if homeCity != nil || currentCity != nil {
                    Divider().padding(.leading, 16)
                }
                
                LocationOption(
                    icon: "globe.americas.fill",
                    title: "Global",
                    subtitle: "Worldwide rankings",
                    isSelected: selectedScope == .global,
                    action: {
                        selectedScope = .global
                        dismissAndSelect()
                    }
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
        if let country = country {
            return "\(city), \(country)"
        }
        return city
    }
    
    private func dismissAndSelect() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onSelect()
        }
    }
}

// MARK: - Location Option Row

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
    
    private var podiumHeight: CGFloat {
        switch position {
        case 1: return 100
        case 2: return 80
        case 3: return 60
        default: return 60
        }
    }
    
    private var medalColor: Color {
        switch position {
        case 1: return Color.yellow
        case 2: return Color.gray
        case 3: return Color.orange
        default: return Color.gray
        }
    }
    
    private var medalEmoji: String {
        switch position {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return ""
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.2))
                    .frame(width: position == 1 ? 64 : 52, height: position == 1 ? 64 : 52)
                
                if let avatarUrl = entry.avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    }
                    .frame(width: position == 1 ? 60 : 48, height: position == 1 ? 60 : 48)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: position == 1 ? 28 : 22))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                }
            }
            
            // Medal
            Text(medalEmoji)
                .font(.system(size: 24))
            
            // Name
            Text(entry.displayName ?? entry.handle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            // Handle
            Text("@\(entry.handle)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            // Points
            Text("\(entry.lifetimePoints) pts")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(colorScheme == .dark ? .systemGray6 : .systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
    }
    
    @Environment(\.colorScheme) private var colorScheme
}

// MARK: - Leaderboard Row

struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let currentUserId: String?
    @Environment(\.colorScheme) private var colorScheme
    
    private var isCurrentUser: Bool {
        entry.userId == currentUserId
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Rank
            Text("#\(entry.rank)")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)
            
            // Avatar
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.2))
                    .frame(width: 44, height: 44)
                
                if let avatarUrl = entry.avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                }
            }
            
            // Name & Handle
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
            
            // Points
            Text("\(entry.lifetimePoints) pts")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            isCurrentUser ?
            Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.08) :
            Color.clear
        )
    }
}

#Preview {
    RankView()
}
