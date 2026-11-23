import SwiftData
import SwiftUI

/// Screen 15 — Settings & Data Management (sync mode, privacy, notifications, export, clear data).
struct SettingsView: View {
    var showsDoneButton = true

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @AppStorage("syncMode") private var syncModeRaw = SyncMode.localOnly.rawValue
    #if DEBUG
    @AppStorage(FoundationModelExtractionService.simulateKey) private var simulateExtraction = false
    #endif
    @State private var authorization: NotificationAuthorization = .notDetermined
    @State private var confirmClear = false
    @State private var confirmClearFinal = false
    @State private var exportURL: URL?
    @State private var exportError: String?

    private var syncMode: Binding<SyncMode> {
        Binding(get: { SyncMode(rawValue: syncModeRaw) ?? .localOnly }, set: { syncModeRaw = $0.rawValue })
    }

    var body: some View {
        Form {
            Section {
                Picker("Sync", selection: syncMode) {
                    Label("This device only", systemImage: "iphone").tag(SyncMode.localOnly)
                    Label("iCloud", systemImage: "icloud").tag(SyncMode.iCloud)
                    Label("Pet Health Memory account", systemImage: "person.crop.circle").tag(SyncMode.backend)
                }
                syncStatusRow
            } header: {
                Text("Sync")
            } footer: {
                Text(syncFooter)
            }

            Section("Privacy") {
                privacyRow("Text recognition", onDevice: true)
                privacyRow("Auto-fill from documents", onDevice: container.extractionService.isAvailableOnDevice)
                LabeledContent("Analytics & tracking", value: String(localized: "None"))
            }

            Section("Notifications") {
                LabeledContent("Reminder alerts", value: authorizationText)
                if authorization == .denied {
                    Button("Open system settings") { SystemSettings.open() }
                } else if authorization == .notDetermined {
                    Button("Allow reminder alerts") {
                        Task {
                            _ = try? await container.notificationService.requestAuthorization()
                            authorization = await container.notificationService.authorizationStatus()
                        }
                    }
                }
            }

            Section {
                Button("Export all data (JSON)", action: exportAll)
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Share export file", systemImage: "square.and.arrow.up") }
                }
                if let exportError { Text(exportError).foregroundStyle(AppTheme.Colors.dangerText) }
                Button("Delete all data on this device…", role: .destructive) { confirmClear = true }
                    .foregroundStyle(AppTheme.Colors.dangerText)
            } header: {
                Text("Your data")
            } footer: {
                Text("Exports include every pet, record, reminder and weight entry. Original files stay in Documents.")
            }

            #if DEBUG
            Section("Developer") {
                Toggle("Simulate detail extraction", isOn: $simulateExtraction)
                Text("Returns sample fields so the review screen can be tested before Foundation Models is wired up.")
                    .font(.appCaption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            #endif

            Section {
                MedicalDisclaimer()
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .canvasBackground()
        .navigationTitle("Settings")
        .inlineTitleOnPhone()
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task { authorization = await container.notificationService.authorizationStatus() }
        .confirmationDialog("Delete all data?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Continue", role: .destructive) { confirmClearFinal = true }
        } message: {
            Text("Every pet, record, reminder and original document on this device will be removed.")
        }
        .alert("This can't be undone", isPresented: $confirmClearFinal) {
            Button("Delete everything", role: .destructive) {
                Task { try? await DataCleanup.clearAllData(in: context, container: container) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Consider exporting your data first.")
        }
    }

    /// One explicit row (a conditional inside LabeledContent laid out as a tall, mostly empty cell).
    private func privacyRow(_ title: LocalizedStringKey, onDevice: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
            Text(title)
            Spacer(minLength: AppTheme.Spacing.sm)
            if onDevice {
                Label("On this device", systemImage: "checkmark.shield")
                    .foregroundStyle(AppTheme.Colors.successText)
            } else {
                Text("Not on this device — you type the details")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }

    private var syncFooter: String {
        switch SyncMode(rawValue: syncModeRaw) ?? .localOnly {
        case .localOnly: String(localized: "Nothing leaves this device. You can turn sync on at any time.")
        case .iCloud: String(localized: "Records and documents sync privately through your iCloud account across iPhone, iPad and Mac.")
        case .backend: String(localized: "Needed for sharing with sitters or family. Requires Sign in with Apple.")
        }
    }

    @ViewBuilder
    private var syncStatusRow: some View {
        switch SyncMode(rawValue: syncModeRaw) ?? .localOnly {
        case .localOnly:
            EmptyView()
        case .iCloud, .backend:
            // TODO(Sprint 7): bind to SyncEngineProtocol status (synced / syncing / offline — saved locally).
            Label("Sync is coming soon — data stays local for now", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(AppTheme.Colors.warningText)
        }
    }

    private var authorizationText: String {
        switch authorization {
        case .authorized: String(localized: "On")
        case .denied: String(localized: "Off")
        case .notDetermined: String(localized: "Not set up")
        }
    }

    private func exportAll() {
        do {
            exportURL = try DataExport.writeJSON(context: context)
            exportError = nil
        } catch {
            exportError = String(localized: "Export failed. Please try again.")
        }
    }
}

/// User-initiated full JSON export (PRD F13 / §10).
@MainActor
enum DataExport {
    struct Payload: Encodable {
        struct Pet: Encodable { let id: UUID; let name, species: String; let breed: String?; let birthDate: Date?; let sex, microchipNumber, notes: String?; let weightUnit: String }
        struct Event: Encodable {
            let id, petId: UUID; let type, title: String; let eventDate: Date; let notes, providerName: String?
            let sourceDocumentId: UUID?; let nextDueDate: Date?; let dosageText, frequencyText: String?
            let startDate, endDate: Date?; let medicationStatus: String?
        }
        struct Reminder: Encodable { let id, petId: UUID; let healthEventId: UUID?; let title, reminderType: String; let dueDate: Date; let recurrenceRule: String?; let status: String }
        struct Weight: Encodable { let id, petId: UUID; let weight: Double; let unit: String; let measurementDate: Date; let notes: String? }
        struct Document: Encodable { let id, petId: UUID; let title: String?; let originalFileName, mimeType, documentType: String; let ocrText: String?; let createdAt: Date }

        let exportedAt: Date
        let pets: [Pet]; let healthEvents: [Event]; let reminders: [Reminder]; let weights: [Weight]; let documents: [Document]
    }

    static func writeJSON(context: ModelContext) throws -> URL {
        let payload = Payload(
            exportedAt: .now,
            pets: try context.fetch(FetchDescriptor<PetModel>()).map {
                .init(id: $0.id, name: $0.name, species: $0.species, breed: $0.breed, birthDate: $0.birthDate, sex: $0.sex,
                      microchipNumber: $0.microchipNumber, notes: $0.notes, weightUnit: $0.weightUnit)
            },
            healthEvents: try context.fetch(FetchDescriptor<HealthEventModel>()).map {
                .init(id: $0.id, petId: $0.petId, type: $0.type, title: $0.title, eventDate: $0.eventDate, notes: $0.notes,
                      providerName: $0.providerName, sourceDocumentId: $0.sourceDocumentId, nextDueDate: $0.nextDueDate,
                      dosageText: $0.dosageText, frequencyText: $0.frequencyText, startDate: $0.startDate, endDate: $0.endDate,
                      medicationStatus: $0.medicationStatus)
            },
            reminders: try context.fetch(FetchDescriptor<ReminderModel>()).map {
                .init(id: $0.id, petId: $0.petId, healthEventId: $0.healthEventId, title: $0.title, reminderType: $0.reminderType,
                      dueDate: $0.dueDate, recurrenceRule: $0.recurrenceRule, status: $0.status)
            },
            weights: try context.fetch(FetchDescriptor<WeightEntryModel>()).map {
                .init(id: $0.id, petId: $0.petId, weight: $0.weight, unit: $0.unit, measurementDate: $0.measurementDate, notes: $0.notes)
            },
            documents: try context.fetch(FetchDescriptor<DocumentModel>()).map {
                .init(id: $0.id, petId: $0.petId, title: $0.title, originalFileName: $0.originalFileName, mimeType: $0.mimeType,
                      documentType: $0.documentType, ocrText: $0.ocrText, createdAt: $0.createdAt)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PetHealthMemory-export.json")
        try encoder.encode(payload).write(to: url, options: .atomic)
        return url
    }
}
