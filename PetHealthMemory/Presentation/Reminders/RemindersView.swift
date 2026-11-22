import SwiftData
import SwiftUI

/// Screen 4 — Reminders: Overdue → This week → Later → Completed (collapsible).
struct RemindersView: View {
    let petID: UUID

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(AppContainer.self) private var container
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \ReminderModel.dueDate) private var allReminders: [ReminderModel]
    @Query private var pets: [PetModel]
    @State private var scope: Scope = .thisPet
    @State private var showCompleted = false
    @State private var authorization: NotificationAuthorization = .authorized

    enum Scope: String, CaseIterable, Identifiable {
        case thisPet = "This pet", allPets = "All pets"
        var id: String { rawValue }
    }

    private var reminders: [ReminderModel] {
        scope == .thisPet ? allReminders.filter { $0.petId == petID } : allReminders
    }
    private var weekHorizon: Date { Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now }
    private var overdue: [ReminderModel] { reminders.filter { $0.isOpen && $0.dueDate < .now } }
    private var thisWeek: [ReminderModel] { reminders.filter { $0.isOpen && $0.dueDate >= .now && $0.dueDate <= weekHorizon } }
    private var later: [ReminderModel] { reminders.filter { $0.isOpen && $0.dueDate > weekHorizon } }
    private var completed: [ReminderModel] {
        reminders.filter { $0.state == .completed }.sorted { ($0.completedAt ?? $0.dueDate) > ($1.completedAt ?? $1.dueDate) }
    }
    private var petNames: [UUID: String] { Dictionary(uniqueKeysWithValues: pets.map { ($0.id, $0.name) }) }

    var body: some View {
        RouteList {
            if pets.count > 1 {
                Picker("Show", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            if authorization == .denied {
                Section {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                        Image(systemName: "bell.slash").foregroundStyle(AppTheme.Colors.statusWarning)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notifications are off").font(.appSubheadline.weight(.semibold))
                            Text("Reminders still show here, but won't alert you.").font(.appCaption)
                            Button("Turn on in Settings") { SystemSettings.open() }.font(.appCaption.weight(.semibold))
                        }
                    }
                }
            }

            if reminders.filter(\.isOpen).isEmpty && completed.isEmpty {
                ContentUnavailableView {
                    Label("No reminders", systemImage: "bell")
                } description: {
                    Text("Add reminders for boosters, medications and appointments. They work offline.")
                } actions: {
                    Button("Add reminder") { appState.sheet = .newReminder(ReminderDraft()) }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }

            group("Overdue", overdue)
            group("This week", thisWeek)
            group("Later", later)

            if !completed.isEmpty {
                Section {
                    DisclosureGroup("Completed (\(completed.count))", isExpanded: $showCompleted) {
                        ForEach(completed.prefix(30)) { row($0) }
                    }
                }
            }
        }
        .animation(AppTheme.Motion.animation(AppTheme.Motion.standard, reduceMotion: reduceMotion), value: reminders.map(\.status))
        .navigationTitle("Reminders")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { appState.sheet = .newReminder(ReminderDraft()) } label: { Label("Add reminder", systemImage: "plus") }
                    .help("New reminder (⇧⌘R)")
            }
        }
        .task { authorization = await container.notificationService.authorizationStatus() }
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [ReminderModel]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { row($0) }
            }
        }
    }

    private func row(_ reminder: ReminderModel) -> some View {
        ReminderRow(
            reminder: reminder,
            petName: scope == .allPets ? petNames[reminder.petId] : nil,
            onToggle: {
                Task {
                    if reminder.state == .completed {
                        await ReminderActions.reopen(reminder, context: context, container: container)
                    } else {
                        await ReminderActions.complete(reminder, context: context, container: container)
                    }
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { appState.sheet = .editReminder(reminder.id) }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { try? await DataCleanup.delete(reminder: reminder, in: context, container: container) }
            } label: { Label("Delete", systemImage: "trash") }
            if reminder.isOpen {
                Button {
                    Task { await ReminderActions.snooze(reminder, by: .tomorrow, context: context, container: container) }
                } label: { Label("Snooze", systemImage: "moon.zzz") }
                .tint(AppTheme.Colors.statusSource)
            }
        }
        .contextMenu {
            if reminder.isOpen {
                Menu("Snooze") {
                    ForEach(SnoozeOption.allCases) { option in
                        Button(option.title) {
                            Task { await ReminderActions.snooze(reminder, by: option, context: context, container: container) }
                        }
                    }
                }
            }
            Button("Edit") { appState.sheet = .editReminder(reminder.id) }
            Button("Delete", role: .destructive) {
                Task { try? await DataCleanup.delete(reminder: reminder, in: context, container: container) }
            }
        }
    }
}

struct ReminderRow: View {
    let reminder: ReminderModel
    let petName: String?
    let onToggle: () -> Void

    private var isDone: Bool { reminder.state == .completed }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Button(action: onToggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isDone ? AppTheme.Colors.statusSuccess : AppTheme.Colors.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: isDone) { _, done in done }
            .accessibilityLabel(isDone ? "Completed. Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.body.weight(.medium))
                    .strikethrough(isDone, color: AppTheme.Colors.textSecondary)
                    .foregroundStyle(isDone ? AppTheme.Colors.textSecondary : AppTheme.Colors.textPrimary)
                HStack(spacing: AppTheme.Spacing.xs) {
                    DueBadge(date: reminder.dueDate, isCompleted: isDone, soonWindow: reminder.soonWindow)
                    if reminder.recurrence != .none {
                        Label(reminder.recurrence.title, systemImage: "repeat")
                            .font(.appCaption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    if reminder.state == .snoozed {
                        Label("Snoozed", systemImage: "moon.zzz").font(.appCaption).foregroundStyle(AppTheme.Colors.sourceText)
                    }
                    if let petName {
                        Text(petName).font(.appCaption).foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: reminder.type.symbol).foregroundStyle(AppTheme.Colors.textSecondary).accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }
}
