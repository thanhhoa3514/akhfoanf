import Foundation
import UserNotifications

enum NotificationAuthorization {
    case notDetermined, authorized, denied
}

protocol ReminderNotificationServiceProtocol {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async throws -> Bool
    func schedule(id: UUID, title: String, body: String, at date: Date) async throws
    func cancel(reminderId: UUID) async
    /// Ensures UNUserNotificationCenter exactly matches the open reminders persisted locally.
    func reconcile(reminders: [(id: UUID, title: String, body: String, dueDate: Date)]) async
}

/// Offline UNUserNotificationCenter scheduler & launch reconciler (Sprint 5).
final class ReminderNotificationService: ReminderNotificationServiceProtocol {
    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> NotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .authorized
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedule(id: UUID, title: String, body: String, at date: Date) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        guard date > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try await center.add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: trigger))
    }

    func cancel(reminderId: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: [reminderId.uuidString])
    }

    func reconcile(reminders: [(id: UUID, title: String, body: String, dueDate: Date)]) async {
        guard await authorizationStatus() == .authorized else { return }
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let wanted = Set(reminders.map(\.id.uuidString))
        let stale = pending.filter { !wanted.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        for reminder in reminders where !pending.contains(reminder.id.uuidString) {
            try? await schedule(id: reminder.id, title: reminder.title, body: reminder.body, at: reminder.dueDate)
        }
    }
}
