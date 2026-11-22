import Foundation
import Observation
import SwiftData

extension ExtractionFieldKey {
    var label: String {
        switch self {
        case .documentType: String(localized: "Document type")
        case .petName: String(localized: "Pet name on document")
        case .clinic: String(localized: "Clinic")
        case .visitDate: String(localized: "Visit date")
        case .vaccineName: String(localized: "Vaccine")
        case .vaccineDate: String(localized: "Date given")
        case .nextDueDate: String(localized: "Next due")
        case .medicationName: String(localized: "Medication")
        case .dosageText: String(localized: "Dosage")
        case .frequencyText: String(localized: "Frequency")
        case .startDate: String(localized: "Start date")
        case .endDate: String(localized: "End date")
        case .diagnosisText: String(localized: "Diagnosis")
        case .labResultText: String(localized: "Lab result")
        case .weight: String(localized: "Weight")
        case .notes: String(localized: "Notes")
        }
    }

    var isDate: Bool { [.visitDate, .vaccineDate, .nextDueDate, .startDate, .endDate].contains(self) }
    /// Medication instructions are kept verbatim (PRD F04).
    var isVerbatim: Bool { self == .dosageText || self == .frequencyText }
    var isDocumentLevel: Bool { self == .documentType || self == .petName }

    var recordKind: ReviewRecordKind? {
        switch self {
        case .clinic, .visitDate, .notes: .visit
        case .vaccineName, .vaccineDate, .nextDueDate: .vaccination
        case .medicationName, .dosageText, .frequencyText, .startDate, .endDate: .medication
        case .diagnosisText: .diagnosis
        case .labResultText: .labResult
        case .weight: .weight
        case .documentType, .petName: nil
        }
    }
}

enum ReviewRecordKind: String, CaseIterable, Identifiable {
    case visit, vaccination, medication, diagnosis, labResult, weight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visit: String(localized: "Vet visit")
        case .vaccination: String(localized: "Vaccination")
        case .medication: String(localized: "Medication")
        case .diagnosis: String(localized: "Diagnosis")
        case .labResult: String(localized: "Lab result")
        case .weight: String(localized: "Weight")
        }
    }

    var eventType: HealthEventType {
        switch self {
        case .visit: .veterinaryVisit
        case .vaccination: .vaccination
        case .medication: .medication
        case .diagnosis: .diagnosis
        case .labResult: .laboratoryResult
        case .weight: .weight
        }
    }

    /// Field that becomes the record title (must be present).
    var primaryKey: ExtractionFieldKey {
        switch self {
        case .visit: .visitDate
        case .vaccination: .vaccineName
        case .medication: .medicationName
        case .diagnosis: .diagnosisText
        case .labResult: .labResultText
        case .weight: .weight
        }
    }

    /// Own date field, falling back to the document's visit date.
    /// Diagnosis / lab / weight have no dedicated date, so they may carry their own `visitDate`.
    var dateKey: ExtractionFieldKey {
        switch self {
        case .vaccination: .vaccineDate
        case .medication: .startDate
        case .visit, .diagnosis, .labResult, .weight: .visitDate
        }
    }

    var allowedKeys: [ExtractionFieldKey] {
        var keys = ExtractionFieldKey.allCases.filter { $0.recordKind == self }
        if !keys.contains(dateKey) { keys.append(dateKey) }
        return keys
    }
}

struct ReviewField: Identifiable, Equatable {
    let id: UUID
    let key: ExtractionFieldKey
    var value: String
    let originalValue: String?
    let sourceText: String?
    let pageNumber: Int?
    /// AI marked ambiguous / low confidence.
    let flagged: Bool
    /// User tapped "Looks right" or edited the value.
    var resolved: Bool
    /// Backed by a persisted ExtractedFieldModel (nil for user-added fields).
    let persistedID: UUID?

    var needsCheck: Bool { flagged && !resolved }
    var isEmpty: Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isEdited: Bool { value != (originalValue ?? "") }

    var dateValue: Date? { ReviewDate.parse(value) }
}

