import PDFKit
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import VisionKit
#endif

/// Screen 7 — Document Capture / Import sheet → processing → Extraction Review, in one sheet.
struct DocumentCaptureFlow: View {
    let petID: UUID
    let initialSource: CaptureSource?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @State private var pipeline = CapturePipeline()
    @State private var showCamera = false
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var photoItem: PhotosPickerItem?
    @State private var didAutoLaunch = false

    var body: some View {
        NavigationStack {
            Group {
                switch pipeline.phase {
                case .choosing:
                    chooser
                case .processing(let stage):
                    ProcessingView(document: pipeline.document, stage: stage, aiAvailable: container.extractionService.isAvailableOnDevice)
                case .failed(let message):
                    failure(message)
                case .finished(let documentID):
                    ExtractionReviewView(documentID: documentID, dismissesFlow: { dismiss() })
                }
            }
            .animation(AppTheme.Motion.standard, value: pipeline.phase)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showCamera) {
            DocumentScannerView { images in
                showCamera = false
                guard let data = Self.pdfData(from: images) else { return }
                Task { await run(data: data, fileName: "Scan \(Date.now.formatted(.iso8601.year().month().day())).pdf", mime: "application/pdf") }
            } onCancel: {
                showCamera = false
                if initialSource == .camera { dismiss() }
            }
            .ignoresSafeArea()
        }
        #endif
        .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            Task { await run(data: data, fileName: url.lastPathComponent, mime: mime) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                let jpeg = PlatformImage(data: data)?.jpegDataCompat() ?? data
                await run(data: jpeg, fileName: "Photo \(Date.now.formatted(.iso8601.year().month().day())).jpg", mime: "image/jpeg")
            }
        }
        .onAppear {
            guard !didAutoLaunch, let initialSource else { return }
            didAutoLaunch = true
            launch(initialSource)
        }
        .interactiveDismissDisabled(isBusy)
    }

    private var isBusy: Bool {
        if case .processing = pipeline.phase { return true }
        return false
    }

    private func launch(_ source: CaptureSource) {
        switch source {
        case .camera:
            #if os(iOS)
            if VNDocumentCameraViewController.isSupported { showCamera = true } else { showPhotos = true }
            #endif
        case .photos: showPhotos = true
        case .files: showFiles = true
        }
    }

    private func run(data: Data, fileName: String, mime: String) async {
        await pipeline.run(data: data, fileName: fileName, mimeType: mime, petID: petID, context: context, container: container)
    }

    // MARK: Chooser

    private var chooser: some View {
        Form {
            Section {
                #if os(iOS)
                sourceButton("Scan with camera", "Best for paper vaccination cards", "camera.fill") { launch(.camera) }
                #endif
                sourceButton("Photo library", "Photos of records or labels", "photo.on.rectangle") { launch(.photos) }
                sourceButton("Files", "PDFs from email, clinic portals, iCloud Drive", "folder.fill") { launch(.files) }
            }
            Section {
                Picker("Document type", selection: $pipeline.documentType) {
                    ForEach(DocumentType.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            } footer: {
                Label("Text is read on this device. Nothing is uploaded.", systemImage: "lock.shield")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .canvasBackground()
        .navigationTitle("Add Document")
        .inlineTitleOnPhone()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private func sourceButton(_ title: String, _ subtitle: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                TypeIcon(systemImage: symbol, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(subtitle).font(.appCaption).foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .frame(minHeight: AppTheme.Size.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Failure (Flow C)

    private func failure(_ message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Spacer()
            if let document = pipeline.document {
                DocumentThumbnail(document: document, size: 96)
            }
            VStack(spacing: AppTheme.Spacing.sm) {
                Text("We couldn't read this one").font(.title2.weight(.bold))
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                if pipeline.document != nil {
                    Label("The original is saved in Documents.", systemImage: "checkmark.shield")
                        .font(.appSubheadline)
                        .foregroundStyle(AppTheme.Colors.successText)
                }
            }
            VStack(spacing: AppTheme.Spacing.sm) {
                if pipeline.document != nil {
                    Button("Try again") { Task { await pipeline.retry(context: context, container: container) } }
                        .buttonStyle(.primary)
                    Button("Enter details by hand") {
                        if let id = pipeline.document?.id { pipeline.phase = .finished(documentID: id) }
                    }
                    .buttonStyle(.secondary)
                } else {
                    Button("Choose another file") { pipeline.phase = .choosing }
                        .buttonStyle(.primary)
                }
                Button("Keep document only") { dismiss() }
                    .frame(minHeight: AppTheme.Size.minTouch)
            }
            Spacer()
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .canvasBackground()
        .navigationTitle("")
    }

    static func pdfData(from images: [PlatformImage]) -> Data? {
        let pdf = PDFDocument()
        for (index, image) in images.enumerated() {
            if let page = PDFPage(image: image) { pdf.insert(page, at: index) }
        }
        return pdf.pageCount > 0 ? pdf.dataRepresentation() : nil
    }
}

/// OCR / AI processing state: scanline over thumbnail + a step checklist (the checklist carries meaning,
/// so it works with Reduce Motion and VoiceOver). No artificial delays.
struct ProcessingView: View {
    let document: DocumentModel?
    let stage: DocumentProcessor.Stage
    let aiAvailable: Bool

    private var stages: [DocumentProcessor.Stage] {
        aiAvailable ? DocumentProcessor.Stage.allCases : [.saving, .reading, .ready]
    }

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xxl) {
            Spacer()
            Group {
                if let document {
                    DocumentThumbnail(document: document, size: 120, isProcessing: true)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppTheme.Colors.bgElevated)
                        .frame(width: 120, height: 150)
                        .scanline(isActive: true)
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                ForEach(stages, id: \.self) { item in
                    HStack(spacing: AppTheme.Spacing.md) {
                        ZStack {
                            if item < stage || stage == .ready {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.Colors.statusSuccess)
                                    .transition(.scale.combined(with: .opacity))
                            } else if item == stage {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "circle").foregroundStyle(AppTheme.Colors.borderSubtle)
                            }
                        }
                        .frame(width: 24, height: 24)
                        Text(item.title)
                            .font(.body.weight(item == stage ? .semibold : .regular))
                            .foregroundStyle(item <= stage ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                    }
                }
            }
            .animation(AppTheme.Motion.standard, value: stage)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stage.title)
            .accessibilityAddTraits(.updatesFrequently)

            Label("On-device. Nothing leaves your \(Self.deviceName).", systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer()
        }
        .padding(AppTheme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .canvasBackground()
        .navigationTitle("Reading document")
        .inlineTitleOnPhone()
        .onChange(of: stage) { _, newValue in
            AccessibilityNotification.Announcement(newValue.title).post()
        }
    }

    private static var deviceName: String {
        #if os(macOS)
        return "Mac"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
}

#if os(iOS)
/// VisionKit document camera (auto edge-detection, multi-page). iOS only.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onCancel: onCancel) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onScan: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onScan((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onCancel() }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onCancel() }
    }
}
#endif
