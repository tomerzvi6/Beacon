import Foundation

enum SupportReaction: String, CaseIterable, Identifiable {
    case heart
    case hug

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .heart: return "לב"
        case .hug: return "חיבוק"
        }
    }

    var symbol: String {
        switch self {
        case .heart: return "heart.fill"
        case .hug: return "hands.sparkles.fill"
        }
    }
}