struct ReviewRecord: Identifiable, Equatable {
    let id = UUID()
    var kind: ReviewRecordKind
    var fields: [ReviewField]
    var included: Bool

    func field(_ key: ExtractionFieldKey) -> ReviewField? { fields.first { $0.key == key && !$0.isEmpty } }
}

enum ReviewDate {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Only accepts normalised ISO dates — ambiguous raw strings stay unparsed and flagged.
    static func parse(_ value: String) -> Date? { formatter.date(from: value.trimmingCharacters(in: .whitespaces)) }
    static func string(_ date: Date) -> String { formatter.string(from: date) }
}

struct SavedRecordSummary: Identifiable {
    let id: UUID
    let title: String
    let type: HealthEventType
    let date: Date
    let nextDueDate: Date?
}

/// Screen 9 state. Nothing becomes a HealthEvent until `confirm()` (PRD F05 — no auto-save).
@MainActor
@Observable
final class ExtractionReviewModel {
    var records: [ReviewRecord] = []
    var documentFields: [ReviewField] = []
    var documentType: DocumentType = .other
    private(set) var isManualMode = false
    private var removedPersistedIDs = Set<UUID>()
    /// The extracted `documentType` field is applied to the picker rather than shown as a row.
    private var documentTypeField: (id: UUID, original: String?)?

    // MARK: Load

    func load(document: DocumentModel, fields: [ExtractedFieldModel]) {
        documentType = document.docType
        isManualMode = fields.isEmpty
        let sorted = fields.sorted { $0.sortOrder < $1.sortOrder }

        var grouped: [String: ReviewRecord] = [:]
        var order: [String] = []
        var docLevel: [ReviewField] = []

        for model in sorted {
            guard let key = ExtractionFieldKey(rawValue: model.fieldName) else { continue }
            let rejected = model.reviewStatus == ReviewStatus.rejected.rawValue
            if rejected { continue }
            let field = ReviewField(
                id: model.id, key: key, value: model.fieldValue ?? "", originalValue: model.fieldValue,
                sourceText: model.sourceText, pageNumber: model.pageNumber,
                flagged: model.isAmbiguous || model.confidence == "low" || (model.fieldValue == nil && model.sourceText != nil),
                resolved: false, persistedID: model.id
            )
            if key.isDocumentLevel {
                if key == .documentType, let type = model.fieldValue.flatMap(DocumentType.init(rawValue:)) {
                    documentType = type
                    documentTypeField = (model.id, model.fieldValue)
                } else {
                    docLevel.append(field)
                }
                continue
            }
            guard let kind = key.recordKind else { continue }
            let groupKey = model.groupKey ?? "\(kind.rawValue)-0"
            if grouped[groupKey] == nil {
                grouped[groupKey] = ReviewRecord(kind: kind, fields: [], included: true)
                order.append(groupKey)
            }
            grouped[groupKey]?.fields.append(field)
        }

        documentFields = docLevel
        records = order.compactMap { grouped[$0] }

        // Visit records default off for certificates (avoid timeline clutter) unless they're the only record.
        let visitHeavyTypes: [DocumentType] = [.veterinaryVisitReport, .medicalRecord, .invoice]
        for index in records.indices where records[index].kind == .visit {
            records[index].included = visitHeavyTypes.contains(documentType) || records.count == 1
        }
    }

    // MARK: Derived

    /// Document-wide visit date (from the Visit record only).
    var visitDate: Date? {
        records.lazy.filter { $0.kind == .visit }.compactMap { $0.field(.visitDate)?.dateValue }.first
    }

    var clinic: String? {
        records.lazy.filter { $0.kind == .visit }.compactMap { $0.field(.clinic)?.value }.first
    }

    func resolvedDate(for record: ReviewRecord) -> Date? {
        if let date = record.field(record.kind.dateKey)?.dateValue { return date }
        return visitDate
    }

