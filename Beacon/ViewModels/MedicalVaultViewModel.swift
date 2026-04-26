import Foundation
import Observation
import SwiftData

@Observable
final class MedicalVaultViewModel {
    private let context: ModelContext

    var alert: HospitalSyncAlert?
    var documents: [MedicalDocument] = []
    var searchText: String = ""
    var selectedFilter: MedicalDocumentKind = .all
    var lastImportedTaskTitles: [String] = []

    init(context: ModelContext) {
        self.context = context
        refresh()
    }

    var featuredSummary: AISummary { SampleAISummaries.dashboardFeatured }

    var filteredDocuments: [MedicalDocument] {
        var result = documents
        if selectedFilter != .all {
            result = result.filter { $0.kind == selectedFilter }
        }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let needle = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(needle) ||
                $0.sourceDescription.lowercased().contains(needle)
            }
        }
        return result
    }

    func refresh() {
        let docDescriptor = FetchDescriptor<MedicalDocument>(
            sortBy: [SortDescriptor(\.documentDate, order: .reverse)]
        )
        documents = (try? context.fetch(docDescriptor)) ?? []

        var alertDescriptor = FetchDescriptor<HospitalSyncAlert>(
            sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
        )
        alertDescriptor.fetchLimit = 1
        alert = (try? context.fetch(alertDescriptor))?.first
    }

    func dismissAlert() {
        if let alert {
            context.delete(alert)
            try? context.save()
        }
        refresh()
    }

    func summary(for document: MedicalDocument) -> AISummary? {
        guard let key = document.aiSummaryKey else { return nil }
        return SampleAISummaries.summary(for: key)
    }

    @discardableResult
    func addSuggestedTasksToCalendar(from summary: AISummary) -> [String] {
        var added: [String] = []
        for suggestion in summary.suggestedTasks {
            let targetTitle = suggestion.title
            let predicate = #Predicate<DailyTask> { task in
                task.title == targetTitle
            }
            let existing = (try? context.fetch(FetchDescriptor<DailyTask>(predicate: predicate))) ?? []
            guard existing.isEmpty else { continue }

            let task = DailyTask(
                title: suggestion.title,
                detail: suggestion.detail,
                kind: .medical,
                origin: .aiSuggestion
            )
            context.insert(task)
            added.append(suggestion.title)
        }
        try? context.save()
        lastImportedTaskTitles = added
        return added
    }
}
