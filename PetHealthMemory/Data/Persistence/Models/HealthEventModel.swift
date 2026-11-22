import Foundation
import SwiftData

@Model
final class HealthEventModel {
    @Attribute(.unique) var id: UUID
    var petId: UUID
    var type: String
    var title: String
    var eventDate: Date
    var notes: String?
    var providerId: UUID?
    var sourceDocumentId: UUID?
    /// Clinic name as written (denormalised, mirrors backend `provider_name`).
    var providerName: String?
    /// Vaccination: next due date — only when explicitly stated by document or user.
    var nextDueDate: Date?
    /// Medication: dosage & frequency are stored verbatim, never calculated.
    var dosageText: String?
    var frequencyText: String?
    var startDate: Date?
    var endDate: Date?
    /// Medication: "active" | "completed" (see `MedicationStatus`).
    var medicationStatus: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        petId: UUID,
        type: String,
        title: String,
        eventDate: Date,
        notes: String? = nil,
        providerId: UUID? = nil,
        sourceDocumentId: UUID? = nil,
        providerName: String? = nil,
        nextDueDate: Date? = nil,
        dosageText: String? = nil,
        frequencyText: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        medicationStatus: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.petId = petId
        self.type = type
        self.title = title
        self.eventDate = eventDate
        self.notes = notes
        self.providerId = providerId
        self.sourceDocumentId = sourceDocumentId
        self.providerName = providerName
        self.nextDueDate = nextDueDate
        self.dosageText = dosageText
        self.frequencyText = frequencyText
        self.startDate = startDate
        self.endDate = endDate
        self.medicationStatus = medicationStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