    func issues(for record: ReviewRecord) -> [String] {
        var issues: [String] = []
        if record.field(record.kind.primaryKey) == nil { issues.append(String(localized: "Add \(record.kind.primaryKey.label)")) }
        if resolvedDate(for: record) == nil { issues.append(String(localized: "Add a date")) }
        let unchecked = record.fields.filter(\.needsCheck).count
        if unchecked > 0 { issues.append(unchecked == 1 ? String(localized: "Check 1 field") : String(localized: "Check \(unchecked) fields")) }
        let badDates = record.fields.filter { $0.key.isDate && !$0.isEmpty && $0.dateValue == nil }.count
        if badDates > 0 { issues.append(String(localized: "Fix date format")) }
        return issues
    }

    var includedRecords: [ReviewRecord] { records.filter(\.included) }
    var blockingCount: Int { includedRecords.filter { !issues(for: $0).isEmpty }.count }
    var flaggedCount: Int { records.flatMap(\.fields).filter(\.needsCheck).count + documentFields.filter(\.needsCheck).count }
    var canSave: Bool { !includedRecords.isEmpty && blockingCount == 0 }

    var saveTitle: String {
        if includedRecords.isEmpty { return String(localized: "Select a record to save") }
        if blockingCount > 0 { return blockingCount == 1 ? "1 record needs attention" : "\(blockingCount) records need attention" }
        return includedRecords.count == 1 ? String(localized: "Save 1 record") : String(localized: "Save \(includedRecords.count) records")
    }

    // MARK: Editing

    func update(recordID: UUID, fieldID: UUID, value: String) {
        mutateField(recordID: recordID, fieldID: fieldID) { field in
            field.value = value
            field.resolved = true
        }
    }

    /// Sets a starting value (e.g. "Set date") but keeps an AI flag unresolved until the user confirms.
    func setDraftValue(recordID: UUID, fieldID: UUID, value: String) {
        mutateField(recordID: recordID, fieldID: fieldID) { $0.value = value }
    }

    func markLooksRight(recordID: UUID?, fieldID: UUID) {
        if let recordID {
            mutateField(recordID: recordID, fieldID: fieldID) { $0.resolved = true }
        } else if let index = documentFields.firstIndex(where: { $0.id == fieldID }) {
            documentFields[index].resolved = true
        }
    }

    func remove(recordID: UUID, fieldID: UUID) {
        guard let r = records.firstIndex(where: { $0.id == recordID }),
              let f = records[r].fields.firstIndex(where: { $0.id == fieldID }) else { return }
        if let persisted = records[r].fields[f].persistedID { removedPersistedIDs.insert(persisted) }
        records[r].fields.remove(at: f)
    }

    func addField(_ key: ExtractionFieldKey, to recordID: UUID) {
        guard let r = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[r].fields.append(Self.newField(key))
    }

    func addRecord(_ kind: ReviewRecordKind) {
        var fields = [Self.newField(kind.primaryKey)]
        // Seed a date unless the document's visit date will cover it.
        if kind.dateKey != kind.primaryKey && (kind.dateKey != .visitDate || visitDate == nil) {
            fields.append(Self.newField(kind.dateKey))
        }
        records.append(ReviewRecord(kind: kind, fields: fields, included: true))
    }

    func removeRecord(_ recordID: UUID) {
        guard let r = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[r].fields.compactMap(\.persistedID).forEach { removedPersistedIDs.insert($0) }
        records.remove(at: r)
    }

    private static func newField(_ key: ExtractionFieldKey) -> ReviewField {
        ReviewField(id: UUID(), key: key, value: "", originalValue: nil, sourceText: nil, pageNumber: nil,
                    flagged: false, resolved: true, persistedID: nil)
    }

    private func mutateField(recordID: UUID, fieldID: UUID, _ change: (inout ReviewField) -> Void) {
        guard let r = records.firstIndex(where: { $0.id == recordID }),
              let f = records[r].fields.firstIndex(where: { $0.id == fieldID }) else { return }
        change(&records[r].fields[f])
    }

    // MARK: Confirm / discard

