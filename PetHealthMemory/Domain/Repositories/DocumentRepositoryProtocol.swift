import Foundation

protocol DocumentRepositoryProtocol {
    func fetchAll(for petId: UUID) throws -> [DocumentModel]
    func fetch(by id: UUID) throws -> DocumentModel?
    func search(query: String, petId: UUID?) throws -> [DocumentModel]
    func save(_ document: DocumentModel) throws
    func delete(_ document: DocumentModel) throws
}
