import SwiftData
import SwiftUI

/// Screen 10 — Health Event Detail with 1-tap source document (US-06).
struct HealthEventDetailView: View {
    let eventID: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppContainer.self) private var container
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var events: [HealthEventModel]
    @Query private var documents: [DocumentModel]
    @Query private var reminders: [ReminderModel]
    @State private var confirmDelete = false

    init(eventID: UUID) {
        self.eventID = eventID
        _events = Query(filter: #Predicate<HealthEventModel> { $0.id == eventID })
        _reminders = Query(filter: #Predicate<ReminderModel> { $0.healthEventId == eventID }, sort: \.dueDate)
    }

    var body: some View {
        if let event = events.first {
            let source = event.sourceDocumentId.flatMap { id in documents.first { $0.id == id } }
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    header(event)
                    detailsCard(event)
                    if let notes = event.notes {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            Text("Notes").font(.headline)
                            Text(notes).textSelection(.enabled)
                        }
                        .card()
                    }
                    sourceCard(source, hadSource: event.sourceDocumentId != nil)
                    remindersCard(event)
                    MedicalDisclaimer()
                }
                .padding(AppTheme.Spacing.lg)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .canvasBackground()
            .navigationTitle(event.eventType.title)
            .inlineTitleOnPhone()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { appState.sheet = .editEvent(eventID) } label: { Label("Edit", systemImage: "pencil") }
                        Button { addReminder(for: event) } label: { Label("Add reminder", systemImage: "bell.badge") }
                        Divider()
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete record", systemImage: "trash") }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Delete this record?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete record", role: .destructive) {
                    Task {
                        try? await DataCleanup.delete(event: event, in: context, container: container)
                        appState.detailRoute = nil
                        dismiss()
                    }
                }
            } message: {
                Text("The original document is kept. Linked reminders stay but are unlinked.")
            }
        } else {
            ContentUnavailableView("Record not found", systemImage: "heart.text.square")
        }
    }

    private func header(_ event: HealthEventModel) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            TypeIcon(systemImage: event.eventType.symbol, tint: event.eventType.tint, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.title2.weight(.bold)).foregroundStyle(AppTheme.Colors.textPrimary)
                Text(event.eventDate.formatted(date: .long, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }

    private func detailsCard(_ event: HealthEventModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if let clinic = event.providerName {
                InfoRow(label: "Clinic", value: clinic, systemImage: "building.2")
            }
            if event.eventType == .vaccination {
                InfoRow(
                    label: "Next due",
                    value: event.nextDueDate?.shortDate ?? "Not stated",
                    systemImage: "calendar.badge.clock"
                )
            }
            if event.eventType == .medication {
                if let dosage = event.dosageText {
                    InfoRow(label: "Dosage", value: dosage, systemImage: "pills", verbatim: true)
                }
                if let frequency = event.frequencyText {
                    InfoRow(label: "Frequency", value: frequency, systemImage: "repeat", verbatim: true)
                }
                if let start = event.startDate {
                    InfoRow(label: "Started", value: start.shortDate, systemImage: "play.circle")
                }
                if let end = event.endDate {
                    InfoRow(label: "Ends", value: end.shortDate, systemImage: "stop.circle")
                }
                Toggle(isOn: Binding(
                    get: { event.isActiveMedication },
                    set: { active in
                        withAnimation(AppTheme.Motion.animation(AppTheme.Motion.confirm, reduceMotion: reduceMotion)) {
                            event.medicationStatus = (active ? MedicationStatus.active : .completed).rawValue
                            event.updatedAt = .now
                            try? context.save()
                        }
                    }
                )) {
                    Label("Currently taking", systemImage: "checkmark.circle")
                }
                .sensoryFeedback(.selection, trigger: event.medicationStatus)
            }
            if event.providerName == nil && event.eventType != .vaccination && event.eventType != .medication {
                InfoRow(label: "Type", value: event.eventType.title, systemImage: "tag")
            }
        }
        .card()
    }

    @ViewBuilder
    private func sourceCard(_ source: DocumentModel?, hadSource: Bool) -> some View {
        if let source {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Source").font(.headline)
                NavigationLink(value: Route.document(source.id)) {
                    HStack(spacing: AppTheme.Spacing.md) {
                        DocumentThumbnail(document: source, size: 56)
                            .zoomSource(id: Route.document(source.id))
                        VStack(alignment: .leading, spacing: 4) {
                            SourceBadge(title: source.docType.title)
                            Text(source.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text("Open the original to verify").font(.caption).foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .card()
        } else if hadSource {
            Label("The source document was deleted.", systemImage: "doc.questionmark")
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .card()
        } else {
            Label("Added by hand — no source document", systemImage: "hand.raised")
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .card()
        }
    }

    private func remindersCard(_ event: HealthEventModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionHeader(title: "Reminders", actionTitle: "Add") { addReminder(for: event) }
            if reminders.isEmpty {
                Text(event.nextDueDate != nil ? "The document states a next due date. Add a reminder?" : "No reminders for this record.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            ForEach(reminders) { reminder in
                Button { appState.sheet = .editReminder(reminder.id) } label: {
                    HStack {
                        Label(reminder.title, systemImage: reminder.type.symbol)
                        Spacer()
                        DueBadge(date: reminder.dueDate, isCompleted: reminder.state == .completed)
                    }
                    .frame(minHeight: AppTheme.Size.minTouch)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private func addReminder(for event: HealthEventModel) {
        let type: ReminderType = switch event.eventType {
        case .vaccination: .vaccination
        case .medication: .medication
        case .veterinaryVisit: .veterinaryAppointment
        default: .custom
        }
        let title = event.eventType == .vaccination ? "\(event.title) booster" : event.title
        appState.sheet = .newReminder(ReminderDraft(
            title: title,
            type: type,
            dueDate: event.nextDueDate ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now,
            healthEventId: event.id
        ))
    }
}
