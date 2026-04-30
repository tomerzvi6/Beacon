import Foundation
import Observation
import SwiftData

@Observable
final class MedicalVaultViewModel {
    private let context: ModelContext
    private let uploadService: BackendDocumentService

    var alert: HospitalSyncAlert?
    var documents: [MedicalDocument] = []
    var searchText: String = ""
    var selectedFilter: MedicalDocumentKind = .all
    var lastImportedTaskTitles: [String] = []

    // Phase 9.2 — upload flow state
    enum UploadPhase: Equatable {
        case idle
        case uploading(progress: Double)
    }
    var uploadPhase: UploadPhase = .idle
    var uploadAlert: UploadAlert? = nil

    enum UploadAlert: Identifiable, Equatable {
        case success(filename: String, documentId: UUID)
        case duplicate(filename: String, uploadedAt: Date?)
        case failure(message: String)

        var id: String {
            switch self {
            case .success(_, let id):  return "success-\(id.uuidString)"
            case .duplicate(let f, _): return "duplicate-\(f)"
            case .failure(let m):      return "failure-\(m.hashValue)"
            }
        }
    }

    init(context: ModelContext, uploadService: BackendDocumentService = BackendDocumentService()) {
        self.context = context
        self.uploadService = uploadService
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

    // MARK: - Upload (Phase 9.2)

    @MainActor
    func upload(
        _ file: PendingUploadFile,
        category: BackendDocumentCategory?,
        isPrivate: Bool
    ) async {
        uploadPhase = .uploading(progress: 0)
        do {
            let outcome = try await uploadService.upload(
                data: file.data,
                filename: file.filename,
                mimeType: file.mimeType,
                category: category,
                isPrivate: isPrivate,
                onProgress: { [weak self] fraction in
                    self?.uploadPhase = .uploading(progress: fraction)
                }
            )
            switch outcome {
            case .success(let documentId):
                uploadAlert = .success(filename: file.filename, documentId: documentId)
            case .duplicate(_, let uploadedAt):
                uploadAlert = .duplicate(filename: file.filename, uploadedAt: uploadedAt)
            }
        } catch let error as APIError {
            uploadAlert = .failure(message: error.userMessage)
        } catch {
            uploadAlert = .failure(message: error.localizedDescription)
        }
        uploadPhase = .idle
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
