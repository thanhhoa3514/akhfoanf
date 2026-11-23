import CoreGraphics
import CoreText
import Foundation
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Launch arguments used by the UI test target (`PetHealthMemoryUITests`), always as
/// `-key value` pairs so they land in the UserDefaults argument domain. (A bare flag such as
/// `-ui-testing` would swallow the next argument, and macOS then treats the leftover value as a
/// file to open, which suppresses the app's initial window.)
///
/// - `-ui-testing YES`: in-memory store, no persisted pet selection, no animations.
/// - `-seed-sample-data YES`: inserts a realistic demo pet with history (only with `-ui-testing`).
/// - `-color-scheme dark|light`: forces the appearance for screenshot runs.
enum LaunchOptions {
    private static let defaults = UserDefaults.standard

    static let isUITesting = defaults.bool(forKey: "ui-testing")
    static let seedSampleData = isUITesting && defaults.bool(forKey: "seed-sample-data")

    static var colorScheme: ColorScheme? {
        switch defaults.string(forKey: "color-scheme") {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    /// Called once from the App initialiser before any view reads state.
    @MainActor
    static func prepare(_ modelContainer: ModelContainer) {
        guard isUITesting else { return }
        UserDefaults.standard.removeObject(forKey: "selectedPetID")
        #if canImport(UIKit)
        UIView.setAnimationsEnabled(false)
        #endif
        if seedSampleData {
            SampleData.insert(into: modelContainer.mainContext)
        }
    }
}

/// Deterministic demo data for screenshots. Dates are relative to now so "due soon" and
/// "overdue" states always render the same way.
enum SampleData {
    /// Wording follows the app's language, so localized screenshot runs show local data.
    private static var copy: SampleCopy { SampleCopy.forLanguage(Bundle.main.preferredLocalizations.first ?? "en") }

    @MainActor
    static func insert(into context: ModelContext) {
        let copy = Self.copy
        let calendar = Calendar.current
        func days(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now)) ?? .now
        }

        let clinic = CareProviderModel(clinicName: copy.clinicName, vetName: copy.vetName,
                                       phone: "+84 28 3822 1234")
        context.insert(clinic)

        let pet = PetModel(name: "Mochi", species: "Dog", breed: copy.breed,
                           birthDate: calendar.date(byAdding: .year, value: -4, to: .now),
                           sex: "Female", microchipNumber: "900215001234567")
        context.insert(pet)

        let rabies = HealthEventModel(petId: pet.id, type: HealthEventType.vaccination.rawValue,
                                      title: copy.rabies, eventDate: days(-340), providerId: clinic.id,
                                      providerName: clinic.clinicName, nextDueDate: days(25))
        let combined = HealthEventModel(petId: pet.id, type: HealthEventType.vaccination.rawValue,
                                        title: copy.combinedVaccine, eventDate: days(-200), providerId: clinic.id,
                                        providerName: clinic.clinicName, nextDueDate: days(165))
        let medication = HealthEventModel(petId: pet.id, type: HealthEventType.medication.rawValue,
                                          title: copy.medication, eventDate: days(-14),
                                          dosageText: copy.dosage, frequencyText: copy.frequency,
                                          startDate: days(-14), endDate: days(16),
                                          medicationStatus: MedicationStatus.active.rawValue)
        let visit = HealthEventModel(petId: pet.id, type: HealthEventType.veterinaryVisit.rawValue,
                                     title: copy.visitTitle, eventDate: days(-14),
                                     notes: copy.visitNotes,
                                     providerId: clinic.id, providerName: clinic.clinicName)
        let allergy = HealthEventModel(petId: pet.id, type: HealthEventType.allergy.rawValue,
                                       title: copy.allergy, eventDate: days(-400))
        [rabies, combined, medication, visit, allergy].forEach { context.insert($0) }

        let reminders = [
            ReminderModel(petId: pet.id, healthEventId: rabies.id, title: copy.rabiesBooster,
                          reminderType: ReminderType.vaccination.rawValue, dueDate: days(25)),
            ReminderModel(petId: pet.id, healthEventId: medication.id, title: copy.medicationRefill,
                          reminderType: ReminderType.medication.rawValue, dueDate: days(-1)),
            ReminderModel(petId: pet.id, title: copy.skinRecheck,
                          reminderType: ReminderType.veterinaryAppointment.rawValue, dueDate: days(14)),
        ]
        reminders.forEach { context.insert($0) }

        let weights: [(Int, Double)] = [(-180, 9.8), (-120, 10.1), (-60, 10.4), (-14, 10.2)]
        for (offset, kg) in weights {
            context.insert(WeightEntryModel(petId: pet.id, weight: kg, measurementDate: days(offset)))
        }

        insertDocuments(into: context, copy: copy, petID: pet.id, rabies: rabies, days: days)
        try? context.save()
    }

