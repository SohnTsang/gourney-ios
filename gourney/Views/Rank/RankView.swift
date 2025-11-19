// Views/Rank/RankView.swift
// Redesigned to match Gourney design system

import SwiftUI

struct RankView: View {
    @StateObject private var viewModel = RankViewModel()
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(colorScheme == .dark ? .black : .systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Scope Tabs
                    scopeTabBar
                        .background(colorScheme == .dark ? Color.black : Color.white)
                    
                    // Content
                    ScrollView {
                        VStack(spacing: 16) {
                            // Filter Bar
                            filterBar
                                .padding(.horizontal)
                                .padding(.top, 16)
                            
                            // Content based on scope
                            if viewModel.isLoading {
                                loadingView
                            } else if let error = viewModel.errorMessage {
                                errorView(error)
                            } else if viewModel.entries.isEmpty {
                                emptyView
                            } else {
                                leaderboardContent
                            }
                        }
                    }
                    .refreshable {
                        await viewModel.loadLeaderboard()
                    }
                }
            }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            if viewModel.entries.isEmpty {
                await viewModel.loadLeaderboard()
            }
        }
        .onDisappear {
            viewModel.clearMemory()
        }
    }
    
    // MARK: - Scope Tab Bar
    
    private var scopeTabBar: some View {
        HStack(spacing: 0) {
            ForEach(RankScope.allCases, id: \.self) { scope in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedScope = scope
                    }
                    Task {
                        await viewModel.loadLeaderboard()
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(scope.localizedTitle)
                            .font(.system(size: 15, weight: viewModel.selectedScope == scope ? .semibold : .medium))
                            .foregroundColor(viewModel.selectedScope == scope ? Color(red: 1.0, green: 0.4, blue: 0.4) : .secondary)
                        
                        Rectangle()
                            .fill(viewModel.selectedScope == scope ? Color(red: 1.0, green: 0.4, blue: 0.4) : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Filter Bar
    
    private var filterBar: some View {
        VStack(spacing: 12) {
            // Timeframe Picker
            Picker("", selection: $viewModel.selectedTimeframe) {
                ForEach(RankTimeframe.allCases, id: \.self) { timeframe in
                    Text(timeframe.localizedTitle).tag(timeframe)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedTimeframe) { _, _ in
                Task {
                    await viewModel.loadLeaderboard()
                }
            }
            
            // City Picker (only for city scope)
            if viewModel.selectedScope == .city {
                Menu {
                    ForEach(viewModel.availableCities, id: \.self) { city in
                        Button {
                            viewModel.selectedCity = city
                            Task {
                                await viewModel.loadLeaderboard()
                            }
                        } label: {
                            HStack {
                                Text(city)
                                if viewModel.selectedCity == city {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "building.2")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        Text(viewModel.selectedCity)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(colorScheme == .dark ? Color(white: 0.15) : Color(.systemGray6))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .background(colorScheme == .dark ? Color(white: 0.1) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Leaderboard Content
    
    private var leaderboardContent: some View {
        VStack(spacing: 0) {
            // User's Rank Card (if not in top 20)
            if let userRank = viewModel.userRank,
               let rank = userRank.rank,
               rank > 20 {
                userRankCard(userRank: userRank)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
            
            // Rankings List
            VStack(spacing: 0) {
                ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                    LeaderboardEntryRow(
                        entry: entry,
                        timeframe: viewModel.selectedTimeframe
                    )
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    
                    if index < viewModel.entries.count - 1 {
                        Divider()
                            .padding(.leading, 80)
                    }
                    
                    // Load more trigger
                    if index == viewModel.entries.count - 5 {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task {
                                    await viewModel.loadLeaderboard(loadMore: true)
                                }
                            }
                    }
                }
                
                // Loading More
                if viewModel.isLoadingMore {
                    ProgressView()
                        .padding()
                }
            }
            .background(colorScheme == .dark ? Color(white: 0.1) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
        }
    }
    
    // MARK: - User Rank Card
    
    private func userRankCard(userRank: UserRank) -> some View {
        HStack(spacing: 16) {
            // Rank Badge
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.15))
                    .frame(width: 52, height: 52)
                
                Text("#\(userRank.rank ?? 0)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Rank")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text(pointsText(userRank))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.1),
                    Color(red: 1.0, green: 0.5, blue: 0.5).opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func pointsText(_ userRank: UserRank) -> String {
        let points = viewModel.selectedTimeframe == .weekly ? userRank.weeklyPoints : userRank.lifetimePoints
        return "\(points) points"
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading rankings...")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
    }
    
    // MARK: - Error View
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
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
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
    }
    
    // MARK: - Empty View
    
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "trophy")
                .font(.system(size: 64))
                .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3))
            
            VStack(spacing: 8) {
                Text("No rankings yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Be the first to earn points!")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
    }
}

// MARK: - Leaderboard Entry Row

struct LeaderboardEntryRow: View {
    let entry: LeaderboardEntry
    let timeframe: RankTimeframe
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 14) {
            // Rank Badge
            Text(rankText)
                .font(entry.rank <= 3 ? .system(size: 24) : .system(size: 16, weight: .bold))
                .foregroundColor(rankColor)
                .frame(width: 48)
            
            // Avatar
            AsyncImage(url: URL(string: entry.avatarUrl ?? "")) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.2))
                    .overlay {
                        Text(String(entry.handle.prefix(1)).uppercased())
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                    }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            
            // User Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("@\(entry.handle)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    if let displayName = entry.displayName, !displayName.isEmpty {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(displayName)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Text(pointsText)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Following Badge
            if entry.isFollowing == true {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
            }
        }
    }
    
    private var rankText: String {
        switch entry.rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "#\(entry.rank)"
        }
    }
    
    private var rankColor: Color {
        switch entry.rank {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return .secondary
        }
    }
    
    private var pointsText: String {
        let points = timeframe == .weekly ? entry.weeklyPoints : entry.lifetimePoints
        return "\(points) points"
    }
}

#Preview {
    RankView()
}
