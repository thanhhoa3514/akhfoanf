import SwiftData
import SwiftUI

/// Screen 8 — Document Detail (original viewer + metadata + recognized text + linked records).
struct DocumentDetailView: View {
    let documentID: UUID

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppContainer.self) private var container
    @Query private var documents: [DocumentModel]
    @Query private var linkedEvents: [HealthEventModel]
    @State private var showText = false
    @State private var confirmDelete = false
    @State private var isRetrying = false
    @State private var retryError: String?
    @State private var showFullScreen = false
    @State private var isRenaming = false
    @State private var titleDraft = ""

    init(documentID: UUID) {
        self.documentID = documentID
        _documents = Query(filter: #Predicate<DocumentModel> { $0.id == documentID })
        _linkedEvents = Query(filter: #Predicate<HealthEventModel> { $0.sourceDocumentId == documentID }, sort: \.eventDate, order: .reverse)
    }

    var body: some View {
        if let document = documents.first {
            let fileURL = container.fileStorage.resolveURL(relativePath: document.filePath)
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                    DocumentPreview(url: fileURL, isPDF: document.isPDF)
                        .frame(height: 420)
                        .background(AppTheme.Colors.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.card).strokeBorder(AppTheme.Colors.borderSubtle))
                        .overlay(alignment: .topTrailing) {
                            Button { showFullScreen = true } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .padding(10)
                                    .background(.regularMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(AppTheme.Spacing.sm)
                            .accessibilityLabel("View full screen")
                        }

                    statusCard(document)
                    metadataCard(document)
                    textCard(document)
                    linkedCard
                }
                .padding(AppTheme.Spacing.lg)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .canvasBackground()
            .navigationTitle(document.displayTitle)
            .inlineTitleOnPhone()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: fileURL) { Label("Share original", systemImage: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Rename…", systemImage: "pencil") { startRename(document) }
                        Divider()
                        Button("Delete…", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .alert("Rename document", isPresented: $isRenaming) {
                TextField("Title", text: $titleDraft)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    document.title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    try? context.save()
                }
            }
            .confirmationDialog("Delete this document?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete original file", role: .destructive) {
                    try? DataCleanup.delete(document: document, in: context, container: container)
                    appState.detailRoute = nil
                    dismiss()
                }
            } message: {
                Text(linkedEvents.isEmpty
                     ? "The original file is removed from this device."
                     : "\(linkedEvents.count) records were created from it. They're kept, but lose their source link.")
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showFullScreen) { fullScreen(fileURL, document) }
            #else
            .sheet(isPresented: $showFullScreen) { fullScreen(fileURL, document).frame(minWidth: 700, minHeight: 800) }
            #endif
        } else {
            ContentUnavailableView("Document not found", systemImage: "doc.questionmark")
        }
    }

    private func fullScreen(_ url: URL, _ document: DocumentModel) -> some View {
        NavigationStack {
            DocumentPreview(url: url, isPDF: document.isPDF)
                .navigationTitle(document.displayTitle)
                .inlineTitleOnPhone()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showFullScreen = false } } }
        }
    }

    @ViewBuilder
    private func statusCard(_ document: DocumentModel) -> some View {
        switch document.status {
        case .extracted, .ocrCompleted:
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "questionmark.circle.fill").font(.title2).foregroundStyle(AppTheme.Colors.statusWarning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.status == .extracted ? "Details are waiting for your review" : "Text is ready — add details")
                        .font(.appSubheadline.weight(.semibold))
                    Text("Nothing is added to the timeline until you confirm.").font(.appCaption).foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Spacer()
                Button("Review") { appState.sheet = .review(documentID: documentID) }
                    .buttonStyle(.borderedProminent)
            }
            .card()
        case .failed:
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Label("The text couldn't be read", systemImage: "exclamationmark.triangle.fill")
                    .font(.appSubheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.dangerText)
                if let retryError { Text(retryError).font(.appCaption).foregroundStyle(AppTheme.Colors.textSecondary) }
                HStack {
                    Button {
                        Task {
                            isRetrying = true
                            do { try await DocumentProcessor.process(document, context: context, container: container) }
                            catch { retryError = (error as? LocalizedError)?.errorDescription }
                            isRetrying = false
                        }
                    } label: {
                        if isRetrying { ProgressView().controlSize(.small) } else { Text("Try again") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRetrying)
                    Button("Enter by hand") { appState.sheet = .review(documentID: documentID) }
                        .buttonStyle(.bordered)
                }
            }
            .card()
        case .pending:
            HStack { ProgressView(); Text("Reading text on this device…") }.card()
        case .reviewed:
            EmptyView()
        }
    }

    private func startRename(_ document: DocumentModel) {
        titleDraft = document.displayTitle
        isRenaming = true
    }

    /// Read-only facts; editing is explicit (Rename… in the toolbar menu, the Type menu here).
    private func metadataCard(_ document: DocumentModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Label("Type", systemImage: "tag")
                    .font(.appSubheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer()
                Picker("Type", selection: Binding(
                    get: { document.docType },
                    set: { document.documentType = $0.rawValue; try? context.save() }
                )) {
                    ForEach(DocumentType.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            Divider()
            InfoRow(label: "Imported", value: document.createdAt.formatted(date: .long, time: .omitted), systemImage: "calendar")
            InfoRow(label: "Original file", value: document.originalFileName, systemImage: "doc")
            if let pages = document.pageCount {
                InfoRow(label: "Pages", value: "\(pages)", systemImage: "doc.on.doc")
            }
            Label("Stored privately on this device", systemImage: "lock.shield")
                .font(.appCaption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .card()
    }

    @ViewBuilder
    private func textCard(_ document: DocumentModel) -> some View {
        if let text = document.ocrText, !text.isEmpty {
            DisclosureGroup(isExpanded: $showText) {
                Text(text)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, AppTheme.Spacing.sm)
            } label: {
                Label("Recognized text", systemImage: "text.viewfinder").font(.headline)
            }
            .card()
        }
    }

    @ViewBuilder
    private var linkedCard: some View {
        if !linkedEvents.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Records from this document").font(.headline)
                ForEach(linkedEvents) { event in
                    NavigationLink(value: Route.event(event.id)) {
                        TimelineRow(event: event, sourceTitle: nil, showsRail: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }
    }
}
