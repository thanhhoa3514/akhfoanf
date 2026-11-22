import SwiftUI

// MARK: - Enum display metadata

extension HealthEventType {
    var title: String {
        switch self {
        case .veterinaryVisit: String(localized: "Vet visit")
        case .vaccination: String(localized: "Vaccination")
        case .medication: String(localized: "Medication")
        case .surgery: String(localized: "Surgery")
        case .diagnosis: String(localized: "Diagnosis")
        case .allergy: String(localized: "Allergy")
        case .symptom: String(localized: "Symptom")
        case .laboratoryResult: String(localized: "Lab result")
        case .weight: String(localized: "Weight")
        case .note: String(localized: "Note")
        case .other: String(localized: "Other")
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
        case .vaccinationCertificate: String(localized: "Vaccination certificate")
        case .veterinaryVisitReport: String(localized: "Visit report")
        case .prescription: String(localized: "Prescription")
        case .laboratoryResult: String(localized: "Lab result")
        case .invoice: String(localized: "Invoice")
        case .medicalRecord: String(localized: "Medical record")
        case .other: String(localized: "Other")
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
        case .vaccination: String(localized: "Vaccination")
        case .medication: String(localized: "Medication")
        case .veterinaryAppointment: String(localized: "Vet appointment")
        case .generalCare: String(localized: "General care")
        case .custom: String(localized: "Custom")
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

    /// Species and sex are stored as stable English values (shared with the backend); show them
    /// in the user's language.
    static func displayName(species: String) -> String {
        switch species {
        case "Dog": String(localized: "Dog")
        case "Cat": String(localized: "Cat")
        case "Rabbit": String(localized: "Rabbit")
        case "Bird": String(localized: "Bird")
        case "Fish": String(localized: "Fish")
        case "Other": String(localized: "Other")
        default: species
        }
    }

    static func displayName(sex: String) -> String {
        switch sex {
        case "Unknown": String(localized: "Unknown")
        case "Female": String(localized: "Female")
        case "Male": String(localized: "Male")
        case "Female (spayed)": String(localized: "Female (spayed)")
        case "Male (neutered)": String(localized: "Male (neutered)")
        default: sex
        }
    }

    var ageText: String? {
        guard let birthDate else { return nil }
        let comps = Calendar.current.dateComponents([.year, .month], from: birthDate, to: .now)
        if let years = comps.year, years > 0 { return years == 1 ? String(localized: "1 yr") : String(localized: "\(years) yrs") }
        if let months = comps.month { return months == 1 ? String(localized: "1 mo") : String(localized: "\(months) mo") }
        return nil
    }

    /// "Dog · Golden Retriever · 3 yrs"
    var subtitle: String {
        [PetModel.displayName(species: species), breed, ageText].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
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
    /// How many days ahead this reminder counts as "due soon".
    var soonWindow: Int { type == .vaccination ? DueState.vaccineSoonWindow : DueState.defaultSoonWindow }
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
        case .none: String(localized: "Never")
        case .daily: String(localized: "Every day")
        case .weekly: String(localized: "Every week")
        case .monthly: String(localized: "Every month")
        case .every3Months: String(localized: "Every 3 months")
        case .every6Months: String(localized: "Every 6 months")
        case .yearly: String(localized: "Every year")
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
