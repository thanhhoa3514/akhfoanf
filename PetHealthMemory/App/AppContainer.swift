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

    init(
        fileStorage: LocalFileStorageProtocol = LocalFileStorage(),
        ocrService: VisionOCRServiceProtocol = VisionOCRService(),
        extractionService: ExtractionServiceProtocol = FoundationModelExtractionService(),
        notificationService: ReminderNotificationServiceProtocol = ReminderNotificationService(),
        pdfService: PDFReportServiceProtocol = PDFReportService()
    ) {
        self.fileStorage = fileStorage
        self.ocrService = ocrService
        self.extractionService = extractionService
        self.notificationService = notificationService
        self.pdfService = pdfService
    }
}
