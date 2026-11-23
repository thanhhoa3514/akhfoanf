import SwiftData
import SwiftUI

/// Reminder detail for the wide layouts (iPad / Mac detail column). iPhone keeps the edit sheet.
struct ReminderDetailView: View {
    let reminderID: UUID

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(AppContainer.self) private var container
    @Query private var reminders: [ReminderModel]
    @Query private var events: [HealthEventModel]
    @Query private var pets: [PetModel]

    init(reminderID: UUID) {
        self.reminderID = reminderID
        _reminders = Query(filter: #Predicate<ReminderModel> { $0.id == reminderID })
    }

    var body: some View {
        if let reminder = reminders.first {
            let linked = reminder.healthEventId.flatMap { id in events.first { $0.id == id } }
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    header(reminder)
                    actions(reminder)
                    detailsCard(reminder)
                    if let notes = reminder.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            Text("Notes").font(.headline)
                            Text(notes).textSelection(.enabled)
                        }
                        .card()
                    }
                    if let linked { linkedCard(linked) }
                }
                .padding(AppTheme.Spacing.lg)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .canvasBackground()
            .navigationTitle(reminder.type.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { appState.sheet = .editReminder(reminder.id) } label: { Label("Edit", systemImage: "pencil") }
                }
            }
        } else {
            ContentUnavailableView("Reminder not found", systemImage: "bell.slash")
        }
    }

    private func header(_ reminder: ReminderModel) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            TypeIcon(systemImage: reminder.type.symbol,
                     tint: DueState(date: reminder.dueDate, soonWindow: reminder.soonWindow).fill, size: 52)
            VStack(alignment: .leading, spacing: 6) {
                Text(reminder.title).font(.title2.weight(.bold)).foregroundStyle(AppTheme.Colors.textPrimary)
                DueBadge(date: reminder.dueDate, isCompleted: reminder.state == .completed, soonWindow: reminder.soonWindow)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func actions(_ reminder: ReminderModel) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if reminder.isOpen {
                Button {
                    Task { await ReminderActions.complete(reminder, context: context, container: container) }
                } label: { Label("Mark as done", systemImage: "checkmark.circle") }
                .buttonStyle(.primary)
                Menu {
                    ForEach(SnoozeOption.allCases) { option in
                        Button(option.title) {
                            Task { await ReminderActions.snooze(reminder, by: option, context: context, container: container) }
                        }
                    }
                } label: { Label("Snooze", systemImage: "moon.zzz") }
                .menuIndicator(.hidden)
                .buttonStyle(.secondary)
            } else {
                Button {
                    Task { await ReminderActions.reopen(reminder, context: context, container: container) }
                } label: { Label("Mark as not done", systemImage: "arrow.uturn.backward.circle") }
                .buttonStyle(.secondary)
            }
        }
        .frame(maxWidth: 480)
    }

    private func detailsCard(_ reminder: ReminderModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            InfoRow(label: String(localized: "Due"),
                    value: reminder.dueDate.formatted(date: .long, time: .shortened),
                    systemImage: "calendar")
            InfoRow(label: String(localized: "Repeat"), value: reminder.recurrence.title, systemImage: "repeat")
            InfoRow(label: String(localized: "Type"), value: reminder.type.title, systemImage: "tag")
            if pets.count > 1, let pet = pets.first(where: { $0.id == reminder.petId }) {
                InfoRow(label: String(localized: "Pet"), value: pet.name, systemImage: "pawprint", verbatim: true)
            }
            if let done = reminder.completedAt, reminder.state == .completed {
                InfoRow(label: String(localized: "Done"), value: done.shortDate, systemImage: "checkmark.circle")
            }
        }
        .card()
    }

    private func linkedCard(_ event: HealthEventModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Linked record").font(.headline)
            NavigationLink(value: Route.event(event.id)) {
                HStack(spacing: AppTheme.Spacing.md) {
                    TypeIcon(systemImage: event.eventType.symbol, tint: event.eventType.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.appSubheadline.weight(.semibold)).foregroundStyle(AppTheme.Colors.textPrimary)
                        Text([event.eventType.title, event.eventDate.shortDate].joined(separator: " · "))
                            .font(.appCaption).foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .card()
    }
}
