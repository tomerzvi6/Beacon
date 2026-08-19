import Foundation

/// Which pipeline feeds the patient's medical data into Beacon.
///
/// `.hospitalIntegrated` — the Rambam-cooperation build: documents arrive
/// automatically from the hospital/HMO integration and the family mostly reads.
///
/// `.independent` — the self-serve build (Plan B): the family captures
/// everything themselves — batch document scans, medication-box photos,
/// appointment screenshots — and Beacon does the structuring.
///
/// The mode is a runtime switch (persisted in UserDefaults) so both versions
/// can be demoed live from the same install.
enum DataSourceMode: String, Codable, CaseIterable, Identifiable {
    case hospitalIntegrated
    case independent

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .hospitalIntegrated: return "מחובר לבית החולים"
        case .independent: return "עצמאי"
        }
    }

    var explanation: String {
        switch self {
        case .hospitalIntegrated:
            return "מסמכים וסיכומים מגיעים אוטומטית מבית החולים ומהקופה."
        case .independent:
            return "המשפחה מצלמת ומשתפת — ביקון מזהה, מסדר ומסכם הכל לבד."
        }
    }

    var iconSymbol: String {
        switch self {
        case .hospitalIntegrated: return "building.2.fill"
        case .independent: return "camera.viewfinder"
        }
    }
}
