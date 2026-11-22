import Charts
import SwiftData
import SwiftUI

/// Screen 6 — Pet Profile Detail. Also the default detail pane for Home on macOS / iPad.
struct PetProfileDetailView: View {
    let petID: UUID

    @Environment(\.isCompactLayout) private var isCompact
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(AppContainer.self) private var container
    @Query private var pets: [PetModel]
    @Query private var weights: [WeightEntryModel]
    @State private var confirmDelete = false
    @State private var footprint = DataCleanup.PetFootprint()

    init(petID: UUID) {
        self.petID = petID
        _pets = Query(filter: #Predicate<PetModel> { $0.id == petID })
        _weights = Query(filter: #Predicate<WeightEntryModel> { $0.petId == petID }, sort: \.measurementDate)
    }

    var body: some View {
        if let pet = pets.first {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    header(pet)
                    details(pet)
                    weightCard(pet)
                    if let notes = pet.notes {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            Text("Notes").font(.headline)
                            Text(notes).foregroundStyle(AppTheme.Colors.textPrimary).textSelection(.enabled)
                        }
                        .card()
                    }
                    // iPhone: at the end of the profile. Wide layouts: in the toolbar's "…" menu,
                    // so a destructive action never sits in the always-visible Home detail column.
                    if isCompact {
                        Button(role: .destructive, action: requestDelete) {
                            Label("Delete \(pet.name)'s profile", systemImage: "trash")
                                .frame(maxWidth: .infinity, minHeight: AppTheme.Size.minTouch)
                        }
                        .foregroundStyle(AppTheme.Colors.dangerText)
                    }
                }
                .padding(AppTheme.Spacing.lg)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .canvasBackground()
            .navigationTitle(pet.name)
            .inlineTitleOnPhone()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { appState.sheet = .editPet(petID) }
                }
                if !isCompact {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Delete \(pet.name)'s Profile…", systemImage: "trash", role: .destructive, action: requestDelete)
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog("Delete \(pet.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete profile and all data", role: .destructive) {
                    Task { try? await DataCleanup.delete(petID: petID, in: context, container: container) }
                }
            } message: {
                Text("This permanently removes \(footprint.summary), including original files. Export a PDF first if you need a copy.")
            }
        } else {
            ContentUnavailableView("Pet not found", systemImage: "pawprint")
        }
    }

    private func requestDelete() {
        footprint = DataCleanup.footprint(of: petID, in: context)
        confirmDelete = true
    }

    private func header(_ pet: PetModel) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            PetAvatar(pet: pet, size: 104)
            Text(pet.name).font(.title.weight(.bold))
            Text(pet.subtitle).font(.subheadline).foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppTheme.Spacing.md)
    }

    private func details(_ pet: PetModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if let birth = pet.birthDate {
                InfoRow(label: "Date of birth", value: birth.shortDate, systemImage: "birthday.cake")
            }
            InfoRow(label: "Sex", value: pet.sex ?? "Not set", systemImage: "circle.lefthalf.filled")
            if let chip = pet.microchipNumber {
                InfoRow(label: "Microchip", value: chip, systemImage: "barcode")
            }
            InfoRow(label: "Weight unit", value: pet.weightUnit, systemImage: "scalemass")
        }
        .card()
    }

    private func weightCard(_ pet: PetModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text("Weight").font(.headline)
                Spacer()
                if let last = weights.last {
                    Text("\(last.weight.formatted(.number.precision(.fractionLength(0...2)))) \(last.unit)")
                        .font(.headline)
                        .contentTransition(.numericText())
                }
                Image(systemName: "chevron.right").foregroundStyle(AppTheme.Colors.textSecondary)
            }
            if weights.count >= 2 {
                Chart(weights) { entry in
                    LineMark(x: .value("Date", entry.measurementDate), y: .value("Weight", entry.weight))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(AppTheme.Colors.brandPrimary)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 56)
                .accessibilityLabel("Weight trend")
            } else {
                Text(weights.isEmpty ? "No weight logged yet" : "Log one more entry to see a trend")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .card()
        .routeButton(.weightLog(pet.id))
    }
}

/// Pet switcher menu (PRD §11 — pet selection accessible from the main interface).
struct PetSwitcherMenu<Label: View>: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \PetModel.createdAt) private var pets: [PetModel]
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            ForEach(pets) { pet in
                Button {
                    withAnimation(AppTheme.Motion.animation(AppTheme.Motion.quick, reduceMotion: reduceMotion)) {
                        appState.switchPet(to: pet.id)
                    }
                } label: {
                    if pet.id == appState.selectedPetID {
                        SwiftUI.Label(pet.name, systemImage: "checkmark")
                    } else {
                        Text(pet.name)
                    }
                }
            }
            Divider()
            Button { appState.sheet = .newPet } label: {
                SwiftUI.Label("Add another pet", systemImage: "plus")
            }
        } label: {
            label()
        }
        .accessibilityLabel("Switch pet")
    }
}
