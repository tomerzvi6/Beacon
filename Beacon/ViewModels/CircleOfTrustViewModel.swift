import Foundation
import Observation
import SwiftData

@Observable
final class CircleOfTrustViewModel {
    private let context: ModelContext
    private let environment: AppEnvironment

    var posts: [FeedPost] = []
    var composerText: String = ""
    var composerStatus: FeedPostStatus? = nil
    var composerAsPatient: Bool = false

    init(context: ModelContext, environment: AppEnvironment) {
        self.context = context
        self.environment = environment
        refresh()
    }

    var canCompose: Bool { environment.currentUser.isAdmin }

    func refresh() {
        let descriptor = FetchDescriptor<FeedPost>(
            sortBy: [SortDescriptor(\.postedAt, order: .reverse)]
        )
        posts = (try? context.fetch(descriptor)) ?? []
    }

    func publishComposer() {
        let body = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let displayBody = composerAsPatient
            ? "\"\(body)\"\n— \(environment.patient.displayName)"
            : body
        let post = FeedPost(
            authorMemberId: environment.currentUser.id,
            body: displayBody,
            status: composerStatus,
            postedAt: Date(),
            audience: .familyOnly
        )
        context.insert(post)
        try? context.save()
        composerText = ""
        composerStatus = nil
        composerAsPatient = false
        refresh()
    }

    func incrementReaction(_ reaction: SupportReaction, on post: FeedPost) {
        switch reaction {
        case .heart: post.heartCount += 1
        case .hug: post.hugCount += 1
        }
        try? context.save()
        refresh()
    }

    func addComment(_ body: String, to post: FeedPost) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let comment = FeedComment(
            authorMemberId: environment.currentUser.id,
            body: trimmed,
            postedAt: Date()
        )
        post.comments.append(comment)
        try? context.save()
        refresh()
    }
}
