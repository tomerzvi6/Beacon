import Foundation
import SwiftData

@Model
final class HospitalSyncAlert {
    @Attribute(.unique) var id: String
    var title: String
    var body: String
    var sourceHospital: String
    var receivedAt: Date
    var isUnread: Bool
    var linkedDocumentId: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        sourceHospital: String,
        receivedAt: Date = .now,
        isUnread: Bool = true,
        linkedDocumentId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.sourceHospital = sourceHospital
        self.receivedAt = receivedAt
        self.isUnread = isUnread
        self.linkedDocumentId = linkedDocumentId
    }
}
