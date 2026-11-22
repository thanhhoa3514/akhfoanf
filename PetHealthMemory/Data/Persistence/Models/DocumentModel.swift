import Foundation
import SwiftData

@Model
final class DocumentModel {
    @Attribute(.unique) var id: UUID
    var petId: UUID
    var filePath: String
    var originalFileName: String
    /// User-facing title (searchable). Defaults to the file name.
    var title: String?
    var mimeType: String
    var documentType: String
    var ocrText: String?
    var pageCount: Int?
    var processingStatus: String
    var checksum: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        petId: UUID,
        filePath: String,
        originalFileName: String,
        title: String? = nil,
        mimeType: String,
        documentType: String = DocumentType.other.rawValue,
        ocrText: String? = nil,
        pageCount: Int? = nil,
        processingStatus: String = ProcessingStatus.pending.rawValue,
        checksum: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.petId = petId
        self.filePath = filePath
        self.originalFileName = originalFileName
        self.title = title
        self.mimeType = mimeType
        self.documentType = documentType
        self.ocrText = ocrText
        self.pageCount = pageCount
        self.processingStatus = processingStatus
        self.checksum = checksum
        self.createdAt = createdAt
    }
}
