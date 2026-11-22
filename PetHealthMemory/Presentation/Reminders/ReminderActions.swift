import Foundation
import SwiftData

/// Reminder state transitions shared by list rows, Home and the form (PRD F09).
@MainActor
enum ReminderActions {
    static func complete(_ reminder: ReminderModel, context: ModelContext, container: AppContainer) async {
        reminder.status = ReminderStatus.completed.rawValue
        reminder.completedAt = .now
        await container.notificationService.cancel(reminderId: reminder.id)
        // Recurring: roll forward a fresh occurrence (keeps history of completions).
        if let next = reminder.recurrence.nextDate(after: reminder.dueDate) {
            let upcoming = ReminderModel(
                petId: reminder.petId, healthEventId: reminder.healthEventId, title: reminder.title,
                reminderType: reminder.reminderType, dueDate: next, recurrenceRule: reminder.recurrenceRule,
                notes: reminder.notes
            )
            context.insert(upcoming)
            try? await schedule(upcoming, container: container)
        }
        try? context.save()
    }

    static func reopen(_ reminder: ReminderModel, context: ModelContext, container: AppContainer) async {
        reminder.status = ReminderStatus.pending.rawValue
        reminder.completedAt = nil
        try? context.save()
        try? await schedule(reminder, container: container)
    }

    static func snooze(_ reminder: ReminderModel, by interval: SnoozeOption, context: ModelContext, container: AppContainer) async {
        reminder.dueDate = interval.date(from: max(reminder.dueDate, .now))
        reminder.status = ReminderStatus.snoozed.rawValue
        try? context.save()
        try? await schedule(reminder, container: container)
    }

    static func schedule(_ reminder: ReminderModel, container: AppContainer) async throws {
        try await container.notificationService.schedule(
            id: reminder.id, title: reminder.title, body: reminder.notes ?? reminder.type.title, at: reminder.dueDate
        )
    }
}

enum SnoozeOption: String, CaseIterable, Identifiable {
    case oneHour, tonight, tomorrow, nextWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHour: String(localized: "In 1 hour")
        case .tonight: String(localized: "This evening")
        case .tomorrow: String(localized: "Tomorrow morning")
        case .nextWeek: String(localized: "Next week")
        }
    }

    func date(from base: Date) -> Date {
        let calendar = Calendar.current
        switch self {
        case .oneHour:
            return base.addingTimeInterval(3600)
        case .tonight:
            let evening = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: base) ?? base
            return evening > base ? evening : base.addingTimeInterval(3600)
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: base) ?? base
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        case .nextWeek:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: base) ?? base
        }
    }
}
