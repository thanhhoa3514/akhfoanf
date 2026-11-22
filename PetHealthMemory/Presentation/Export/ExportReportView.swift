import SwiftData
import SwiftUI

/// Screen 14 — PDF Health Report Export (offline, PRD F12).
struct ExportReportView: View {
    let petID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @Query private var pets: [PetModel]
    @Query private var events: [HealthEventModel]
    @Query private var weights: [WeightEntryModel]
    @Query private var documents: [DocumentModel]

    @State private var range: RangeOption = .allTime
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var options = PDFReportOptions()
    @State private var reportURL: URL?
    @State private var errorMessage: String?
    @State private var isGenerating = false

    enum RangeOption: String, CaseIterable, Identifiable {
        case allTime = "All time", last12Months = "Last 12 months", last3Months = "Last 3 months", custom = "Custom"
        var id: String { rawValue }
    }

    init(petID: UUID) {
        self.petID = petID
        _pets = Query(filter: #Predicate<PetModel> { $0.id == petID })
        _events = Query(filter: #Predicate<HealthEventModel> { $0.petId == petID })
        _weights = Query(filter: #Predicate<WeightEntryModel> { $0.petId == petID })
        _documents = Query(filter: #Predicate<DocumentModel> { $0.petId == petID })
    }

    private var resolvedOptions: PDFReportOptions {
        var resolved = options
        let calendar = Calendar.current
        switch range {
        case .allTime: resolved.startDate = nil; resolved.endDate = nil
        case .last12Months: resolved.startDate = calendar.date(byAdding: .month, value: -12, to: .now); resolved.endDate = nil
        case .last3Months: resolved.startDate = calendar.date(byAdding: .month, value: -3, to: .now); resolved.endDate = nil
        case .custom:
            resolved.startDate = calendar.startOfDay(for: customStart)
            resolved.endDate = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: customEnd))
        }
        return resolved
    }

    private var eventCount: Int {
        let o = resolvedOptions
        return events.filter { e in
            (o.startDate.map { e.eventDate >= $0 } ?? true) && (o.endDate.map { e.eventDate <= $0 } ?? true)
        }.count
    }

    var body: some View {
        Form {
            Section("Date range") {
                Picker("Range", selection: $range) {
                    ForEach(RangeOption.allCases) { Text($0.rawValue).tag($0) }
                }
                if range == .custom {
                    DatePicker("From", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                    DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                }
                LabeledContent("Records in range", value: "\(eventCount)")
                    .contentTransition(.numericText())
            }
            Section("Include") {
                Toggle("Pet profile", isOn: $options.includeProfile)
                Toggle("Vaccinations", isOn: $options.includeVaccinations)
                Toggle("Medications", isOn: $options.includeMedications)
                Toggle("Vet visits", isOn: $options.includeVisits)
                Toggle("Other health events", isOn: $options.includeOtherEvents)
                Toggle("Weight", isOn: $options.includeWeights)
                Toggle("Notes", isOn: $options.includeNotes)
                Toggle("Document references", isOn: $options.includeDocumentReferences)
            }
            Section {
                Button(action: generate) {
                    HStack {
                        if isGenerating { ProgressView().controlSize(.small) }
                        Text(reportURL == nil ? "Create PDF" : "Create again")
                    }
                }
                .buttonStyle(.primary)
                .disabled(isGenerating || pets.first == nil)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if let reportURL {
                    ShareLink(item: reportURL) {
                        Label("Share PDF", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(AppTheme.Colors.dangerText)
                }
            } footer: {
                Label("Created on this device — no internet needed.", systemImage: "lock.shield")
            }

            if let reportURL {
                Section("Preview") {
                    PDFKitView(url: reportURL)
                        .frame(height: 420)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .canvasBackground()
        .navigationTitle("Health Report")
        .inlineTitleOnPhone()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
        .onChange(of: options) { _, _ in reportURL = nil }
        .onChange(of: range) { _, _ in reportURL = nil }
        .onChange(of: customStart) { _, _ in reportURL = nil }
        .onChange(of: customEnd) { _, _ in reportURL = nil }
    }

    private func generate() {
        guard let pet = pets.first else { return }
        isGenerating = true
        errorMessage = nil
        // Yield one frame so the spinner shows before rendering on the main actor.
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            do {
                reportURL = try container.pdfService.generateReport(
                    pet: pet, events: events, weights: weights, documents: documents, options: resolvedOptions
                )
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "The PDF couldn't be created."
            }
            isGenerating = false
        }
    }
}
