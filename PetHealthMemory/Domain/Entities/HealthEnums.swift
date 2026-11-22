import Foundation

enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case kg
    case lb
}

enum DocumentType: String, Codable, CaseIterable, Sendable {
    case vaccinationCertificate = "vaccination_certificate"
    case veterinaryVisitReport = "veterinary_visit_report"
    case prescription
    case laboratoryResult = "laboratory_result"
    case invoice
    case medicalRecord = "medical_record"
    case other
}

enum ProcessingStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case ocrCompleted = "ocr_completed"
    case extracted
    case reviewed
    case failed
}

enum ReviewStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case confirmed
    case edited
    case rejected
}

enum HealthEventType: String, Codable, CaseIterable, Sendable {
    case veterinaryVisit = "veterinary_visit"
    case vaccination
    case medication
    case surgery
    case diagnosis
    case allergy
    case symptom
    case laboratoryResult = "laboratory_result"
    case weight
    case note
    case other
}

enum ReminderType: String, Codable, CaseIterable, Sendable {
    case vaccination
    case medication
    case veterinaryAppointment = "veterinary_appointment"
    case generalCare = "general_care"
    case custom
}

enum ReminderStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case completed
    case snoozed
    case cancelled
}

enum MedicationStatus: String, Codable, CaseIterable, Sendable {
    case active
    case completed
}

/// Sync mode chosen by the user in Settings (DESIGN.md — Sync UX).
enum SyncMode: String, Codable, CaseIterable, Sendable {
    case localOnly = "local_only"
    case iCloud = "icloud"
    case backend
}
