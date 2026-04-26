import Foundation
import SwiftData

enum MedicalDocumentKind: String, Codable, CaseIterable, Identifiable {
    case all
    case visitSummary
    case bloodTest
    case imaging
    case prescription
    case other

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .all: return "הכל"
        case .visitSummary: return "סיכומי ביקור"
        case .bloodTest: return "בדיקות דם"
        case .imaging: return "הדמיות"
        case .prescription: return "מרשמים"
        case .other: return "אחר"
        }
    }

    var iconSymbol: String {
        switch self {
        case .all: return "tray.full"
        case .visitSummary: return "stethoscope"
        case .bloodTest: return "drop.fill"
        case .imaging: return "waveform.path.ecg"
        case .prescription: return "doc.text.fill"
        case .other: return "doc"
        }
    }
}

enum DocumentFileType: String, Codable {
    case pdf
    case image
    case text

    var displayLabel: String {
        switch self {
        case .pdf: return "PDF"
        case .image: return "תמונה"
        case .text: return "טקסט"
        }
    }
}

@Model
final class MedicalDocument {
    @Attribute(.unique) var id: String
    var title: String
    var sourceDescription: String
    var documentDate: Date
    var kindRaw: String
    var fileTypeRaw: String
    var fileSizeLabel: String?
    var hasAISummary: Bool
    var aiSummaryKey: String?

    var kind: MedicalDocumentKind {
        get { MedicalDocumentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var fileType: DocumentFileType {
        get { DocumentFileType(rawValue: fileTypeRaw) ?? .pdf }
        set { fileTypeRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        sourceDescription: String,
        documentDate: Date,
        kind: MedicalDocumentKind,
        fileType: DocumentFileType,
        fileSizeLabel: String? = nil,
        hasAISummary: Bool = false,
        aiSummaryKey: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceDescription = sourceDescription
        self.documentDate = documentDate
        self.kindRaw = kind.rawValue
        self.fileTypeRaw = fileType.rawValue
        self.fileSizeLabel = fileSizeLabel
        self.hasAISummary = hasAISummary
        self.aiSummaryKey = aiSummaryKey
    }
}
