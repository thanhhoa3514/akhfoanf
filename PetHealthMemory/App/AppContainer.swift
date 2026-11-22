import Foundation
import Observation

/// Central dependency container for platform services. Injected with `.environment(container)`.
@MainActor
@Observable
final class AppContainer {
    let fileStorage: LocalFileStorageProtocol
    let ocrService: VisionOCRServiceProtocol
    let extractionService: ExtractionServiceProtocol
    let notificationService: ReminderNotificationServiceProtocol
    let pdfService: PDFReportServiceProtocol

    // Defaults are built in the body: default-argument expressions are evaluated in a
    // nonisolated context and can't call the @MainActor PDFReportService initializer.
    init(
        fileStorage: LocalFileStorageProtocol? = nil,
        ocrService: VisionOCRServiceProtocol? = nil,
        extractionService: ExtractionServiceProtocol? = nil,
        notificationService: ReminderNotificationServiceProtocol? = nil,
        pdfService: PDFReportServiceProtocol? = nil
    ) {
        self.fileStorage = fileStorage ?? LocalFileStorage()
        self.ocrService = ocrService ?? VisionOCRService()
        self.extractionService = extractionService ?? FoundationModelExtractionService()
        self.notificationService = notificationService ?? ReminderNotificationService()
        self.pdfService = pdfService ?? PDFReportService()
    }
}
