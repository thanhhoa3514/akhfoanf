import PDFKit
import SwiftUI

/// Thumbnail for a stored document; loads off the main thread, scanline while processing.
struct DocumentThumbnail: View {
    let document: DocumentModel
    var size: CGFloat = AppTheme.Size.thumbnail
    var isProcessing = false

    @Environment(AppContainer.self) private var container
    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            AppTheme.Colors.bgElevated
            if let image {
                Image(platformImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: document.docType.symbol)
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .frame(width: size, height: size * 1.25)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppTheme.Colors.borderSubtle))
        .scanline(isActive: isProcessing)
        .task(id: document.filePath) {
            let url = container.fileStorage.resolveURL(relativePath: document.filePath)
            let mime = document.mimeType
            let target = CGSize(width: size * 2, height: size * 2.5)
            image = await Task.detached(priority: .utility) {
                Thumbnailer.thumbnail(for: url, mimeType: mime, size: target)
            }.value
        }
        .accessibilityHidden(true)
    }
}

/// Status pill for documents (processing pipeline + review state).
struct DocumentStatusPill: View {
    let status: ProcessingStatus

    var body: some View {
        switch status {
        case .pending:
            Pill(text: "Processing", systemImage: "hourglass", tint: AppTheme.Colors.textSecondary, textColor: AppTheme.Colors.textSecondary)
        case .ocrCompleted, .extracted:
            Pill(text: "Needs review", systemImage: "questionmark.circle.fill", tint: AppTheme.Colors.statusWarning, textColor: AppTheme.Colors.warningText)
        case .reviewed:
            Pill(text: "Reviewed", systemImage: "checkmark.seal.fill", tint: AppTheme.Colors.statusSuccess, textColor: AppTheme.Colors.successText)
        case .failed:
            Pill(text: "Couldn't read", systemImage: "exclamationmark.triangle.fill", tint: AppTheme.Colors.statusDanger, textColor: AppTheme.Colors.dangerText)
        }
    }
}

/// Full original viewer: PDFKit for PDFs, zoomable image otherwise.
struct DocumentPreview: View {
    let url: URL
    let isPDF: Bool

    var body: some View {
        if isPDF {
            PDFKitView(url: url)
        } else if let image = PlatformImage(contentsOfFile: url.path) {
            ZoomableImage(image: image)
        } else {
            ContentUnavailableView("Can't open this file", systemImage: "doc.questionmark")
        }
    }
}

private struct ZoomableImage: View {
    let image: PlatformImage
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width * scale * pinch)
            }
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in scale = min(max(scale * value.magnification, 1), 5) }
            )
            .onTapGesture(count: 2) { withAnimation(AppTheme.Motion.standard) { scale = scale > 1 ? 1 : 2.5 } }
        }
        .accessibilityLabel("Original document image")
    }
}

#if os(iOS)
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
#else
struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
#endif
