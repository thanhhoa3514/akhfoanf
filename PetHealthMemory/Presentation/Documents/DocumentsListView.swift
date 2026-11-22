import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Screen 3 — Documents. "Needs review" queue first, then the archive. Drop files to import (macOS / iPad).
struct DocumentsListView: View {
    let petID: UUID

    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Environment(AppContainer.self) private var container
    @Query private var documents: [DocumentModel]
    @State private var isDropTargeted = false
    @State private var typeFilter: DocumentType?
    @State private var pendingDelete: DocumentModel?

    init(petID: UUID) {
        self.petID = petID
        _documents = Query(filter: #Predicate<DocumentModel> { $0.petId == petID }, sort: \.createdAt, order: .reverse)
    }

    private var attention: [DocumentModel] { documents.filter { $0.status.needsReview || $0.status == .failed } }
    private var archive: [DocumentModel] {
        documents.filter { !($0.status.needsReview || $0.status == .failed) && (typeFilter == nil || $0.docType == typeFilter) }
    }

    var body: some View {
        RouteList(firstRoute: (attention.first ?? archive.first).map { .document($0.id) }) {
            if documents.isEmpty {
                ContentUnavailableView {
                    Label("No documents yet", systemImage: "doc.viewfinder")
                } description: {
                    Text("Scan a vaccination card, or import PDFs and photos. Originals are kept safely on this device.")
                } actions: {
                    Button("Add a document") { appState.sheet = .capture(source: nil) }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            }

            if !attention.isEmpty {
                Section("Needs your attention") {
                    ForEach(attention) { doc in row(doc) }
                }
            }
            if !archive.isEmpty || typeFilter != nil {
                Section {
                    ForEach(archive) { doc in row(doc) }
                } header: {
                    HStack {
                        Text("All documents")
                        Spacer()
                        Menu {
                            Button("All types") { typeFilter = nil }
                            ForEach(DocumentType.allCases, id: \.self) { type in
                                Button(type.title) { typeFilter = type }
                            }
                        } label: {
                            Label(typeFilter?.title ?? "All types", systemImage: "line.3.horizontal.decrease")
                                .font(.caption)
                        }
                        .fixedSize()
                    }
                }
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: AppTheme.Radius.card)
                    .strokeBorder(AppTheme.Colors.brandPrimary, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .background(AppTheme.Colors.brandPrimarySoft.opacity(0.6))
                    .overlay(Label("Drop to import", systemImage: "arrow.down.doc").font(.title3.weight(.semibold)))
                    .padding(AppTheme.Spacing.sm)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = urls.filter { url in
                guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
                return type.conforms(to: .pdf) || type.conforms(to: .image)
            }
            guard !accepted.isEmpty else { return false }
            Task { await DocumentImporter.importFiles(accepted, petID: petID, context: context, container: container, appState: appState) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    #if os(iOS)
                    Button { appState.sheet = .capture(source: .camera) } label: { Label("Scan with camera", systemImage: "camera") }
                    #endif
                    Button { appState.sheet = .capture(source: .photos) } label: { Label("Photo library", systemImage: "photo.on.rectangle") }
                    Button { appState.sheet = .capture(source: .files) } label: { Label("Files…", systemImage: "folder") }
                } label: {
                    Label("Add document", systemImage: "plus")
                }
                .help("Import a document (⌘I)")
            }
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.displayTitle ?? "document")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete original file", role: .destructive) {
                if let doc = pendingDelete { try? DataCleanup.delete(document: doc, in: context, container: container) }
                pendingDelete = nil
            }
        } message: {
            Text("Records created from it are kept, but lose their source link.")
        }
    }

    private func row(_ doc: DocumentModel) -> some View {
        NavigationLink(value: Route.document(doc.id)) {
            HStack(spacing: AppTheme.Spacing.md) {
                DocumentThumbnail(document: doc, isProcessing: doc.status == .pending)
                    .zoomSource(id: Route.document(doc.id))
                VStack(alignment: .leading, spacing: 4) {
                    Text(doc.displayTitle).font(.body.weight(.semibold)).lineLimit(2)
                    Text("\(doc.docType.title) · \(doc.createdAt.shortDate)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    DocumentStatusPill(status: doc.status)
                }
            }
            .padding(.vertical, AppTheme.Spacing.xs)
        }
        .swipeActions {
            Button(role: .destructive) { pendingDelete = doc } label: { Label("Delete", systemImage: "trash") }
        }
        .contextMenu {
            if doc.status.needsReview {
                Button { appState.sheet = .review(documentID: doc.id) } label: { Label("Review details", systemImage: "checklist") }
            }
            Button(role: .destructive) { pendingDelete = doc } label: { Label("Delete", systemImage: "trash") }
        }
    }
}
