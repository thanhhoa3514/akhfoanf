import Foundation
import SwiftData

@Model
final class WeightEntryModel {
    @Attribute(.unique) var id: UUID
    var petId: UUID
    var weight: Double
    var unit: String
    var measurementDate: Date
    var notes: String?

    init(
        id: UUID = UUID(),
        petId: UUID,
        weight: Double,
        unit: String = WeightUnit.kg.rawValue,
        measurementDate: Date = .now,
        notes: String? = nil
    ) {
        self.id = id
        self.petId = petId
        self.weight = weight
        self.unit = unit
        self.measurementDate = measurementDate
        self.notes = notes
    }
}
