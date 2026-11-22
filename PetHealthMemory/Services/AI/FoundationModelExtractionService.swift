import Foundation

/// Canonical extraction targets (PRD F04). Raw values are persisted in `ExtractedFieldModel.fieldName`
/// and sent to the backend unchanged.
enum ExtractionFieldKey: String, CaseIterable, Codable, Sendable {
    case documentType, petName, clinic, visitDate
    case vaccineName, vaccineDate, nextDueDate
    case medicationName, dosageText, frequencyText, startDate, endDate
    case diagnosisText, labResultText, weight, notes
}

struct ExtractedFieldDraft: Identifiable, Hashable, Sendable {
    let id: UUID
    var fieldName: String
    var fieldValue: String?
    var sourceText: String?
    var pageNumber: Int?
    var confidence: String?
    var isAmbiguous: Bool
    /// Groups fields belonging to one record, e.g. "vaccination-0".
    var groupKey: String?

    init(
        id: UUID = UUID(),
        fieldName: String,
        fieldValue: String?,
        sourceText: String? = nil,
        pageNumber: Int? = nil,
        confidence: String? = nil,
        isAmbiguous: Bool = false,
        groupKey: String? = nil
    ) {
        self.id = id
        self.fieldName = fieldName
        self.fieldValue = fieldValue
        self.sourceText = sourceText
        self.pageNumber = pageNumber
        self.confidence = confidence
        self.isAmbiguous = isAmbiguous
        self.groupKey = groupKey
    }
}

protocol ExtractionServiceProtocol {
    var isAvailableOnDevice: Bool { get }
    func extractFields(from ocrText: String) async throws -> [ExtractedFieldDraft]
}

/// Apple Foundation Models extraction service with explicit runtime availability check (Sprint 3).
final class FoundationModelExtractionService: ExtractionServiceProtocol {
    /// DEBUG-only switch (Settings ▸ Developer) that returns sample drafts so the review UI can be
    /// exercised before the real model integration lands. Never compiled into release builds.
    static let simulateKey = "debug.simulateExtraction"

    var isAvailableOnDevice: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: Self.simulateKey) { return true }
        #endif
        // TODO(Sprint 3): return SystemLanguageModel.default.availability == .available (iOS/macOS 26+).
        return false
    }

    func extractFields(from ocrText: String) async throws -> [ExtractedFieldDraft] {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: Self.simulateKey) { return Self.sampleDrafts }
        #endif
        // TODO(Sprint 3): Run structured @Generable extraction. Missing → nil, ambiguous → isAmbiguous.
        return []
    }

    #if DEBUG
    static let sampleDrafts: [ExtractedFieldDraft] = [
        .init(fieldName: ExtractionFieldKey.documentType.rawValue, fieldValue: DocumentType.vaccinationCertificate.rawValue, confidence: "high"),
        .init(fieldName: ExtractionFieldKey.petName.rawValue, fieldValue: "Bella", sourceText: "Patient: BELLA", pageNumber: 1, confidence: "high"),
        .init(fieldName: ExtractionFieldKey.clinic.rawValue, fieldValue: "Riverside Animal Clinic", sourceText: "RIVERSIDE ANIMAL CLINIC", pageNumber: 1, confidence: "high"),
        .init(fieldName: ExtractionFieldKey.visitDate.rawValue, fieldValue: "2026-11-14", sourceText: "Date: 14/11/2026", pageNumber: 1, confidence: "high"),
        .init(fieldName: ExtractionFieldKey.vaccineName.rawValue, fieldValue: "Rabies (Nobivac)", sourceText: "Rabies — Nobivac 1yr", pageNumber: 1, confidence: "high", groupKey: "vaccination-0"),
        .init(fieldName: ExtractionFieldKey.vaccineDate.rawValue, fieldValue: "2026-11-14", sourceText: "given 14/11/26", pageNumber: 1, confidence: "high", groupKey: "vaccination-0"),
        .init(fieldName: ExtractionFieldKey.nextDueDate.rawValue, fieldValue: nil, sourceText: "next due 11/12/27", pageNumber: 1, confidence: "low", isAmbiguous: true, groupKey: "vaccination-0"),
        .init(fieldName: ExtractionFieldKey.vaccineName.rawValue, fieldValue: "DHPPi", sourceText: "DHPPi booster", pageNumber: 1, confidence: "medium", groupKey: "vaccination-1"),
        .init(fieldName: ExtractionFieldKey.medicationName.rawValue, fieldValue: "Bravecto 500mg", sourceText: "Bravecto 500mg chew", pageNumber: 2, confidence: "high", groupKey: "medication-0"),
        .init(fieldName: ExtractionFieldKey.dosageText.rawValue, fieldValue: "1 chew", sourceText: "1 chew", pageNumber: 2, confidence: "high", groupKey: "medication-0"),
        .init(fieldName: ExtractionFieldKey.frequencyText.rawValue, fieldValue: "every 12 weeks", sourceText: "q12w", pageNumber: 2, confidence: "low", isAmbiguous: true, groupKey: "medication-0"),
        .init(fieldName: ExtractionFieldKey.weight.rawValue, fieldValue: "24.6 kg", sourceText: "Wt 24.6kg", pageNumber: 1, confidence: "high")
    ]
    #endif
}
