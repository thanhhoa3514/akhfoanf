import Foundation

protocol PetRepositoryProtocol {
    func fetchAll() throws -> [PetModel]
    func fetch(by id: UUID) throws -> PetModel?
    func save(_ pet: PetModel) throws
    func delete(_ pet: PetModel) throws
}
