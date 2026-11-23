import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import PetHealthMemory

/// End-to-end Vision OCR + RuleBasedDocumentExtractor benchmark tests.
/// Synthesizes realistic veterinary PDFs and images on the fly (zero binary assets in Git)
/// and runs directly on macOS CI runners (`xcodebuild test -destination 'platform=macOS'`).
final class VisionOCRBenchmarkTests: XCTestCase {
    private let ocrService = VisionOCRService()
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VisionOCRBenchmarkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func testScannedPNGVaccinationCertificateAndExtraction() async throws {
        let lines = [
            "RIVERSIDE ANIMAL CLINIC",
            "Vaccination certificate",
            "Patient: MOCHI  Breed: Shiba Inu",
            "Rabies - Nobivac 1yr given 17/12/2025",
            "Next due 17/12/2026",
            "Dr. Sarah Chen",
        ]
        let pngURL = try renderPNG(lines: lines, fileName: "rabies.png")

        let result = try await ocrService.recognizeText(from: pngURL, mimeType: "image/png")
        XCTAssertEqual(result.pageCount, 1)
        assertContainsAll(result.text, keywords: ["RIVERSIDE", "Rabies", "17/12/2025", "17/12/2026"])

        let drafts = RuleBasedDocumentExtractor.extract(from: result.text)
        XCTAssertEqual(drafts.first(where: { $0.fieldName == "vaccineName" })?.fieldValue, "Rabies")
        XCTAssertEqual(drafts.first(where: { $0.fieldName == "vaccineDate" })?.fieldValue, "2025-12-17")
    }

    func testScannedPNGPrescriptionPreservesDecimalDosage() async throws {
        let lines = [
            "RIVERSIDE ANIMAL CLINIC",
            "Prescription",
            "Date: 2026-11-08",
            "Wt 10.2 kg",
            "Rx: Apoquel 5.4mg tab - 1 tab once daily with food",
        ]
        let pngURL = try renderPNG(lines: lines, fileName: "prescription.png")

        let result = try await ocrService.recognizeText(from: pngURL, mimeType: "image/png")
        assertContainsAll(result.text, keywords: ["Apoquel", "5.4", "10.2"])

        let drafts = RuleBasedDocumentExtractor.extract(from: result.text)
        XCTAssertEqual(drafts.first(where: { $0.fieldName == "medicationName" })?.fieldValue, "Apoquel")
        XCTAssertEqual(drafts.first(where: { $0.fieldName == "weight" })?.fieldValue, "10.2 kg")
    }

    func testMultiPageScannedPDFPerformanceAndAccuracy() async throws {
        let pageSets: [[String]] = [
            ["RIVERSIDE ANIMAL CLINIC", "Laboratory Report - Page 1", "Patient: MOCHI"],
            ["Blood Chemistry Panel - Page 2", "ALT 42 U/L", "BUN 18 mg/dL"],
            ["Hematology Panel - Page 3", "WBC 8.4 K/uL", "RBC 6.8 M/uL"],
            ["Vaccination History - Page 4", "DHPPi given 2026-05-06"],
            ["Summary - Page 5", "Wt 10.4 kg", "Follow up in 6 months"],
        ]
        let pdfURL = try renderScannedPDF(pages: pageSets, fileName: "multipage_lab.pdf")

        let result = try await ocrService.recognizeText(from: pdfURL, mimeType: "application/pdf")
        XCTAssertEqual(result.pageCount, 5)
        assertContainsAll(result.text, keywords: ["Laboratory", "ALT", "DHPPi", "10.4"])
    }

    func testMultilingualGermanAndFrenchCards() async throws {
        let lines = [
            "Clinique Veterinaire du Parc",
            "Certificat de vaccination",
            "Tollwut / Rage 2026-06-15",
            "Poids: 9.8 kg",
        ]
        let pngURL = try renderPNG(lines: lines, fileName: "multilingual.png")

        let result = try await ocrService.recognizeText(from: pngURL, mimeType: "image/png")
        assertContainsAll(result.text, keywords: ["Clinique", "Tollwut", "9.8"])
    }

    func testBlankImageThrowsNoTextFound() async throws {
        let blankURL = try renderPNG(lines: [], fileName: "blank.png")
        do {
            _ = try await ocrService.recognizeText(from: blankURL, mimeType: "image/png")
            XCTFail("Expected OCRError.noTextFound for a blank image")
        } catch let error as OCRError {
            XCTAssertEqual(error.localizedDescription, OCRError.noTextFound.localizedDescription)
        }
    }

    // MARK: - Synthetic Document Renderers

    private func assertContainsAll(_ text: String, keywords: [String], file: StaticString = #filePath, line: UInt = #line) {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        for keyword in keywords {
            let target = keyword.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            XCTAssertTrue(normalized.contains(target), "Expected OCR text to contain '\(keyword)'. Got:\n\(text)", file: file, line: line)
        }
    }

    private func renderCGImage(lines: [String], width: Int = 1200, height: Int = 1600) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw OCRError.unreadableFile
        }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica" as CFString, 36, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1),
        ]

        var y = CGFloat(height) - 120
        for textLine in lines {
            let attributed = NSAttributedString(string: textLine, attributes: attrs)
            let ctLine = CTLineCreateWithAttributedString(attributed)
            ctx.textPosition = CGPoint(x: 80, y: y)
            CTLineDraw(ctLine, ctx)
            y -= 72
        }

        guard let image = ctx.makeImage() else { throw OCRError.unreadableFile }
        return image
    }

    private func renderPNG(lines: [String], fileName: String) throws -> URL {
        let image = try renderCGImage(lines: lines)
        let url = tempDir.appendingPathComponent(fileName)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw OCRError.unreadableFile
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw OCRError.unreadableFile }
        return url
    }

    private func renderScannedPDF(pages: [[String]], fileName: String) throws -> URL {
        let url = tempDir.appendingPathComponent(fileName)
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let pdfCtx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw OCRError.unreadableFile
        }
        for pageLines in pages {
            let cgImage = try renderCGImage(lines: pageLines)
            pdfCtx.beginPDFPage(nil)
            pdfCtx.draw(cgImage, in: mediaBox)
            pdfCtx.endPDFPage()
        }
        pdfCtx.closePDF()
        return url
    }
}
