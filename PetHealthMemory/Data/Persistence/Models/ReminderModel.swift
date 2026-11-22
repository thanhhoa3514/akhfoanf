import Foundation
import SwiftData

@Model
final class ReminderModel {
    @Attribute(.unique) var id: UUID
    var petId: UUID
    var healthEventId: UUID?
    var title: String
    var reminderType: String
    var dueDate: Date
    var recurrenceRule: String?
    var status: String
    var notes: String?
    var completedAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        petId: UUID,
        healthEventId: UUID? = nil,
        title: String,
        reminderType: String = ReminderType.custom.rawValue,
        dueDate: Date,
        recurrenceRule: String? = nil,
        status: String = ReminderStatus.pending.rawValue,
        notes: String? = nil,
        completedAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.petId = petId
        self.healthEventId = healthEventId
        self.title = title
        self.reminderType = reminderType
        self.dueDate = dueDate
        self.recurrenceRule = recurrenceRule
        self.status = status
        self.notes = notes
        self.completedAt = completedAt
        self.createdAt = createdAt
    }
}
