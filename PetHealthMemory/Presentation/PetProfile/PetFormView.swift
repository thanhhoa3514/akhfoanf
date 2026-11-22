import PhotosUI
import SwiftData
import SwiftUI

/// Screen 5 — Create / Edit Pet Profile. First-launch variant is the whole onboarding (< 30 s, US-01).
struct PetFormView: View {
    enum Mode: Equatable {
        case firstLaunch
        case create
        case edit(UUID)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppContainer.self) private var container

    @State private var name = ""
    @State private var species = "Dog"
    @State private var customSpecies = ""
    @State private var breed = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -2, to: .now) ?? .now
    @State private var sex = "Unknown"
    @State private var weightUnit: WeightUnit = .kg
    @State private var microchip = ""
    @State private var notes = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var existing: PetModel?
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    private static let speciesOptions = ["Dog", "Cat", "Rabbit", "Bird", "Fish", "Other"]
    private static let sexOptions = ["Unknown", "Female", "Male", "Female (spayed)", "Male (neutered)"]

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var resolvedSpecies: String {
        species == "Other" ? customSpecies.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "Other" : species
    }

    var body: some View {
        Form {
            if mode == .firstLaunch {
                Section {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Who are we caring for?")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Label("Everything stays on this device. No account needed.", systemImage: "lock.shield")
                            .font(.appSubheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                HStack(spacing: AppTheme.Spacing.lg) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        avatar
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photoData == nil ? String(localized: "Add photo") : String(localized: "Change photo"))

                    TextField("Name", text: $name)
                        .font(.title3.weight(.semibold))
                        .focused($nameFocused)
                        .submitLabel(.done)
                }
                Picker("Species", selection: $species) {
                    ForEach(Self.speciesOptions, id: \.self) { Text(PetModel.displayName(species: $0)) }
                }
                if species == "Other" {
                    TextField("Species", text: $customSpecies)
                }
                // Labelled rows: a filled-in field has no placeholder left to say what it is.
                LabeledContent("Breed") {
                    TextField("Optional", text: $breed).multilineTextAlignment(.trailing)
                }
            }

            Section("Details — all optional") {
                Toggle("Date of birth", isOn: $hasBirthDate.animation())
                if hasBirthDate {
                    DatePicker("Born", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                }
                Picker("Sex", selection: $sex) {
                    ForEach(Self.sexOptions, id: \.self) { Text(PetModel.displayName(sex: $0)) }
                }
                Picker("Weight unit", selection: $weightUnit) {
                    Text("kg").tag(WeightUnit.kg)
                    Text("lb").tag(WeightUnit.lb)
                }
                .pickerStyle(.segmented)
                LabeledContent("Microchip") {
                    TextField("Optional", text: $microchip)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.asciiCapable)
                        #endif
                }
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AppTheme.Colors.dangerText)
                }
            }

            if mode == .firstLaunch {
                Section {
                    Button("Create profile", action: save)
                        .buttonStyle(.primary)
                        .disabled(trimmedName.isEmpty)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .canvasBackground()
        .navigationTitle(navigationTitle)
        .inlineTitleOnPhone()
        .toolbar {
            if mode != .firstLaunch {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(trimmedName.isEmpty)
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    photoData = data
                }
            }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .firstLaunch: ""
        case .create: String(localized: "New Pet")
        case .edit: String(localized: "Edit Profile")
        }
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let photoData, let image = PlatformImage(data: photoData) {
                    Image(platformImage: image).resizable().scaledToFill()
                } else if let existing {
                    PetAvatar(pet: existing, size: 72)
                } else {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.Colors.brandAccent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.Colors.brandAccent.opacity(0.15))
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())

            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.white, AppTheme.Colors.brandPrimary)
        }
    }

    private func load() {
        guard case .edit(let id) = mode else {
            nameFocused = true
            return
        }
        let descriptor = FetchDescriptor<PetModel>(predicate: #Predicate { $0.id == id })
        guard let pet = try? context.fetch(descriptor).first else { return }
        existing = pet
        name = pet.name
        if Self.speciesOptions.contains(pet.species) {
            species = pet.species
        } else {
            species = "Other"
            customSpecies = pet.species
        }
        breed = pet.breed ?? ""
        hasBirthDate = pet.birthDate != nil
        birthDate = pet.birthDate ?? birthDate
        sex = pet.sex ?? "Unknown"
        weightUnit = WeightUnit(rawValue: pet.weightUnit) ?? .kg
        microchip = pet.microchipNumber ?? ""
        notes = pet.notes ?? ""
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        do {
            var photoPath = existing?.photoPath
            if let photoData {
                let jpeg = PlatformImage(data: photoData)?.jpegDataCompat() ?? photoData
                if let old = photoPath { try? container.fileStorage.deleteFile(relativePath: old) }
                photoPath = try container.fileStorage.saveFile(data: jpeg, fileName: "pet.jpg", subdirectory: "photos")
            }

            let pet = existing ?? PetModel(name: trimmedName, species: resolvedSpecies)
            pet.name = trimmedName
            pet.species = resolvedSpecies
            pet.breed = breed.nilIfEmpty
            pet.birthDate = hasBirthDate ? birthDate : nil
            pet.sex = sex == "Unknown" ? nil : sex
            pet.weightUnit = weightUnit.rawValue
            pet.microchipNumber = microchip.nilIfEmpty
            pet.notes = notes.nilIfEmpty
            pet.photoPath = photoPath
            pet.updatedAt = .now
            if existing == nil { context.insert(pet) }
            try context.save()
            appState.switchPet(to: pet.id)
            if mode != .firstLaunch { dismiss() }
        } catch {
            errorMessage = "Couldn't save the profile. Please try again."
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
