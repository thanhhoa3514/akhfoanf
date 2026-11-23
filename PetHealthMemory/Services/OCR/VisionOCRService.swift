import Foundation
import PDFKit
import Vision

struct OCRResult: Sendable {
    var text: String
    var pageCount: Int
}

enum OCRError: LocalizedError {
    case unreadableFile
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .unreadableFile: String(localized: "This file couldn't be opened.")
        case .noTextFound: String(localized: "No text was found. The photo may be blurry or too dark.")
        }
    }
}

protocol VisionOCRServiceProtocol {
    func recognizeText(from fileURL: URL, mimeType: String) async throws -> OCRResult
}

/// On-device Apple Vision OCR. Text-based PDFs use their embedded text layer first;
/// scanned pages / images go through `VNRecognizeTextRequest`. Nothing leaves the device.
final class VisionOCRService: VisionOCRServiceProtocol {
    private static let maxRenderDimension: CGFloat = 2400

    func recognizeText(from fileURL: URL, mimeType: String) async throws -> OCRResult {
        try await Task.detached(priority: .userInitiated) {
            if mimeType == "application/pdf" {
                guard let pdf = PDFDocument(url: fileURL) else { throw OCRError.unreadableFile }
                var pages: [String] = []
                for index in 0..<pdf.pageCount {
                    try autoreleasepool {
                        guard let page = pdf.page(at: index) else { return }
                        if let embedded = page.string,
                           embedded.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 {
                            pages.append(embedded)
                        } else {
                            let bounds = page.bounds(for: .mediaBox)
                            let longestSide = max(bounds.width, bounds.height, 1)
                            let scale = min(2.0, Self.maxRenderDimension / longestSide)
                            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                            if let cg = page.thumbnail(of: size, for: .mediaBox).cgImageCompat {
                                pages.append(try Self.recognize(handler: VNImageRequestHandler(cgImage: cg, options: [:])))
                            }
                        }
                    }
                }
                let text = pages.joined(separator: "\n\n")
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OCRError.noTextFound }
                return OCRResult(text: text, pageCount: pdf.pageCount)
            } else {
                // Using the file URL directly preserves EXIF orientation from camera photos.
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    throw OCRError.unreadableFile
                }
                let handler = VNImageRequestHandler(url: fileURL, options: [:])
                let text = try Self.recognize(handler: handler)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OCRError.noTextFound }
                return OCRResult(text: text, pageCount: 1)
            }
        }.value
    }

    nonisolated private static func recognize(handler: VNImageRequestHandler) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
