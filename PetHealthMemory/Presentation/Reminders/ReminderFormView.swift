import SwiftData
import SwiftUI

/// Screen 12 — Create / Edit Reminder. Notification permission is requested here, in context (PRD F09).
struct ReminderFormView: View {
    enum Mode {
        case create(petID: UUID, draft: ReminderDraft)
        case edit(UUID)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container

    @State private var title = ""
    @State private var type: ReminderType = .custom
    @State private var dueDate = Date.now
    @State private var recurrence: RecurrenceOption = .none
    @State private var notes = ""
    @State private var existing: ReminderModel?
    @State private var linkedEventID: UUID?
    @State private var confirmDelete = false
    @State private var permissionNote: String?

    var body: some View {
        Form {
            Section {
                TextField("What needs doing?", text: $title)
                Picker("Type", selection: $type) {
                    ForEach(ReminderType.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                DatePicker("Due", selection: $dueDate)
                Picker("Repeat", selection: $recurrence) {
                    ForEach(RecurrenceOption.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Notes") {
                TextField("Optional", text: $notes, axis: .vertical).lineLimit(2...5)
            }
            if let permissionNote {
                Section { Label(permissionNote, systemImage: "bell.slash").foregroundStyle(AppTheme.Colors.warningText) }
            }
            if existing != nil {
                Section {
                    Button("Delete reminder", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .canvasBackground()
        .navigationTitle(existing == nil ? "New Reminder" : "Edit Reminder")
        .inlineTitleOnPhone()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.disabled(title.nilIfEmpty == nil)
            }
        }
        .confirmationDialog("Delete this reminder?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    if let existing { try? await DataCleanup.delete(reminder: existing, in: context, container: container) }
                    dismiss()
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        switch mode {
        case .create(_, let draft):
            title = draft.title
            type = draft.type
            dueDate = draft.dueDate
            linkedEventID = draft.healthEventId
        case .edit(let id):
            guard let reminder = try? context.fetch(FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.id == id })).first else { return }
            existing = reminder
            title = reminder.title
            type = reminder.type
            dueDate = reminder.dueDate
            recurrence = reminder.recurrence
            notes = reminder.notes ?? ""
            linkedEventID = reminder.healthEventId
        }
    }

    private func save() async {
        let reminder: ReminderModel
        if let existing {
            reminder = existing
        } else if case .create(let petID, _) = mode {
            reminder = ReminderModel(petId: petID, title: "", dueDate: dueDate)
            context.insert(reminder)
        } else { return }

        reminder.title = title.nilIfEmpty ?? type.title
        reminder.reminderType = type.rawValue
        reminder.dueDate = dueDate
        reminder.recurrenceRule = recurrence.rule
        reminder.notes = notes.nilIfEmpty
        reminder.healthEventId = linkedEventID
        if reminder.state == .snoozed { reminder.status = ReminderStatus.pending.rawValue }
        try? context.save()

        let service = container.notificationService
        if await service.authorizationStatus() == .notDetermined {
            _ = try? await service.requestAuthorization()
        }
        if await service.authorizationStatus() == .denied {
            permissionNote = "Saved. Notifications are off, so this reminder will only appear in the app."
            try? await Task.sleep(for: .seconds(1.6))
        } else {
            try? await ReminderActions.schedule(reminder, container: container)
        }
        dismiss()
    }
}
