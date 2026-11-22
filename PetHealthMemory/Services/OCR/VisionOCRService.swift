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
        case .unreadableFile: "This file couldn't be opened."
        case .noTextFound: "No text was found. The photo may be blurry or too dark."
        }
    }
}

protocol VisionOCRServiceProtocol {
    func recognizeText(from fileURL: URL, mimeType: String) async throws -> OCRResult
}

/// On-device Apple Vision OCR. Text-based PDFs use their embedded text layer first;
/// scanned pages / images go through `VNRecognizeTextRequest`. Nothing leaves the device.
final class VisionOCRService: VisionOCRServiceProtocol {
    func recognizeText(from fileURL: URL, mimeType: String) async throws -> OCRResult {
        try await Task.detached(priority: .userInitiated) {
            if mimeType == "application/pdf" {
                guard let pdf = PDFDocument(url: fileURL) else { throw OCRError.unreadableFile }
                var pages: [String] = []
                for index in 0..<pdf.pageCount {
                    guard let page = pdf.page(at: index) else { continue }
                    if let embedded = page.string, embedded.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 {
                        pages.append(embedded)
                    } else {
                        let bounds = page.bounds(for: .mediaBox)
                        let scale: CGFloat = 2
                        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                        if let cg = page.thumbnail(of: size, for: .mediaBox).cgImageCompat {
                            pages.append(try Self.recognize(cgImage: cg))
                        }
                    }
                }
                let text = pages.joined(separator: "\n\n")
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OCRError.noTextFound }
                return OCRResult(text: text, pageCount: pdf.pageCount)
            } else {
                guard let image = PlatformImage(contentsOfFile: fileURL.path), let cg = image.cgImageCompat else {
                    throw OCRError.unreadableFile
                }
                let text = try Self.recognize(cgImage: cg)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OCRError.noTextFound }
                return OCRResult(text: text, pageCount: 1)
            }
        }.value
    }

    nonisolated private static func recognize(cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
