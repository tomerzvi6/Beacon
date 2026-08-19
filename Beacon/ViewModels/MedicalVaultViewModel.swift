import Foundation
import Observation
import SwiftData

/// Drives the Medical Vault. As of Phase 9.3, documents are read
/// directly from the backend (`GET /v1/documents/`) rather than from
/// SwiftData; the only @Model still owned by this view model is
/// `HospitalSyncAlert`, which is in-app notification state and will
/// be migrated when the hospital-sync surface is wired up.
@Observable
final class MedicalVaultViewModel {
    private let context: ModelContext
    private let documentService: BackendDocumentService

    // MARK: - HospitalSyncAlert (still SwiftData-backed for Phase 9.3)
    var alert: HospitalSyncAlert?

    // MARK: - Document list (backend-backed)
    var documents: [BackendDocument] = []
    var isLoading: Bool = false
    var loadErrorMessage: String? = nil
    private var nextCursor: String? = nil
    var hasMore: Bool { nextCursor != nil }

    // MARK: - Filters → re-fetch
    var searchText: String = ""
    var selectedCategory: BackendDocumentCategory? = nil

    // Suggested tasks returned by the most recent successful parse.
    // Stored so featuredAISummary can include them without a second API call.
    var lastParsedSuggestedTasks: [BackendSuggestedTask] = []
    var lastImportedTaskTitles: [String] = []

    /// Live AISummary built from the most recently parsed backend document.
    /// Returns nil when no parsed document exists yet — callers fall back to
    /// the static demo summary in that case.
    var featuredAISummary: AISummary? {
        guard let doc = featuredDocument,
              let simpleSummary = doc.parsed_summary_simple_he, !simpleSummary.isEmpty
        else { return nil }

        let headline = doc.typedCategory?.displayLabel
            ?? doc.filename?.replacingOccurrences(of: "_", with: " ")
            ?? "מסמך רפואי"
        let tasks = lastParsedSuggestedTasks.map {
            AISuggestedTask(id: $0.title_he, title: $0.title_he, detail: $0.due_hint)
        }
        return AISummary(
            id: doc.id.uuidString,
            headline: headline,
            summaryText: simpleSummary,
            keyPoints: [],
            recommendation: nil,
            suggestedTasks: tasks
        )
    }

    // Fallback demo summary shown before the first real document is parsed.
    var featuredSummary: AISummary { SampleAISummaries.dashboardFeatured }

    // MARK: - Upload flow state (Phase 9.2)
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

    // Doc-ids currently being polled for parse-status updates. Surfaced
    // to the view so it can show per-card parsing UI without recomputing
    // from `status` on every refresh tick.
    var pollingDocumentIds: Set<UUID> = []

    private let taskService: TaskService

    init(
        context: ModelContext,
        documentService: BackendDocumentService = BackendDocumentService(),
        taskService: TaskService = TaskService()
    ) {
        self.context = context
        self.documentService = documentService
        self.taskService = taskService
        refreshAlert()
    }

    // MARK: - Document list (backend)

    /// Most recently parsed document — drives the AI featured card.
    /// Returns nil when nothing in the current page has parsed yet.
    var featuredDocument: BackendDocument? {
        documents
            .filter { $0.isParsed && $0.parsed_summary_simple_he?.isEmpty == false }
            .sorted { ($0.parsed_at ?? .distantPast) > ($1.parsed_at ?? .distantPast) }
            .first
    }

