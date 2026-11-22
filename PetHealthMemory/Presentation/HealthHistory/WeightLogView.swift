import Charts
import SwiftData
import SwiftUI

/// Screen 16 — Weight Log & Chart (optional for MVP, PRD F10).
struct WeightLogView: View {
    let petID: UUID

    @Environment(\.modelContext) private var context
    @Query private var entries: [WeightEntryModel]
    @Query private var pets: [PetModel]
    @State private var showAdd = false
    @State private var editing: WeightEntryModel?

    init(petID: UUID) {
        self.petID = petID
        _entries = Query(filter: #Predicate<WeightEntryModel> { $0.petId == petID }, sort: \.measurementDate, order: .reverse)
        _pets = Query(filter: #Predicate<PetModel> { $0.id == petID })
    }

    private var unit: String { pets.first?.weightUnit ?? WeightUnit.kg.rawValue }

    var body: some View {
        RouteList {
            if entries.count >= 2 {
                Section {
                    Chart(entries) { entry in
                        LineMark(x: .value("Date", entry.measurementDate), y: .value("Weight", entry.weight))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(AppTheme.Colors.brandPrimary)
                        PointMark(x: .value("Date", entry.measurementDate), y: .value("Weight", entry.weight))
                            .foregroundStyle(AppTheme.Colors.brandPrimary)
                    }
                    .chartYAxisLabel(unit)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .accessibilityLabel("Weight over time")
                }
            }
            Section(entries.isEmpty ? "" : "Entries") {
                if entries.isEmpty {
                    ContentUnavailableView("No weight logged", systemImage: "scalemass", description: Text("Add an entry after each vet visit or weigh-in."))
                }
                ForEach(entries) { entry in
                    Button { editing = entry } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(entry.weight.formatted(.number.precision(.fractionLength(0...2)))) \(entry.unit)").font(.body.weight(.semibold))
                                if let notes = entry.notes { Text(notes).font(.appCaption).foregroundStyle(AppTheme.Colors.textSecondary) }
                            }
                            Spacer()
                            Text(entry.measurementDate.shortDate).foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    offsets.map { entries[$0] }.forEach { context.delete($0) }
                    try? context.save()
                }
            }
        }
        .navigationTitle("Weight")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Label("Add weight", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { NavigationStack { WeightEntryForm(petID: petID, unit: unit, entry: nil) } }
        .sheet(item: $editing) { entry in NavigationStack { WeightEntryForm(petID: petID, unit: unit, entry: entry) } }
    }
}

private struct WeightEntryForm: View {
    let petID: UUID
    let unit: String
    let entry: WeightEntryModel?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var weight: Double?
    @State private var date = Date.now
    @State private var notes = ""

    var body: some View {
        Form {
            HStack {
                TextField("Weight", value: $weight, format: .number)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Text(entry?.unit ?? unit).foregroundStyle(AppTheme.Colors.textSecondary)
            }
            DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
            TextField("Notes", text: $notes)
            if let entry {
                Button("Delete entry", role: .destructive) {
                    context.delete(entry)
                    try? context.save()
                    dismiss()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(entry == nil ? "Add Weight" : "Edit Weight")
        .inlineTitleOnPhone()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let weight, weight > 0 else { return }
                    let target = entry ?? WeightEntryModel(petId: petID, weight: weight, unit: unit)
                    target.weight = weight
                    target.measurementDate = date
                    target.notes = notes.nilIfEmpty
                    if entry == nil { context.insert(target) }
                    try? context.save()
                    dismiss()
                }
                .disabled((weight ?? 0) <= 0)
            }
        }
        .onAppear {
            if let entry {
                weight = entry.weight
                date = entry.measurementDate
                notes = entry.notes ?? ""
            }
        }
    }
}
