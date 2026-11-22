import Foundation
import SwiftData

@Model
final class PetModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var species: String
    var breed: String?
    var birthDate: Date?
    var sex: String?
    var microchipNumber: String?
    var photoPath: String?
    var weightUnit: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        species: String,
        breed: String? = nil,
        birthDate: Date? = nil,
        sex: String? = nil,
        microchipNumber: String? = nil,
        photoPath: String? = nil,
        weightUnit: String = WeightUnit.kg.rawValue,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.species = species
        self.breed = breed
        self.birthDate = birthDate
        self.sex = sex
        self.microchipNumber = microchipNumber
        self.photoPath = photoPath
        self.weightUnit = weightUnit
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
