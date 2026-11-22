import Foundation
import SwiftData

@Model
final class CareProviderModel {
    @Attribute(.unique) var id: UUID
    var clinicName: String
    var vetName: String?
    var phone: String?
    var address: String?
    var notes: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        clinicName: String,
        vetName: String? = nil,
        phone: String? = nil,
        address: String? = nil,
        notes: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.clinicName = clinicName
        self.vetName = vetName
        self.phone = phone
        self.address = address
        self.notes = notes
        self.createdAt = createdAt
    }
}
