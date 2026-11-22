import SwiftData
import SwiftUI

/// macOS / iPad sidebar: pet selector on top, sections below, quick actions at the bottom.
struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \PetModel.createdAt) private var pets: [PetModel]
    @Query private var documents: [DocumentModel]
    @Query private var reminders: [ReminderModel]

    private var reviewCount: Int {
        documents.filter { $0.petId == appState.selectedPetID && $0.status.needsReview }.count
    }
    private var overdueCount: Int {
        reminders.filter { $0.petId == appState.selectedPetID && $0.isOpen && $0.dueDate < .now }.count
    }

    var body: some View {
        @Bindable var appState = appState
        List(selection: Binding<AppSection?>(get: { appState.section }, set: { if let s = $0 { appState.section = s } })) {
            Section("Pets") {
                ForEach(pets) { pet in
                    Button {
                        appState.switchPet(to: pet.id)
                    } label: {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            PetAvatar(pet: pet, size: 28)
                            Text(pet.name)
                                .fontWeight(pet.id == appState.selectedPetID ? .semibold : .regular)
                            Spacer()
                            if pet.id == appState.selectedPetID {
                                Image(systemName: "checkmark").foregroundStyle(AppTheme.Colors.brandText)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(pet.id == appState.selectedPetID ? .isSelected : [])
                }
                Button { appState.sheet = .newPet } label: {
                    Label("Add pet", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.Colors.brandText)
            }

            Section("Records") {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .badge(badge(for: section))
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Pet Health Memory")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: AppTheme.Spacing.sm) {
                Button { appState.sheet = .capture(source: nil) } label: {
                    Label("Import Document", systemImage: "doc.badge.plus")
                        #if os(macOS)
                        .frame(maxWidth: .infinity)
                        #endif
                }
                #if os(macOS)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                #else
                .buttonStyle(.primary)
                #endif
                .help("Import a PDF or photo (⌘I). You can also drop files onto Documents.")
                #if os(iOS)
                Button { appState.sheet = .settings } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.secondary)
                #endif
            }
            .padding(AppTheme.Spacing.md)
        }
    }

    private func badge(for section: AppSection) -> Int {
        switch section {
        case .documents: reviewCount
        case .reminders: overdueCount
        default: 0
        }
    }
}
