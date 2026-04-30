import Foundation

/// Backend `category` values from `DOCUMENT_CATEGORIES` in
/// `shared/schemas.py`. Strings rather than an enum to gracefully tolerate
/// the model adding a new category in the future.
enum BackendDocumentCategory: String, CaseIterable, Identifiable {
    case lab
    case prescription
    case visitSummary = "visit_summary"
    case referral
    case imaging
    case consult
    case admin
    case other

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .lab:           return "בדיקות מעבדה"
        case .prescription:  return "מרשמים"
        case .visitSummary:  return "סיכום ביקור"
        case .referral:      return "הפניות"
        case .imaging:       return "הדמיות"
        case .consult:       return "ייעוץ"
        case .admin:         return "מנהלי"
        case .other:         return "אחר"
        }
    }

    var iconSymbol: String {
        switch self {
        case .lab:           return "drop.fill"
        case .prescription:  return "pills.fill"
        case .visitSummary:  return "stethoscope"
        case .referral:      return "arrow.right.doc.on.clipboard"
        case .imaging:       return "waveform.path.ecg"
        case .consult:       return "person.2.wave.2"
        case .admin:         return "doc.text"
        case .other:         return "doc"
        }
    }
}

/// Mirror of `PresignResponse` from `shared/schemas.py`.
struct BackendPresignResponse: Decodable {
    let document_id: UUID
    let upload_url: String
    let expires_in_seconds: Int
}

/// Mirror of `FinalizeDocumentOut`.
struct BackendFinalizeResponse: Decodable {
    let document_id: UUID
    let status: String  // "ok" | "conflict"
    let existing_document_id: UUID?
    let uploaded_at: Date?
    let uploaded_by: UUID?
}

/// In-memory file the user picked but has not yet uploaded. Holds the
/// raw bytes so the upload flow can hash and PUT them in one go without
/// re-reading from disk.
struct PendingUploadFile: Identifiable {
    let id = UUID()
    let data: Data
    let filename: String
    let mimeType: String
    let sourceLabel: String  // "צילום" / "אלבום" / "קובץ"
}

/// Mirror of `DocumentOut` — full record returned by GET /v1/documents/.
struct BackendDocument: Decodable, Identifiable, Equatable {
    let id: UUID
    let household_id: UUID
    let uploaded_by: UUID
    let mime_type: String
    let filename: String?
    let status: String           // uploaded|finalized|parsing|parsed|failed
    let category: String?
    let category_source: String?
    let category_suggested: String?
    let is_private: Bool
    let flagged_for_review: Bool
    let flag_reason: String?
    let parsed_summary_simple_he: String?
    let created_at: Date
    let parsed_at: Date?
    let deleted_at: Date?
}
