import XCTest
@testable import Pet_Health_Memory

final class RuleBasedDocumentExtractorTests: XCTestCase {
    func testVaccinationCertificateExtractsUnambiguousDatesAndClinic() {
        let ocr = """
        RIVERSIDE ANIMAL CLINIC
        Vaccination certificate
        Patient: MOCHI  Species: Canine  Breed: Shiba Inu
        Rabies - Nobivac 1yr  given 17/12/25
        Next due 17/12/26
        Dr. Sarah Chen
        """

        let drafts = RuleBasedDocumentExtractor.extract(from: ocr)

        XCTAssertEqual(value(.documentType, in: drafts), DocumentType.vaccinationCertificate.rawValue)
        XCTAssertEqual(value(.clinic, in: drafts), "Riverside Animal Clinic")
        XCTAssertEqual(value(.vaccineName, in: drafts), "Rabies")
        XCTAssertEqual(value(.vaccineDate, in: drafts), "2025-12-17")
        XCTAssertEqual(value(.nextDueDate, in: drafts), "2026-12-17")
        XCTAssertFalse(draft(.vaccineDate, in: drafts)?.isAmbiguous ?? true)
    }

    func testAmbiguousDatesAreFlaggedAndNeverInvented() {
        let ocr = """
        RIVERSIDE ANIMAL CLINIC
        Consultation report
        Patient: MOCHI  Date: 08/11/2026
        Wt 10.2kg
        Rx: Apoquel 5.4mg tab - 1 tab SID with food x 30d
        DHPPi booster given
        Recheck 4 wks  next due 11/12/27
        """

        let drafts = RuleBasedDocumentExtractor.extract(from: ocr)

        let visitDate = draft(.visitDate, in: drafts)
        XCTAssertNotNil(visitDate)
        XCTAssertNil(visitDate?.fieldValue)
        XCTAssertEqual(visitDate?.isAmbiguous, true)

        XCTAssertEqual(value(.weight, in: drafts), "10.2 kg")
        XCTAssertEqual(value(.vaccineName, in: drafts), "DHPPi")
        XCTAssertEqual(value(.medicationName, in: drafts), "Apoquel")
        XCTAssertEqual(value(.dosageText, in: drafts), "5.4mg tab")

        let freq = draft(.frequencyText, in: drafts)
        XCTAssertEqual(freq?.fieldValue, "1 tab SID with food x 30d")
        XCTAssertEqual(freq?.isAmbiguous, true)
    }

    func testEmptyOrNonMedicalTextDoesNotHallucinate() {
        XCTAssertTrue(RuleBasedDocumentExtractor.extract(from: "   \n  ").isEmpty)
        let drafts = RuleBasedDocumentExtractor.extract(from: "Hello world, this is a photo caption.")
        XCTAssertTrue(drafts.isEmpty)
    }

    private func draft(_ key: ExtractionFieldKey, in drafts: [ExtractedFieldDraft]) -> ExtractedFieldDraft? {
        drafts.first { $0.fieldName == key.rawValue }
    }

    private func value(_ key: ExtractionFieldKey, in drafts: [ExtractedFieldDraft]) -> String? {
        draft(key, in: drafts)?.fieldValue
    }
}
