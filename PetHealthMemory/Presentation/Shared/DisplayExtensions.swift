import SwiftUI

// MARK: - Enum display metadata

extension HealthEventType {
    var title: String {
        switch self {
        case .veterinaryVisit: "Vet visit"
        case .vaccination: "Vaccination"
        case .medication: "Medication"
        case .surgery: "Surgery"
        case .diagnosis: "Diagnosis"
        case .allergy: "Allergy"
        case .symptom: "Symptom"
        case .laboratoryResult: "Lab result"
        case .weight: "Weight"
        case .note: "Note"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .veterinaryVisit: "stethoscope"
        case .vaccination: "syringe.fill"
        case .medication: "pills.fill"
        case .surgery: "cross.case.fill"
        case .diagnosis: "list.clipboard.fill"
        case .allergy: "allergens.fill"
        case .symptom: "thermometer.medium"
        case .laboratoryResult: "testtube.2"
        case .weight: "scalemass.fill"
        case .note: "note.text"
        case .other: "square.grid.2x2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .vaccination, .veterinaryVisit: AppTheme.Colors.brandPrimary
        case .medication: AppTheme.Colors.brandAccent
        case .laboratoryResult, .diagnosis: AppTheme.Colors.statusSource
        case .allergy, .surgery, .symptom: AppTheme.Colors.statusDanger
        case .weight, .note, .other: AppTheme.Colors.textSecondary
        }
    }
}

extension DocumentType {
    var title: String {
        switch self {
        case .vaccinationCertificate: "Vaccination certificate"
        case .veterinaryVisitReport: "Visit report"
        case .prescription: "Prescription"
        case .laboratoryResult: "Lab result"
        case .invoice: "Invoice"
        case .medicalRecord: "Medical record"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .vaccinationCertificate: "syringe"
        case .veterinaryVisitReport: "stethoscope"
        case .prescription: "pills"
        case .laboratoryResult: "testtube.2"
        case .invoice: "creditcard"
        case .medicalRecord: "folder"
        case .other: "doc"
        }
    }
}

extension ReminderType {
    var title: String {
        switch self {
        case .vaccination: "Vaccination"
        case .medication: "Medication"
        case .veterinaryAppointment: "Vet appointment"
        case .generalCare: "General care"
        case .custom: "Custom"
        }
    }

    var symbol: String {
        switch self {
        case .vaccination: "syringe"
        case .medication: "pills"
        case .veterinaryAppointment: "calendar.badge.clock"
        case .generalCare: "pawprint"
        case .custom: "bell"
        }
    }
}

extension ProcessingStatus {
    /// Whether the document still waits for the user to review/confirm extracted data.
    var needsReview: Bool { self == .extracted || self == .ocrCompleted }
}

// MARK: - Model conveniences

extension PetModel {
    var speciesSymbol: String {
        switch species.lowercased() {
        case "dog": "dog.fill"
        case "cat": "cat.fill"
        case "bird": "bird.fill"
        case "rabbit": "hare.fill"
        case "fish": "fish.fill"
        default: "pawprint.fill"
        }
    }

    var ageText: String? {
        guard let birthDate else { return nil }
        let comps = Calendar.current.dateComponents([.year, .month], from: birthDate, to: .now)
        if let years = comps.year, years > 0 { return years == 1 ? "1 yr" : "\(years) yrs" }
        if let months = comps.month { return months == 1 ? "1 mo" : "\(months) mo" }
        return nil
    }

    /// "Dog · Golden Retriever · 3 yrs"
    var subtitle: String {
        [species, breed, ageText].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }
}

extension HealthEventModel {
    var eventType: HealthEventType { HealthEventType(rawValue: type) ?? .other }
    var medicationState: MedicationStatus? { medicationStatus.flatMap(MedicationStatus.init(rawValue:)) }
    var isActiveMedication: Bool { eventType == .medication && medicationState != .completed }
}

extension DocumentModel {
    var docType: DocumentType { DocumentType(rawValue: documentType) ?? .other }
    var status: ProcessingStatus { ProcessingStatus(rawValue: processingStatus) ?? .pending }
    var displayTitle: String { (title?.isEmpty == false ? title : nil) ?? originalFileName }
    var isPDF: Bool { mimeType == "application/pdf" }
}

extension ReminderModel {
    var type: ReminderType { ReminderType(rawValue: reminderType) ?? .custom }
    var state: ReminderStatus { ReminderStatus(rawValue: status) ?? .pending }
    var isOpen: Bool { state == .pending || state == .snoozed }
    var recurrence: RecurrenceOption { RecurrenceOption(rule: recurrenceRule) }
}

// MARK: - Recurrence

/// Minimal RRULE subset stored in `ReminderModel.recurrenceRule` (backend accepts the same string).
enum RecurrenceOption: String, CaseIterable, Identifiable {
    case none, daily, weekly, monthly, every3Months, every6Months, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Never"
        case .daily: "Every day"
        case .weekly: "Every week"
        case .monthly: "Every month"
        case .every3Months: "Every 3 months"
        case .every6Months: "Every 6 months"
        case .yearly: "Every year"
        }
    }

    var rule: String? {
        switch self {
        case .none: nil
        case .daily: "FREQ=DAILY;INTERVAL=1"
        case .weekly: "FREQ=WEEKLY;INTERVAL=1"
        case .monthly: "FREQ=MONTHLY;INTERVAL=1"
        case .every3Months: "FREQ=MONTHLY;INTERVAL=3"
        case .every6Months: "FREQ=MONTHLY;INTERVAL=6"
        case .yearly: "FREQ=YEARLY;INTERVAL=1"
        }
    }

    init(rule: String?) {
        self = Self.allCases.first { $0.rule == rule } ?? .none
    }

    func nextDate(after date: Date) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .none: return nil
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly: return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date)
        case .every3Months: return calendar.date(byAdding: .month, value: 3, to: date)
        case .every6Months: return calendar.date(byAdding: .month, value: 6, to: date)
        case .yearly: return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}

// MARK: - Formatting

extension Date {
    var shortDate: String { formatted(.dateTime.day().month(.abbreviated).year()) }
    var monthYear: String { formatted(.dateTime.month(.wide).year()) }
}
