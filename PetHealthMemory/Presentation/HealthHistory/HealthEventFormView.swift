import SwiftData
import SwiftUI

/// Screen 11 — Create / Edit Health Event. Type-specific fields; no schedules or dosages are generated.
struct HealthEventFormView: View {
    enum Mode {
        case create(petID: UUID, type: HealthEventType?)
        case edit(UUID)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CareProviderModel.clinicName) private var providers: [CareProviderModel]

    @State private var type: HealthEventType = .veterinaryVisit
    @State private var title = ""
    @State private var date = Date.now
    @State private var clinic = ""
    @State private var notes = ""
    @State private var hasNextDue = false
    @State private var nextDue = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var dosage = ""
    @State private var frequency = ""
    @State private var hasEnd = false
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    @State private var isActive = true
    @State private var existing: HealthEventModel?

    private var canSave: Bool { title.nilIfEmpty != nil }

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $type) {
                    ForEach(HealthEventType.allCases, id: \.self) { type in
                        Label(type.title, systemImage: type.symbol).tag(type)
                    }
                }
                TextField(titlePlaceholder, text: $title)
                DatePicker(type == .medication ? String(localized: "Start date") : String(localized: "Date"), selection: $date, displayedComponents: .date)
                TextField("Clinic (optional)", text: $clinic)
                if clinic.isEmpty, !providers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(providers.prefix(6)) { provider in
                                Button(provider.clinicName) { clinic = provider.clinicName }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }

            if type == .vaccination {
                Section {
                    Toggle("Next due date", isOn: $hasNextDue.animation())
                    if hasNextDue {
                        DatePicker("Due", selection: $nextDue, displayedComponents: .date)
                    }
                } footer: {
                    Text("Only add a due date your vet or the document states. The app never suggests vaccine schedules.")
                }
            }

            if type == .medication {
                Section {
                    TextField("Dosage, as written (e.g. 1 tablet)", text: $dosage)
                    TextField("Frequency, as written (e.g. twice daily)", text: $frequency)
                    Toggle("End date", isOn: $hasEnd.animation())
                    if hasEnd {
                        DatePicker("Ends", selection: $endDate, in: date..., displayedComponents: .date)
                    }
                    Toggle("Currently taking", isOn: $isActive)
                } footer: {
                    Text("Copy instructions exactly from the label or prescription. The app doesn't calculate dosages.")
                }
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...8)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .canvasBackground()
        .navigationTitle(existing == nil ? String(localized: "New Record") : String(localized: "Edit Record"))
        .inlineTitleOnPhone()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
        }
        .onAppear(perform: load)
    }

    private var titlePlaceholder: String {
        switch type {
        case .vaccination: "Vaccine name"
        case .medication: "Medication name"
        case .veterinaryVisit: "Reason for visit"
        case .allergy: "Allergic to…"
        case .laboratoryResult: "Test name"
        default: "Title"
        }
    }

    private func load() {
        switch mode {
        case .create(_, let presetType):
            if let presetType { type = presetType }
        case .edit(let id):
            let descriptor = FetchDescriptor<HealthEventModel>(predicate: #Predicate { $0.id == id })
            guard let event = try? context.fetch(descriptor).first else { return }
            existing = event
            type = event.eventType
            title = event.title
            date = event.startDate ?? event.eventDate
            clinic = event.providerName ?? ""
            notes = event.notes ?? ""
            hasNextDue = event.nextDueDate != nil
            nextDue = event.nextDueDate ?? nextDue
            dosage = event.dosageText ?? ""
            frequency = event.frequencyText ?? ""
            hasEnd = event.endDate != nil
            endDate = event.endDate ?? endDate
            isActive = event.isActiveMedication || event.eventType != .medication
        }
    }

    private func save() {
        let event: HealthEventModel
        if let existing {
            event = existing
        } else if case .create(let petID, _) = mode {
            event = HealthEventModel(petId: petID, type: type.rawValue, title: "", eventDate: date)
            context.insert(event)
        } else { return }

        event.type = type.rawValue
        event.title = title.nilIfEmpty ?? type.title
        event.eventDate = date
        event.providerName = clinic.nilIfEmpty
        event.notes = notes.nilIfEmpty
        event.nextDueDate = type == .vaccination && hasNextDue ? nextDue : nil
        event.dosageText = type == .medication ? dosage.nilIfEmpty : nil
        event.frequencyText = type == .medication ? frequency.nilIfEmpty : nil
        event.startDate = type == .medication ? date : nil
        event.endDate = type == .medication && hasEnd ? endDate : nil
        event.medicationStatus = type == .medication ? (isActive ? MedicationStatus.active : .completed).rawValue : nil
        event.updatedAt = .now
        CareProviderDirectory.remember(clinic: event.providerName, in: context)
        try? context.save()
        dismiss()
    }
}

/// Keeps a lightweight clinic directory for quick re-entry (CareProviderModel).
enum CareProviderDirectory {
    @MainActor
    static func remember(clinic: String?, in context: ModelContext) {
        guard let clinic else { return }
        let existing = (try? context.fetch(FetchDescriptor<CareProviderModel>())) ?? []
        guard !existing.contains(where: { $0.clinicName.caseInsensitiveCompare(clinic) == .orderedSame }) else { return }
        context.insert(CareProviderModel(clinicName: clinic))
    }
}
