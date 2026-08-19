import Foundation
import UIKit
import Vision

/// Editable pre-fill produced from a medication-box / pharmacy-label photo.
/// Every field is a guess — the user confirms or fixes it in the intake sheet.
struct MedicationLabelDraft {
    var name: String = ""
    var dosageDescription: String = ""
    var timesPerDay: Int = 1
    var usageInstructions: String = ""
    var recognizedLines: [String] = []
}

/// Editable pre-fill produced from an appointment SMS screenshot or a
/// printed summons (זימון תור).
struct AppointmentDraft {
    var title: String = ""
    var startsAt: Date = .now
    var locationName: String = ""
    var subtitle: String = ""
    var foundDate: Bool = false
    var recognizedLines: [String] = []
}

/// On-device OCR (Vision) + heuristic parsing for the independent-mode
/// intake flows. No network, no backend — imperfect guesses are fine
/// because the UI always shows an editable confirmation form.
enum IntakeOCRService {

    // MARK: - OCR

    /// Recognizes Hebrew + English text and returns the lines top-to-bottom.
    static func recognizeText(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations
                    .sorted { $0.boundingBox.midY > $1.boundingBox.midY } // Vision origin is bottom-left
                    .compactMap { $0.topCandidates(1).first?.string }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["he-IL", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    // MARK: - Medication label parsing

    static func parseMedicationLabel(from lines: [String]) -> MedicationLabelDraft {
        var draft = MedicationLabelDraft(recognizedLines: lines)
        let joined = lines.joined(separator: "\n")

        draft.name = guessMedicationName(from: lines) ?? ""
        draft.dosageDescription = firstMatch(
            in: joined,
            pattern: #"\d+(?:\.\d+)?\s*(?:mg|mcg|ml|g|מ"ג|מ״ג|מ"ל|מ״ל|מק"ג|גרם|יחידות)"#
        ) ?? ""
        draft.timesPerDay = guessTimesPerDay(from: joined)
        draft.usageInstructions = guessInstructions(from: lines) ?? ""
        return draft
    }

    private static func guessMedicationName(from lines: [String]) -> String? {
        // Israeli pharmacy labels usually print the trade name in Latin
        // letters, often next to the strength ("ACAMOL 500 mg").
        let latinWithStrength = lines.first { line in
            line.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) != nil &&
            line.range(of: #"\d+\s*(?:mg|mcg|ml|g)"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        if let latinWithStrength {
            return cleanedName(latinWithStrength)
        }
        // Otherwise: the most "name-like" Latin line.
        let latinLine = lines.first { line in
            line.range(of: #"^[A-Za-z][A-Za-z\s\-]{2,}$"#, options: .regularExpression) != nil
        }
        if let latinLine {
            return cleanedName(latinLine)
        }
        // Fall back to the first Hebrew line that isn't obviously boilerplate.
        let boilerplate = ["בית מרקחת", "קופת חולים", "כללית", "מכבי", "לאומית", "מאוחדת", "טלפון", "כתובת", "מספר", "ת.ז", "תאריך"]
        return lines.first { line in
            line.count >= 3 &&
            line.range(of: #"[א-ת]{3,}"#, options: .regularExpression) != nil &&
            !boilerplate.contains(where: { line.contains($0) })
        }.map(cleanedName)
    }

    private static func cleanedName(_ raw: String) -> String {
        // Strip trailing strength ("ACAMOL 500 mg" → "ACAMOL").
        let stripped = raw.replacingOccurrences(
            of: #"\s*\d+(?:\.\d+)?\s*(?:mg|mcg|ml|g|מ"ג|מ״ג|טבליות|כדורים).*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? raw : trimmed
    }

    private static func guessTimesPerDay(from text: String) -> Int {
        if let match = firstMatch(in: text, pattern: #"(\d)\s*פעמים\s*ביום"#),
           let n = Int(firstMatch(in: match, pattern: #"\d"#) ?? ""), (1...6).contains(n) {
            return n
        }
        if text.contains("פעמיים ביום") { return 2 }
        if text.contains("שלוש פעמים") { return 3 }
        if text.contains("ארבע פעמים") { return 4 }
        if text.contains("פעם ביום") || text.contains("אחת ליום") { return 1 }
        if let match = firstMatch(in: text, pattern: #"כל\s*(\d+)\s*שעות"#),
           let hours = Int(firstMatch(in: match, pattern: #"\d+"#) ?? ""), hours > 0 {
            // The schedule UI supports up to 4 daily slots.
            return max(1, min(4, 24 / hours))
        }
        return 1
    }

    private static func guessInstructions(from lines: [String]) -> String? {
        let keywords = ["אחרי האוכל", "לפני האוכל", "עם האוכל", "על קיבה ריקה", "לפני השינה", "עם הרבה מים", "אין לרסק", "בבוקר", "בערב"]
        return lines.first { line in
            keywords.contains(where: { line.contains($0) })
        }
    }

    // MARK: - Appointment parsing

    /// When no date is recognized: tomorrow 09:00. An appointment is always
    /// in the future, so this beats defaulting to "right now".
    static func defaultAppointmentDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    static func parseAppointment(from lines: [String]) -> AppointmentDraft {
        var draft = AppointmentDraft(recognizedLines: lines)
        draft.startsAt = defaultAppointmentDate()
        let joined = lines.joined(separator: "\n")

        if let date = detectDate(in: joined) {
            draft.startsAt = date
            draft.foundDate = true
        }
        draft.title = guessAppointmentTitle(from: lines) ?? "תור לרופא"
        draft.locationName = guessLocation(from: lines) ?? ""
        return draft
    }

    private static func detectDate(in text: String) -> Date? {
        // NSDataDetector first — handles "יום שלישי 21.7 בשעה 10:30"-style text
        // reasonably well when the locale is Hebrew.
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = detector.matches(in: text, options: [], range: range)
            // Prefer a future date — appointment summonses are about the future.
            let future = matches.compactMap(\.date).first { $0 > Date() }
            if let candidate = future ?? matches.compactMap(\.date).first {
                return candidate
            }
        }

        // Fallback: dd/mm/yyyy or dd.mm.yy(yy) + optional HH:mm anywhere in the text.
        guard let dateString = firstMatch(in: text, pattern: #"\b\d{1,2}[./]\d{1,2}[./]\d{2,4}\b"#) else {
            return nil
        }
        let timeString = firstMatch(in: text, pattern: #"\b\d{1,2}:\d{2}\b"#)
        let normalized = dateString.replacingOccurrences(of: ".", with: "/")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateFormat = normalized.count > 8 ? "dd/MM/yyyy" : "dd/MM/yy"
        guard let day = formatter.date(from: normalized) else { return nil }

        guard let timeString,
              let hour = Int(timeString.split(separator: ":")[0]),
              let minute = Int(timeString.split(separator: ":")[1])
        else { return day }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private static func guessAppointmentTitle(from lines: [String]) -> String? {
        // A line naming the doctor is the best title.
        if let doctorLine = lines.first(where: { $0.contains("ד\"ר") || $0.contains("ד״ר") || $0.contains("דר'") || $0.contains("פרופ") }) {
            return doctorLine
        }
        // Otherwise a clinic / specialty line.
        let clinicKeywords = ["מרפאת", "מכון", "אונקולוג", "המטולוג", "הדמיה", "אולטרסאונד", "CT", "MRI", "בדיקת", "טיפול"]
        return lines.first { line in
            clinicKeywords.contains(where: { line.contains($0) })
        }
    }

    private static func guessLocation(from lines: [String]) -> String? {
        let locationKeywords = ["בית חולים", "ביה\"ח", "רמב\"ם", "רמב״ם", "קומה", "בניין", "אגף", "חדר", "מרפאות חוץ", "קריה רפואית"]
        return lines.first { line in
            locationKeywords.contains(where: { line.contains($0) })
        }
    }

    // MARK: - Regex helper

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return String(text[range])
    }
}