    // MARK: Documents

    /// One reviewed certificate (linked to the Rabies record) and one report waiting for review.
    @MainActor
    private static func insertDocuments(into context: ModelContext, copy: SampleCopy, petID: UUID,
                                        rabies: HealthEventModel, days: (Int) -> Date) {
        let storage = LocalFileStorage()

        let certificateLines = copy.certificateLines
        if let path = try? storage.saveFile(data: makePDF(lines: certificateLines),
                                            fileName: "rabies-certificate.pdf", subdirectory: "documents") {
            let certificate = DocumentModel(petId: petID, filePath: path, originalFileName: "rabies-certificate.pdf",
                                            title: copy.certificateTitle, mimeType: "application/pdf",
                                            documentType: DocumentType.vaccinationCertificate.rawValue,
                                            ocrText: certificateLines.joined(separator: "\n"), pageCount: 1,
                                            processingStatus: ProcessingStatus.reviewed.rawValue,
                                            createdAt: days(-340))
            context.insert(certificate)
            rabies.sourceDocumentId = certificate.id
        }

        let reportLines = copy.reportLines
        guard let path = try? storage.saveFile(data: makePDF(lines: reportLines),
                                               fileName: "checkup-report.pdf", subdirectory: "documents") else { return }
        let report = DocumentModel(petId: petID, filePath: path, originalFileName: "checkup-report.pdf",
                                   title: copy.reportTitle, mimeType: "application/pdf",
                                   documentType: DocumentType.veterinaryVisitReport.rawValue,
                                   ocrText: reportLines.joined(separator: "\n"), pageCount: 1,
                                   processingStatus: ProcessingStatus.extracted.rawValue,
                                   createdAt: days(-1))
        context.insert(report)

        typealias Key = ExtractionFieldKey
        let fields: [(Key, String?, String, String, Bool, String?)] = [
            (.documentType, DocumentType.veterinaryVisitReport.rawValue, copy.reportHeading, "high", false, nil),
            (.petName, "Mochi", copy.petNameSource, "high", false, nil),
            (.clinic, copy.clinicName, copy.reportLines[0], "high", false, nil),
            (.visitDate, "2026-11-08", copy.dateSource, "high", false, nil),
            (.weight, "\(10.2.formatted(.number.precision(.fractionLength(1)))) kg", copy.weightSource, "high", false, nil),
            (.diagnosisText, copy.diagnosis.value, copy.diagnosis.source, "medium", false, "diagnosis-0"),
            (.medicationName, copy.medicationField.value, copy.medicationField.source, "high", false, "medication-0"),
            (.dosageText, copy.dosageField.value, copy.dosageField.source, "high", false, "medication-0"),
            (.frequencyText, copy.frequencyField.value, copy.frequencyField.source, "low", true, "medication-0"),
            (.vaccineName, copy.vaccineField.value, copy.vaccineField.source, "medium", false, "vaccination-0"),
            (.nextDueDate, nil, copy.nextDueSource, "low", true, "vaccination-0"),
        ]
        for (order, field) in fields.enumerated() {
            context.insert(ExtractedFieldModel(documentId: report.id, fieldName: field.0.rawValue,
                                               fieldValue: field.1, sourceText: field.2, pageNumber: 1,
                                               confidence: field.3, isAmbiguous: field.4,
                                               groupKey: field.5, sortOrder: order))
        }
    }

    /// A one-page A4 PDF with the given lines, drawn with CoreGraphics/CoreText (works on iOS and macOS).
    private static func makePDF(lines: [String]) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }
        pdf.beginPDFPage(nil)
        pdf.setFillColor(CGColor(gray: 0.95, alpha: 1))
        pdf.fill(CGRect(x: 40, y: 742, width: 515, height: 60))
        var y: CGFloat = 770
        for (index, line) in lines.enumerated() {
            let font = CTFontCreateWithName((index == 0 ? "Helvetica-Bold" : "Helvetica") as CFString,
                                            index == 0 ? 18 : 13, nil)
            let attributed = NSAttributedString(string: line, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
            ])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            pdf.textPosition = CGPoint(x: 56, y: y)
            CTLineDraw(ctLine, pdf)
            y -= index == 0 ? 40 : 24
        }
        pdf.endPDFPage()
        pdf.closePDF()
        return data as Data
    }
}
