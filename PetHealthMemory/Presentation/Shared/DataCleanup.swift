import Foundation
import SwiftData

/// Deletion with associated-file and notification cleanup (PRD F13, US-02).
@MainActor
enum DataCleanup {
    struct PetFootprint {
        var events = 0, documents = 0, reminders = 0, weights = 0
        var summary: String {
            "\(events) records, \(documents) documents, \(reminders) reminders and \(weights) weight entries"
        }
    }

    static func footprint(of petID: UUID, in context: ModelContext) -> PetFootprint {
        PetFootprint(
            events: (try? context.fetchCount(FetchDescriptor<HealthEventModel>(predicate: #Predicate { $0.petId == petID }))) ?? 0,
            documents: (try? context.fetchCount(FetchDescriptor<DocumentModel>(predicate: #Predicate { $0.petId == petID }))) ?? 0,
            reminders: (try? context.fetchCount(FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.petId == petID }))) ?? 0,
            weights: (try? context.fetchCount(FetchDescriptor<WeightEntryModel>(predicate: #Predicate { $0.petId == petID }))) ?? 0
        )
    }

    static func delete(document: DocumentModel, in context: ModelContext, container: AppContainer) throws {
        let docID = document.id
        // Records stay (user-confirmed data) but lose their source link.
        let linked = try context.fetch(FetchDescriptor<HealthEventModel>(predicate: #Predicate { $0.sourceDocumentId == docID }))
        linked.forEach { $0.sourceDocumentId = nil }
        try context.delete(model: ExtractedFieldModel.self, where: #Predicate<ExtractedFieldModel> { $0.documentId == docID })
        try? container.fileStorage.deleteFile(relativePath: document.filePath)
        context.delete(document)
        try context.save()
    }

    static func delete(event: HealthEventModel, in context: ModelContext, container: AppContainer) async throws {
        let eventID = event.id
        let reminders = try context.fetch(FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.healthEventId == eventID }))
        for reminder in reminders { reminder.healthEventId = nil }
        context.delete(event)
        try context.save()
    }

    static func delete(reminder: ReminderModel, in context: ModelContext, container: AppContainer) async throws {
        await container.notificationService.cancel(reminderId: reminder.id)
        context.delete(reminder)
        try context.save()
    }

    static func delete(petID: UUID, in context: ModelContext, container: AppContainer) async throws {
        let documents = try context.fetch(FetchDescriptor<DocumentModel>(predicate: #Predicate { $0.petId == petID }))
        for doc in documents {
            let docID = doc.id
            try context.delete(model: ExtractedFieldModel.self, where: #Predicate<ExtractedFieldModel> { $0.documentId == docID })
            try? container.fileStorage.deleteFile(relativePath: doc.filePath)
            context.delete(doc)
        }
        let reminders = try context.fetch(FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.petId == petID }))
        for reminder in reminders {
            await container.notificationService.cancel(reminderId: reminder.id)
            context.delete(reminder)
        }
        try context.delete(model: HealthEventModel.self, where: #Predicate<HealthEventModel> { $0.petId == petID })
        try context.delete(model: WeightEntryModel.self, where: #Predicate<WeightEntryModel> { $0.petId == petID })
        if let pet = try context.fetch(FetchDescriptor<PetModel>(predicate: #Predicate { $0.id == petID })).first {
            if let photo = pet.photoPath { try? container.fileStorage.deleteFile(relativePath: photo) }
            context.delete(pet)
        }
        try context.save()
    }

    static func clearAllData(in context: ModelContext, container: AppContainer) async throws {
        let pets = try context.fetch(FetchDescriptor<PetModel>())
        for pet in pets { try await delete(petID: pet.id, in: context, container: container) }
        try context.delete(model: CareProviderModel.self)
        try context.save()
    }
}
