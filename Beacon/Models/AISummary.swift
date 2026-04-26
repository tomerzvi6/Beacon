import Foundation

struct AISummary: Identifiable, Hashable, Codable {
    let id: String
    let headline: String
    let summaryText: String
    let keyPoints: [String]
    let recommendation: String?
    let suggestedTasks: [SuggestedTask]

    struct SuggestedTask: Identifiable, Hashable, Codable {
        let id: String
        let title: String
        let detail: String?
    }
}
