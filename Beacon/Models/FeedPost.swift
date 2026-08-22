import Foundation
import SwiftData

enum FeedPostStatus: String, Codable, CaseIterable, Hashable {
    case stable
    case needsRest
    case improving
    case concerned

    var displayLabel: String {
        switch self {
        case .stable: return "מצב יציב"
        case .needsRest: return "זקוקים למנוחה"
        case .improving: return "משתפרים"
        case .concerned: return "מודאגים"
        }
    }
}

enum FeedPostAudience: String, Codable {
    case familyOnly
    case innerCircle
}

@Model
final class FeedPost {
    @Attribute(.unique) var id: String
    var authorMemberId: String
    var body: String
    var statusRaw: String?
    var postedAt: Date
    var heartCount: Int
    var hugCount: Int
    var audienceRaw: String
    /// The real backend author — the server always attributes authorship to
    /// the caller's own token, even when `authorMemberId` above is
    /// overridden to the patient for "post as patient" display. nil for
    /// posts synced before this field existed. Used only to show "פורסם על
    /// ידי X" when the two differ.
    var trueAuthorMemberId: String?
    /// Reaction types (SupportReaction.rawValue) the signed-in user has
    /// already given this post, from the backend's per-viewer `my_reactions`
    /// — lets the reaction bar show an active state instead of a bare
    /// counter that never reflects "did my tap register."
    var myReactionsRaw: [String] = []

    @Relationship(deleteRule: .cascade) var comments: [FeedComment] = []

    var status: FeedPostStatus? {
        get { statusRaw.flatMap(FeedPostStatus.init(rawValue:)) }
        set { statusRaw = newValue?.rawValue }
    }

    var audience: FeedPostAudience {
        get { FeedPostAudience(rawValue: audienceRaw) ?? .familyOnly }
        set { audienceRaw = newValue.rawValue }
    }

    var author: FamilyMember? { FamilyMember.find(id: authorMemberId) }
    var trueAuthor: FamilyMember? { trueAuthorMemberId.flatMap(FamilyMember.find(id:)) }

    init(
        id: String = UUID().uuidString,
        authorMemberId: String,
        body: String,
        status: FeedPostStatus? = nil,
        postedAt: Date = .now,
        heartCount: Int = 0,
        hugCount: Int = 0,
        audience: FeedPostAudience = .familyOnly,
        trueAuthorMemberId: String? = nil,
        myReactionsRaw: [String] = [],
        comments: [FeedComment] = []
    ) {
        self.id = id
        self.authorMemberId = authorMemberId
        self.body = body
        self.statusRaw = status?.rawValue
        self.postedAt = postedAt
        self.heartCount = heartCount
        self.hugCount = hugCount
        self.audienceRaw = audience.rawValue
        self.trueAuthorMemberId = trueAuthorMemberId
        self.myReactionsRaw = myReactionsRaw
        self.comments = comments
    }
}

@Model
final class FeedComment {
    @Attribute(.unique) var id: String
    var authorMemberId: String
    var body: String
    var postedAt: Date

    var author: FamilyMember? { FamilyMember.find(id: authorMemberId) }

    init(
        id: String = UUID().uuidString,
        authorMemberId: String,
        body: String,
        postedAt: Date = .now
    ) {
        self.id = id
        self.authorMemberId = authorMemberId
        self.body = body
        self.postedAt = postedAt
    }
}
