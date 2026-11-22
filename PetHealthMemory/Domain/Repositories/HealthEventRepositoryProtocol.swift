import Foundation

protocol HealthEventRepositoryProtocol {
    func fetchTimeline(for petId: UUID, type: HealthEventType?) throws -> [HealthEventModel]
    func fetch(by id: UUID) throws -> HealthEventModel?
    func search(query: String, petId: UUID?) throws -> [HealthEventModel]
    func save(_ event: HealthEventModel) throws
    func delete(_ event: HealthEventModel) throws
}
