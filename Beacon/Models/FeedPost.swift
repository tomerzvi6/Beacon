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

    init(
        id: String = UUID().uuidString,
        authorMemberId: String,
        body: String,
        status: FeedPostStatus? = nil,
        postedAt: Date = .now,
        heartCount: Int = 0,
        hugCount: Int = 0,
        audience: FeedPostAudience = .familyOnly,
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