    @MainActor
    @discardableResult
    func addSuggestedTasksToCalendar(from summary: AISummary) async -> [String] {
        var added: [String] = []
        for suggestion in summary.suggestedTasks {
            let targetTitle = suggestion.title
            let predicate = #Predicate<DailyTask> { task in
                task.title == targetTitle
            }
            let existing = (try? context.fetch(FetchDescriptor<DailyTask>(predicate: predicate))) ?? []
            guard existing.isEmpty else { continue }

            let created = await taskService.createAndInsert(
                title: suggestion.title, detail: suggestion.detail, kind: .medical, origin: .aiSuggestion, in: context
            )
            if created == nil {
                context.insert(DailyTask(
                    title: suggestion.title, detail: suggestion.detail, kind: .medical, origin: .aiSuggestion
                ))
            }
            added.append(suggestion.title)
        }
        try? context.save()
        lastImportedTaskTitles = added
        return added
    }

    /// Fetch the first page from scratch — also called by pull-to-refresh
    /// and after filters change.
    @MainActor
    func refresh() async {
        isLoading = true
        loadErrorMessage = nil
        nextCursor = nil
        do {
            let page = try await documentService.list(
                category: selectedCategory,
                query: searchText
            )
            documents = page.documents
            nextCursor = page.nextCursor
        } catch let error as APIError {
            loadErrorMessage = error.userMessage
        } catch {
            loadErrorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Append the next page — call from `.onAppear` of the last visible
    /// card so we keep the cursor moving. No-op when `hasMore == false`.
    @MainActor
    func loadMore() async {
        guard let cursor = nextCursor, !isLoading else { return }
        isLoading = true
        loadErrorMessage = nil
        do {
            let page = try await documentService.list(
                category: selectedCategory,
                query: searchText,
                cursor: cursor
            )
            documents.append(contentsOf: page.documents)
            nextCursor = page.nextCursor
        } catch let error as APIError {
            loadErrorMessage = error.userMessage
        } catch {
            loadErrorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Upload

    @MainActor
    func upload(
        _ file: PendingUploadFile,
        category: BackendDocumentCategory?,
        isPrivate: Bool
    ) async {
        uploadPhase = .uploading(progress: 0)
        do {
            let outcome = try await documentService.upload(
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
                // Pull the freshly-finalized doc into the list, then
                // kick off parse + poll in the background.
                await refresh()
                Task { [weak self] in await self?.startParseAndPoll(documentId: documentId) }
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

    /// Sequential upload of a scanned pile (independent-mode batch intake).
    /// One summary alert at the end instead of one per page; every uploaded
    /// page still enters the regular parse + poll pipeline.
    @MainActor
    func uploadBatch(
        _ files: [PendingUploadFile],
        onFileFinished: (Int) -> Void = { _ in }
    ) async -> (succeeded: Int, failed: Int) {
        guard !files.isEmpty else { return (0, 0) }
        var succeeded = 0
        var failed = 0
        var newDocumentIds: [UUID] = []

        for (index, file) in files.enumerated() {
            uploadPhase = .uploading(progress: Double(index) / Double(files.count))
            do {
                let outcome = try await documentService.upload(
                    data: file.data,
                    filename: file.filename,
                    mimeType: file.mimeType,
                    category: nil,
                    isPrivate: false,
                    onProgress: { _ in }
                )
                if case .success(let documentId) = outcome {
                    newDocumentIds.append(documentId)
                }
                succeeded += 1
            } catch {
                failed += 1
            }
            onFileFinished(index + 1)
        }
        uploadPhase = .idle

        if failed == 0 {
            uploadAlert = .success(
                filename: "\(succeeded) דפים",
                documentId: newDocumentIds.first ?? UUID()
            )
        } else {
            uploadAlert = .failure(message: "הועלו \(succeeded) דפים, \(failed) נכשלו. אפשר לנסות שוב את הדפים שנכשלו.")
        }

        await refresh()
        for documentId in newDocumentIds {
            Task { [weak self] in await self?.startParseAndPoll(documentId: documentId) }
        }
        return (succeeded, failed)
    }

    // MARK: - Parse + poll

    /// Trigger backend parsing and then poll for status. Idempotent —
    /// callable from the UI's failure-retry path or after upload.
    @MainActor
    func startParseAndPoll(documentId: UUID) async {
        pollingDocumentIds.insert(documentId)
        defer { pollingDocumentIds.remove(documentId) }

        // Fire parse. Backend route is currently synchronous; awaiting
        // it gives us the parsed payload directly. Capture suggested tasks
        // so the AI feature card can display them immediately after parsing.
        if let response = try? await documentService.parse(documentId: documentId) {
            lastParsedSuggestedTasks = response.suggested_tasks
        }

        // Poll up to ~60s (20 ticks × 3s) for status to settle.
        let maxTicks = 20
        for _ in 0..<maxTicks {
            do {
                let doc = try await documentService.fetch(documentId: documentId)
                replaceOrInsert(doc)
                if doc.isParsed || doc.isFailed { return }
            } catch {
                // Network blip — keep ticking.
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    @MainActor
    private func replaceOrInsert(_ doc: BackendDocument) {
        if let idx = documents.firstIndex(where: { $0.id == doc.id }) {
            documents[idx] = doc
        } else {
            documents.insert(doc, at: 0)
        }
    }

    // MARK: - HospitalSyncAlert (unchanged from earlier phases)

    func dismissAlert() {
        if let alert {
            context.delete(alert)
            try? context.save()
        }
        refreshAlert()
    }

    private func refreshAlert() {
        var descriptor = FetchDescriptor<HospitalSyncAlert>(
            sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        alert = (try? context.fetch(descriptor))?.first
    }
}
