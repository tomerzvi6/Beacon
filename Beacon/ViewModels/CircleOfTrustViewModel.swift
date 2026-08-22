import Foundation
import Observation
import SwiftData

@Observable
final class CircleOfTrustViewModel {
    private let context: ModelContext
    private let environment: AppEnvironment
    private let feedService: FeedService

    var posts: [FeedPost] = []
    var composerText: String = ""
    var composerStatus: FeedPostStatus? = nil
    var composerAsPatient: Bool = false
    var isSyncing: Bool = false

    init(context: ModelContext, environment: AppEnvironment, feedService: FeedService = FeedService()) {
        self.context = context
        self.environment = environment
        self.feedService = feedService
        refresh()
    }

    var canCompose: Bool { environment.canWrite(.feed) }

    /// Fast local read — instant UI on appear, no network wait.
    func refresh() {
        let descriptor = FetchDescriptor<FeedPost>(
            sortBy: [SortDescriptor(\.postedAt, order: .reverse)]
        )
        posts = (try? context.fetch(descriptor)) ?? []
    }

    /// Pulls the feed from the backend and reconciles it into local
    /// SwiftData (upsert by id, drop backend-known ids no longer returned).
    @MainActor
    func syncWithBackend() async {
        isSyncing = true
        defer { isSyncing = false }
        async let membersTask: Void = environment.refreshFamilyMembers()
        let dtos = (try? await feedService.list()) ?? []
        _ = await membersTask

        let fetchedIds = Set(dtos.map { $0.id.uuidString })
        for dto in dtos { upsertLocalPost(from: dto) }
        let allLocal = (try? context.fetch(FetchDescriptor<FeedPost>())) ?? []
        for local in allLocal where UUID(uuidString: local.id) != nil && !fetchedIds.contains(local.id) {
            context.delete(local)
        }
        try? context.save()
        refresh()
    }

    @discardableResult
    private func upsertLocalPost(from dto: FeedService.PostDTO) -> FeedPost {
        let targetId = dto.id.uuidString
        let predicate = #Predicate<FeedPost> { $0.id == targetId }
        let post = (try? context.fetch(FetchDescriptor<FeedPost>(predicate: predicate)))?.first
            ?? {
                let created = FeedPost(id: targetId, authorMemberId: dto.authorUserId.uuidString, body: dto.body)
                context.insert(created)
                return created
            }()
        post.authorMemberId = dto.authorUserId.uuidString
        post.trueAuthorMemberId = dto.authorUserId.uuidString
        post.body = dto.body
        post.status = dto.status.flatMap(FeedPostStatus.init(rawValue:))
        post.postedAt = dto.postedAt
        post.heartCount = dto.heartCount
        post.hugCount = dto.hugCount
        post.audience = FeedPostAudience(rawValue: dto.audience) ?? .familyOnly
        post.myReactionsRaw = dto.myReactions

        let fetchedCommentIds = Set(dto.comments.map { $0.id.uuidString })
        post.comments.removeAll { UUID(uuidString: $0.id) != nil && !fetchedCommentIds.contains($0.id) }
        for commentDTO in dto.comments {
            let commentId = commentDTO.id.uuidString
            if let existing = post.comments.first(where: { $0.id == commentId }) {
                existing.body = commentDTO.body
                existing.postedAt = commentDTO.postedAt
            } else {
                post.comments.append(FeedComment(
                    id: commentId,
                    authorMemberId: commentDTO.authorUserId.uuidString,
                    body: commentDTO.body,
                    postedAt: commentDTO.postedAt
                ))
            }
        }
        return post
    }

    @MainActor
    func publishComposer() async {
        let body = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let shouldPublishAsPatient = composerAsPatient && environment.currentUser.hasFullAccess

        guard let dto = try? await feedService.createPost(
            body: body, status: composerStatus?.rawValue, audience: FeedPostAudience.familyOnly.rawValue
        ) else { return }
        let post = upsertLocalPost(from: dto)
        // The backend attributes authorship to the signed-in user; when
        // posting "as patient" on their behalf, mirror that locally too.
        if shouldPublishAsPatient { post.authorMemberId = environment.patient.id }

        try? context.save()
        composerText = ""
        composerStatus = nil
        composerAsPatient = false
        refresh()
    }

    /// Adds the reaction, or removes it if the viewer already gave this
    /// post the same reaction — matches the tap-to-toggle behavior users
    /// already know from WhatsApp/Facebook, instead of a bare counter that
    /// only ever goes up with no sign of the viewer's own state.
    @MainActor
    func toggleReaction(_ reaction: SupportReaction, on post: FeedPost) async {
        guard let id = UUID(uuidString: post.id) else { return }
        let alreadyReacted = post.myReactionsRaw.contains(reaction.rawValue)
        if alreadyReacted {
            if let dto = try? await feedService.removeReaction(postId: id, reaction: reaction.rawValue) {
                upsertLocalPost(from: dto)
            } else {
                switch reaction {
                case .heart: post.heartCount = max(0, post.heartCount - 1)
                case .hug: post.hugCount = max(0, post.hugCount - 1)
                }
                post.myReactionsRaw.removeAll { $0 == reaction.rawValue }
            }
        } else {
            if let dto = try? await feedService.react(postId: id, reaction: reaction.rawValue) {
                upsertLocalPost(from: dto)
            } else {
                switch reaction {
                case .heart: post.heartCount += 1
                case .hug: post.hugCount += 1
                }
                post.myReactionsRaw.append(reaction.rawValue)
            }
        }
        try? context.save()
        refresh()
    }

    @MainActor
    func addComment(_ body: String, to post: FeedPost) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let id = UUID(uuidString: post.id) else { return }
        if let dto = try? await feedService.addComment(postId: id, body: trimmed) {
            upsertLocalPost(from: dto)
        } else {
            post.comments.append(FeedComment(
                authorMemberId: environment.currentUser.id, body: trimmed, postedAt: Date()
            ))
        }
        try? context.save()
        refresh()
    }
}
