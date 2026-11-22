import Foundation

protocol ReminderRepositoryProtocol {
    func fetchAll(for petId: UUID?, status: ReminderStatus?) throws -> [ReminderModel]
    func save(_ reminder: ReminderModel) throws
    func delete(_ reminder: ReminderModel) throws
}
