import SwiftData

enum ModelContainerFactory {
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([
            PetModel.self,
            DocumentModel.self,
            ExtractedFieldModel.self,
            HealthEventModel.self,
            ReminderModel.self,
            WeightEntryModel.self,
            CareProviderModel.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }
    }
}
