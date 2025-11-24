// Views/Lists/PopularListsSection.swift
// Horizontal scrolling section for popular lists

import SwiftUI

struct PopularListsSection: View {
    let lists: [PopularList]
    let onListTap: (PopularList) -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                
                Text("Popular Lists")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Horizontal Scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(lists) { list in
                        PopularListCard(list: list)
                            .onTapGesture {
                                onListTap(list)
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 16)
        }
        .background(colorScheme == .dark ? Color(.systemBackground) : Color.white)
    }
}

struct PopularListCard: View {
    let list: PopularList
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Placeholder (no cover photos in lists table)
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.3),
                        Color(red: 0.95, green: 0.3, blue: 0.35).opacity(0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 200, height: 120)
                .overlay {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.5))
                }
            
            // List Info
            VStack(alignment: .leading, spacing: 4) {
                Text(list.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let ownerHandle = list.ownerHandle {
                    Text("@\(ownerHandle)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 8) {
                    // Likes
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                        Text("\(list.likesCount)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    // Places
                    HStack(spacing: 3) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("\(list.itemCount)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 200)
            .padding(.horizontal, 4)
        }
        .frame(width: 200)
        .padding(8)
        .background(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
