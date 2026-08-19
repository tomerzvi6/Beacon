import Foundation
import SwiftData

/// Family support feed (פיד) against `/v1/feed/*`.
struct FeedService {
    let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    struct CommentDTO: Decodable, Identifiable {
        let id: UUID
        let authorUserId: UUID
        let body: String
        let postedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case authorUserId = "author_user_id"
            case body
            case postedAt = "posted_at"
        }
    }

    struct PostDTO: Decodable, Identifiable {
        let id: UUID
        let authorUserId: UUID
        let body: String
        let status: String?
        let audience: String
        let postedAt: Date
        let heartCount: Int
        let hugCount: Int
        let myReactions: [String]
        let comments: [CommentDTO]

        enum CodingKeys: String, CodingKey {
            case id
            case authorUserId = "author_user_id"
            case body, status, audience
            case postedAt = "posted_at"
            case heartCount = "heart_count"
            case hugCount = "hug_count"
            case myReactions = "my_reactions"
            case comments
        }
    }

    private struct PostBody: Encodable {
        let body: String
        let status: String?
        let audience: String
    }

    private struct CommentBody: Encodable {
        let body: String
    }

    private struct ReactionBody: Encodable {
        let reaction: String
    }

    func list() async throws -> [PostDTO] {
        try await client.get("/v1/feed/")
    }

    func createPost(body: String, status: String?, audience: String = "family_only") async throws -> PostDTO {
        try await client.post("/v1/feed/", body: PostBody(body: body, status: status, audience: audience))
    }

    func addComment(postId: UUID, body: String) async throws -> PostDTO {
        try await client.post("/v1/feed/\(postId.uuidString)/comments", body: CommentBody(body: body))
    }

    func react(postId: UUID, reaction: String) async throws -> PostDTO {
        try await client.post("/v1/feed/\(postId.uuidString)/react", body: ReactionBody(reaction: reaction))
    }

    /// Posts to the backend feed and inserts the confirmed row into local
    /// SwiftData under the backend-issued id. Used by callers outside
    /// `CircleOfTrustViewModel` (e.g. sharing a caregiver check-in summary)
    /// that don't otherwise touch the feed. `authorOverrideMemberId` lets
    /// the caller attribute the post to someone other than the signed-in
    /// user (e.g. posting "as patient") for local display purposes only —
    /// the backend always attributes authorship to the caller's own token.
    @MainActor
    @discardableResult
    func createPostAndInsert(
        body: String, status: String? = nil, audience: String = "familyOnly",
        authorOverrideMemberId: String? = nil, in context: ModelContext
    ) async -> FeedPost? {
        guard let dto = try? await createPost(body: body, status: status, audience: audience) else {
            return nil
        }
        let post = FeedPost(
            id: dto.id.uuidString,
            authorMemberId: authorOverrideMemberId ?? dto.authorUserId.uuidString,
            body: dto.body,
            status: dto.status.flatMap(FeedPostStatus.init(rawValue:)),
            postedAt: dto.postedAt,
            heartCount: dto.heartCount,
            hugCount: dto.hugCount,
            audience: FeedPostAudience(rawValue: dto.audience) ?? .familyOnly
        )
        context.insert(post)
        try? context.save()
        return post
    }
}
