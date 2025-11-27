// Models/Comment.swift
// Comment models for visit comments
// Production-ready with memory optimization

import Foundation

// MARK: - Comments List Response

struct CommentsResponse: Codable {
    let visitId: String
    let comments: [Comment]
    let commentCount: Int
    let nextCursor: String?
}

// MARK: - Comment Model

struct Comment: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let userHandle: String?
    let userDisplayName: String?
    let userAvatarUrl: String?
    let commentText: String
    let createdAt: String
    let editedAt: String?
    var likeCount: Int          // var for optimistic updates
    var isLiked: Bool           // var for optimistic updates
    let isOwnComment: Bool
    
    // Computed: display name or handle
    var displayName: String {
        if let name = userDisplayName, !name.isEmpty {
            return name
        }
        return userHandle ?? "Unknown"
    }
    
    // Computed: was edited
    var isEdited: Bool {
        editedAt != nil
    }
    
    // Computed: time ago string
    var timeAgo: String {
        timeAgoString(from: createdAt)
    }
    
    static func == (lhs: Comment, rhs: Comment) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Comment Like Toggle Response

struct CommentLikeResponse: Codable {
    let commentId: String
    let liked: Bool
    let likeCount: Int
    let createdAt: String?
}

// MARK: - Comment Create Response

struct CommentCreateResponse: Codable {
    let id: String
    let visitId: String
    let userId: String
    let userHandle: String?
    let userDisplayName: String?
    let userAvatarUrl: String?
    let commentText: String
    let createdAt: String
}

// MARK: - Comment Update Response

struct CommentUpdateResponse: Codable {
    let id: String
    let userId: String
    let userHandle: String?
    let userDisplayName: String?
    let userAvatarUrl: String?
    let commentText: String
    let createdAt: String
    let editedAt: String?
}

// MARK: - Extension to convert Create/Update response to Comment

extension CommentCreateResponse {
    func toComment(isOwnComment: Bool = true) -> Comment {
        Comment(
            id: id,
            userId: userId,
            userHandle: userHandle,
            userDisplayName: userDisplayName,
            userAvatarUrl: userAvatarUrl,
            commentText: commentText,
            createdAt: createdAt,
            editedAt: nil,
            likeCount: 0,
            isLiked: false,
            isOwnComment: isOwnComment
        )
    }
}

extension CommentUpdateResponse {
    func toComment(existingComment: Comment) -> Comment {
        Comment(
            id: id,
            userId: userId,
            userHandle: userHandle,
            userDisplayName: userDisplayName,
            userAvatarUrl: userAvatarUrl,
            commentText: commentText,
            createdAt: createdAt,
            editedAt: editedAt,
            likeCount: existingComment.likeCount,
            isLiked: existingComment.isLiked,
            isOwnComment: existingComment.isOwnComment
        )
    }
}
