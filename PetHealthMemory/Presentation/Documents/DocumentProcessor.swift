import CryptoKit
import Foundation
import Observation
import SwiftData
import UniformTypeIdentifiers

/// Document-to-timeline pipeline: preserve original → on-device OCR → on-device extraction.
/// Produces `ExtractedFieldModel`s with `reviewStatus = pending` — never health records.
@MainActor
enum DocumentProcessor {
    enum Stage: Int, CaseIterable, Comparable {
        case saving, reading, extracting, ready

        static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .saving: "Saving original"
            case .reading: "Reading text"
            case .extracting: "Finding details"
            case .ready: "Ready to review"
            }
        }
    }

    static func store(
        data: Data, fileName: String, mimeType: String, documentType: DocumentType,
        petID: UUID, context: ModelContext, container: AppContainer
    ) throws -> DocumentModel {
        let path = try container.fileStorage.saveFile(data: data, fileName: fileName, subdirectory: "documents")
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let title = (fileName as NSString).deletingPathExtension
        let document = DocumentModel(
            petId: petID, filePath: path, originalFileName: fileName, title: title,
            mimeType: mimeType, documentType: documentType.rawValue, checksum: checksum
        )
        context.insert(document)
        try context.save()
        return document
    }

    /// Runs OCR + extraction. Throws only for OCR failure (document is kept, status = failed).
    static func process(
        _ document: DocumentModel, context: ModelContext, container: AppContainer,
        onStage: (Stage) -> Void = { _ in }
    ) async throws {
        onStage(.reading)
        let url = container.fileStorage.resolveURL(relativePath: document.filePath)
        do {
            let result = try await container.ocrService.recognizeText(from: url, mimeType: document.mimeType)
            document.ocrText = result.text
            document.pageCount = result.pageCount
            document.processingStatus = ProcessingStatus.ocrCompleted.rawValue
            try? context.save()
        } catch {
            document.processingStatus = ProcessingStatus.failed.rawValue
            try? context.save()
            throw error
        }

        guard container.extractionService.isAvailableOnDevice, let text = document.ocrText else {
            onStage(.ready)
            return // Fallback: OCR text + manual entry (US-12).
        }
        onStage(.extracting)
        let docID = document.id
        if let drafts = try? await container.extractionService.extractFields(from: text), !drafts.isEmpty {
            try? context.delete(model: ExtractedFieldModel.self, where: #Predicate<ExtractedFieldModel> { $0.documentId == docID })
            for (index, draft) in drafts.enumerated() {
                context.insert(ExtractedFieldModel(
                    documentId: docID,
                    fieldName: draft.fieldName,
                    fieldValue: draft.fieldValue,
                    sourceText: draft.sourceText,
                    pageNumber: draft.pageNumber,
                    confidence: draft.confidence,
                    isAmbiguous: draft.isAmbiguous,
                    groupKey: draft.groupKey,
                    sortOrder: index
                ))
            }
            document.processingStatus = ProcessingStatus.extracted.rawValue
            try? context.save()
        }
        onStage(.ready)
    }
}

/// Batch import for drag & drop / multi-select. Runs in the background; results land in "Needs review".
@MainActor
enum DocumentImporter {
    static func importFiles(_ urls: [URL], petID: UUID, context: ModelContext, container: AppContainer, appState: AppState) async {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            guard let doc = try? DocumentProcessor.store(
                data: data, fileName: url.lastPathComponent, mimeType: mime, documentType: .other,
                petID: petID, context: context, container: container
            ) else { continue }
            try? await DocumentProcessor.process(doc, context: context, container: container)
        }
    }
}

/// View model for the single-document capture sheet.
@MainActor
@Observable
final class CapturePipeline {
    enum Phase: Equatable {
        case choosing
        case processing(DocumentProcessor.Stage)
        case failed(message: String)
        case finished(documentID: UUID)
    }

    var phase: Phase = .choosing
    var documentType: DocumentType = .other
    private(set) var document: DocumentModel?

    func run(data: Data, fileName: String, mimeType: String, petID: UUID, context: ModelContext, container: AppContainer) async {
        phase = .processing(.saving)
        do {
            let doc = try DocumentProcessor.store(
                data: data, fileName: fileName, mimeType: mimeType, documentType: documentType,
                petID: petID, context: context, container: container
            )
            document = doc
            await process(context: context, container: container)
        } catch {
            phase = .failed(message: "The file couldn't be saved. Check available storage and try again.")
        }
    }

    func retry(context: ModelContext, container: AppContainer) async {
        await process(context: context, container: container)
    }

    private func process(context: ModelContext, container: AppContainer) async {
        guard let document else { return }
        do {
            try await DocumentProcessor.process(document, context: context, container: container) { stage in
                self.phase = .processing(stage)
            }
            phase = .finished(documentID: document.id)
        } catch {
            phase = .failed(message: (error as? LocalizedError)?.errorDescription ?? "The text couldn't be read.")
        }
    }
}
