import Foundation
import SwiftData

@Model
final class ExtractedFieldModel {
    @Attribute(.unique) var id: UUID
    var documentId: UUID
    var fieldName: String
    var fieldValue: String?
    var sourceText: String?
    var pageNumber: Int?
    var confidence: String?
    var isAmbiguous: Bool
    var reviewStatus: String
    /// Groups fields that belong to one record (e.g. "vaccination-0"), so a certificate
    /// listing two vaccines yields two reviewable records.
    var groupKey: String?
    /// Preserves extraction order for stable review layout.
    var sortOrder: Int = 0

    init(
        id: UUID = UUID(),
        documentId: UUID,
        fieldName: String,
        fieldValue: String? = nil,
        sourceText: String? = nil,
        pageNumber: Int? = nil,
        confidence: String? = nil,
        isAmbiguous: Bool = false,
        reviewStatus: String = ReviewStatus.pending.rawValue,
        groupKey: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.documentId = documentId
        self.fieldName = fieldName
        self.fieldValue = fieldValue
        self.sourceText = sourceText
        self.pageNumber = pageNumber
        self.confidence = confidence
        self.isAmbiguous = isAmbiguous
        self.reviewStatus = reviewStatus
        self.groupKey = groupKey
        self.sortOrder = sortOrder
    }
}
