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

    // Marketing-demo AI summary: intentionally static until the real
    // AI service is wired in.
    var featuredSummary: AISummary { SampleAISummaries.dashboardFeatured }
    var lastImportedTaskTitles: [String] = []

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

    init(
        context: ModelContext,
        documentService: BackendDocumentService = BackendDocumentService()
    ) {
        self.context = context
        self.documentService = documentService
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
                Task { await self.startParseAndPoll(documentId: documentId) }
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

    // MARK: - Parse + poll

    /// Trigger backend parsing and then poll for status. Idempotent —
    /// callable from the UI's failure-retry path or after upload.
    @MainActor
    func startParseAndPoll(documentId: UUID) async {
        pollingDocumentIds.insert(documentId)
        defer { pollingDocumentIds.remove(documentId) }

        // Fire parse. Backend route is currently synchronous; awaiting
        // it gives us the parsed payload directly. Errors here are
        // non-fatal — the polling loop reconciles state regardless.
        _ = try? await documentService.parse(documentId: documentId)

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