    /// Creates source-linked records for included, valid records only. Returns what was saved.
    func confirm(document: DocumentModel, fields: [ExtractedFieldModel], context: ModelContext) throws -> [SavedRecordSummary] {
        var saved: [SavedRecordSummary] = []
        let clinic = clinic
        var keptFieldIDs = Set<UUID>()

        for record in includedRecords where issues(for: record).isEmpty {
            guard let date = resolvedDate(for: record) else { continue }
            record.fields.compactMap(\.persistedID).forEach { keptFieldIDs.insert($0) }
            let notes = record.field(.notes)?.value

            if record.kind == .weight {
                let raw = record.field(.weight)?.value ?? ""
                let number = Double(raw.filter { "0123456789.,".contains($0) }.replacingOccurrences(of: ",", with: "."))
                if let number {
                    let unit = raw.lowercased().contains("lb") ? WeightUnit.lb.rawValue : WeightUnit.kg.rawValue
                    context.insert(WeightEntryModel(petId: document.petId, weight: number, unit: unit, measurementDate: date, notes: "From \(document.displayTitle)"))
                }
                continue
            }

            let title: String = switch record.kind {
            case .visit: clinic.map { String(localized: "Visit — \($0)") } ?? String(localized: "Vet visit")
            case .diagnosis, .labResult: String((record.field(record.kind.primaryKey)?.value ?? record.kind.title).prefix(80))
            default: record.field(record.kind.primaryKey)?.value ?? record.kind.title
            }
            let longText: String? = (record.kind == .diagnosis || record.kind == .labResult) ? record.field(record.kind.primaryKey)?.value : nil

            let event = HealthEventModel(
                petId: document.petId,
                type: record.kind.eventType.rawValue,
                title: title,
                eventDate: date,
                notes: [longText, notes].compactMap { $0 }.joined(separator: "\n\n").nilIfEmpty,
                sourceDocumentId: document.id,
                providerName: clinic,
                nextDueDate: record.field(.nextDueDate)?.dateValue,
                dosageText: record.field(.dosageText)?.value,
                frequencyText: record.field(.frequencyText)?.value,
                startDate: record.kind == .medication ? date : nil,
                endDate: record.field(.endDate)?.dateValue,
                medicationStatus: record.kind == .medication
                    ? ((record.field(.endDate)?.dateValue).map { $0 < .now } == true ? MedicationStatus.completed : .active).rawValue
                    : nil
            )
            context.insert(event)
            saved.append(SavedRecordSummary(id: event.id, title: event.title, type: event.eventType, date: date, nextDueDate: event.nextDueDate))
        }

        // Persist review outcome on every extracted field (traceability / extraction-correction metric).
        let allReviewFields = records.flatMap(\.fields) + documentFields
        for model in fields {
            if let docTypeField = documentTypeField, model.id == docTypeField.id {
                let edited = documentType.rawValue != docTypeField.original
                model.reviewStatus = (edited ? ReviewStatus.edited : .confirmed).rawValue
                model.fieldValue = documentType.rawValue
                continue
            }
            if removedPersistedIDs.contains(model.id)
                || (!keptFieldIDs.contains(model.id) && !documentFields.contains(where: { $0.id == model.id })) {
                model.reviewStatus = ReviewStatus.rejected.rawValue
            } else if let field = allReviewFields.first(where: { $0.persistedID == model.id }) {
                model.reviewStatus = (field.isEdited ? ReviewStatus.edited : .confirmed).rawValue
                if field.isEdited { model.fieldValue = field.value }
            }
        }
        // User-added fields are recorded too, flagged as user-provided.
        for field in allReviewFields where field.persistedID == nil && !field.isEmpty {
            context.insert(ExtractedFieldModel(
                documentId: document.id, fieldName: field.key.rawValue, fieldValue: field.value,
                confidence: "user", reviewStatus: ReviewStatus.edited.rawValue
            ))
        }

        document.documentType = documentType.rawValue
        document.processingStatus = ProcessingStatus.reviewed.rawValue
        CareProviderDirectory.remember(clinic: clinic, in: context)
        try context.save()
        return saved
    }

    func discard(document: DocumentModel, fields: [ExtractedFieldModel], context: ModelContext) throws {
        fields.forEach { $0.reviewStatus = ReviewStatus.rejected.rawValue }
        document.documentType = documentType.rawValue
        document.processingStatus = ProcessingStatus.reviewed.rawValue
        try context.save()
    }
}
