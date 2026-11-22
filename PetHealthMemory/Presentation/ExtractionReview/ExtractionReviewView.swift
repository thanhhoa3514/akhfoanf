import SwiftData
import SwiftUI

/// Screen 9 — AI Extraction Review (human-in-the-loop). Also the manual-entry fallback when AI is
/// unavailable (OCR text shown alongside an empty form).
/// iPhone: stacked (document strip → records → sticky save bar). macOS / iPad: original left, fields right.
struct ExtractionReviewView: View {
    let documentID: UUID
    var dismissesFlow: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppContainer.self) private var container
    @Environment(\.isCompactLayout) private var isCompact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var documents: [DocumentModel]
    @Query private var fieldModels: [ExtractedFieldModel]
    @Query private var pets: [PetModel]

    @State private var model = ExtractionReviewModel()
    @State private var loaded = false
    @State private var saved: [SavedRecordSummary]?
    @State private var saveError: String?
    @State private var confirmDiscard = false
    @State private var showOriginal = false
    @State private var highlight: String?
    @State private var leftPane: LeftPane = .original
    @State private var reminderDraft: ReminderDraft?

    enum LeftPane: String, CaseIterable, Identifiable {
        case original = "Original", text = "Recognized text"
        var id: String { rawValue }
    }

    init(documentID: UUID, dismissesFlow: (() -> Void)? = nil) {
        self.documentID = documentID
        self.dismissesFlow = dismissesFlow
        _documents = Query(filter: #Predicate<DocumentModel> { $0.id == documentID })
        _fieldModels = Query(filter: #Predicate<ExtractedFieldModel> { $0.documentId == documentID })
    }

    private var document: DocumentModel? { documents.first }
    private var pet: PetModel? { pets.first { $0.id == document?.petId } }

    var body: some View {
        Group {
            if let document {
                if let saved {
                    SavedConfirmationView(
                        saved: saved, petName: pet?.name ?? "your pet",
                        onAddReminder: { reminderDraft = $0 },
                        onViewTimeline: {
                            appState.section = .history
                            close()
                        },
                        onDone: close
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    reviewLayout(document)
                        .transition(.opacity)
                }
            } else {
                ContentUnavailableView("Document not found", systemImage: "doc.questionmark")
            }
        }
        .animation(AppTheme.Motion.animation(AppTheme.Motion.confirm, reduceMotion: reduceMotion), value: saved == nil)
        .sensoryFeedback(.success, trigger: saved != nil) { _, isSaved in isSaved }
        .canvasBackground()
        .navigationTitle(saved == nil ? (model.isManualMode ? "Add Details" : "Review Details") : "")
        .inlineTitleOnPhone()
        .navigationBarBackButtonHiddenCompat()
        .toolbar {
            if saved == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { close() }
                        .help("Keep it in Needs review and come back later")
                }
            }
        }
        .onAppear {
            guard !loaded, let document else { return }
            model.load(document: document, fields: fieldModels)
            loaded = true
        }
        .confirmationDialog("Discard these details?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard details", role: .destructive) {
                if let document { try? model.discard(document: document, fields: fieldModels, context: context) }
                close()
            }
        } message: {
            Text("Nothing is added to the timeline. The original document stays in Documents.")
        }
        .sheet(item: $reminderDraft) { draft in
            if let petID = document?.petId {
                NavigationStack { ReminderFormView(mode: .create(petID: petID, draft: draft)) }
            }
        }
        .sheet(isPresented: $showOriginal) {
            if let document {
                NavigationStack {
                    SourcePane(document: document, highlight: highlight, pane: $leftPane)
                        .navigationTitle(document.displayTitle)
                        .inlineTitleOnPhone()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showOriginal = false } } }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func close() {
        if let dismissesFlow { dismissesFlow() } else { dismiss() }
    }

    // MARK: Layout

    @ViewBuilder
    private func reviewLayout(_ document: DocumentModel) -> some View {
        if isCompact {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                        documentStrip(document)
                        fieldsColumn(document)
                    }
                    .padding(AppTheme.Spacing.lg)
                }
                .safeAreaInset(edge: .bottom) { saveBar(document, proxy: proxy) }
            }
        } else {
            HStack(spacing: 0) {
                SourcePane(document: document, highlight: highlight, pane: $leftPane)
                    .frame(minWidth: 320, maxWidth: .infinity)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        fieldsColumn(document).padding(AppTheme.Spacing.lg)
                    }
                    .safeAreaInset(edge: .bottom) { saveBar(document, proxy: proxy) }
                }
                .frame(minWidth: 360, idealWidth: 440, maxWidth: 560)
            }
        }
    }

    private func documentStrip(_ document: DocumentModel) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            DocumentThumbnail(document: document, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("Compare with the original as you go").font(.caption).foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Spacer()
            Button("View") {
                leftPane = .original
                showOriginal = true
            }
            .buttonStyle(.bordered)
        }
        .card(padding: AppTheme.Spacing.md)
    }

    @ViewBuilder
    private func fieldsColumn(_ document: DocumentModel) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            summaryBanner
            documentCard
            ForEach(model.records) { record in
                RecordCard(
                    record: record,
                    issues: model.issues(for: record),
                    fallbackDate: record.kind == .visit ? nil : model.visitDate,
                    model: model,
                    onShowSource: { source in
                        highlight = source
                        leftPane = .text
                        if isCompact { showOriginal = true }
                    }
                )
                .id(record.id)
                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity.combined(with: .scale(scale: 0.92))))
            }
            Menu {
                ForEach(ReviewRecordKind.allCases) { kind in
                    Button(kind.title) {
                        withAnimation(AppTheme.Motion.animation(AppTheme.Motion.standard, reduceMotion: reduceMotion)) {
                            model.addRecord(kind)
                        }
                    }
                }
            } label: {
                Label(model.isManualMode && model.records.isEmpty ? "Add a record from this document" : "Add another record", systemImage: "plus.circle")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: AppTheme.Size.minTouch)
            }
            .buttonStyle(.secondary)
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle").foregroundStyle(AppTheme.Colors.dangerText)
            }
            Button("Discard details", role: .destructive) { confirmDiscard = true }
                .foregroundStyle(AppTheme.Colors.dangerText)
                .frame(maxWidth: .infinity, minHeight: AppTheme.Size.minTouch)
            MedicalDisclaimer()
        }
    }

    @ViewBuilder
    private var summaryBanner: some View {
        if model.isManualMode {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic extraction isn't available").font(.subheadline.weight(.semibold))
                    Text("The text was read on this device. Add records and copy details from the recognized text.")
                        .font(.caption)
                }
            } icon: {
                Image(systemName: "text.viewfinder")
            }
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .card()
        } else {
            let flagged = model.flaggedCount
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("We found \(model.records.count) \(model.records.count == 1 ? "record" : "records")")
                        .font(.subheadline.weight(.semibold))
                    Text(flagged > 0
                         ? "\(flagged) \(flagged == 1 ? "field is" : "fields are") marked Check — compare them with the original."
                         : "Check each one against the original before saving.")
                        .font(.caption)
                }
            } icon: {
                Image(systemName: flagged > 0 ? "questionmark.circle.fill" : "checklist")
                    .foregroundStyle(flagged > 0 ? AppTheme.Colors.statusWarning : AppTheme.Colors.brandPrimary)
            }
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .card()
            .contentTransition(.numericText())
        }
    }

    private var documentCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text("Document type")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Spacer()
                Picker("Document type", selection: $model.documentType) {
                    ForEach(DocumentType.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            ForEach(model.documentFields) { field in
                if field.key == .petName, let pet, !field.value.isEmpty,
                   field.value.range(of: pet.name, options: [.caseInsensitive, .diacriticInsensitive]) == nil {
                    HStack(alignment: .top) {
                        Image(systemName: "questionmark.circle.fill").foregroundStyle(AppTheme.Colors.statusWarning)
                        Text("This document mentions “\(field.value)”. Records will be saved to \(pet.name).")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.warningText)
                    }
                }
            }
        }
        .card()
    }

    /// First included record that still has something to resolve.
    private var nextRecordToCheck: ReviewRecord? {
        model.records.first { $0.included && !model.issues(for: $0).isEmpty }
    }

    private func saveBar(_ document: DocumentModel, proxy: ScrollViewProxy) -> some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Button {
                do {
                    let result = try model.confirm(document: document, fields: fieldModels, context: context)
                    saved = result
                } catch {
                    saveError = "Couldn't save. Your edits are still here — try again."
                }
            } label: {
                Text(model.saveTitle).contentTransition(.numericText())
            }
            .buttonStyle(.primary)
            .disabled(!model.canSave)
            .keyboardShortcut(.defaultAction)
            if !model.canSave && !model.includedRecords.isEmpty {
                if let next = nextRecordToCheck {
                    Button {
                        withAnimation(AppTheme.Motion.animation(AppTheme.Motion.standard, reduceMotion: reduceMotion)) {
                            proxy.scrollTo(next.id, anchor: .top)
                        }
                    } label: {
                        Label("Show next item to check", systemImage: "arrow.down.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.Colors.warningText)
                }
                Text("Resolve the items marked in each record, or untick records you don't want.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(.bar)
    }
}

// MARK: - Record card

private struct RecordCard: View {
    let record: ReviewRecord
    let issues: [String]
    let fallbackDate: Date?
    let model: ExtractionReviewModel
    let onShowSource: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var addableKeys: [ExtractionFieldKey] {
        record.kind.allowedKeys.filter { key in !record.fields.contains { $0.key == key } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                Button {
                    withAnimation(AppTheme.Motion.animation(AppTheme.Motion.quick, reduceMotion: reduceMotion)) {
                        if let index = model.records.firstIndex(where: { $0.id == record.id }) {
                            model.records[index].included.toggle()
                        }
                    }
                } label: {
                    Image(systemName: record.included ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(record.included ? AppTheme.Colors.brandPrimary : AppTheme.Colors.textSecondary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(record.included ? "Included — tap to skip" : "Skipped — tap to include")

                TypeIcon(systemImage: record.kind.eventType.symbol, tint: record.kind.eventType.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.kind.title).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.Colors.textSecondary)
                    Text(record.field(record.kind.primaryKey)?.value.nilIfEmpty.map(displayTitle) ?? "New \(record.kind.title.lowercased())")
                        .font(.headline)
                        .lineLimit(2)
                }
                Spacer()
                Menu {
                    ForEach(addableKeys, id: \.self) { key in
                        Button("Add \(key.label.lowercased())") {
                            withAnimation(AppTheme.Motion.animation(AppTheme.Motion.standard, reduceMotion: reduceMotion)) {
                                model.addField(key, to: record.id)
                            }
                        }
                    }
                    Divider()
                    Button("Remove record", role: .destructive) {
                        withAnimation(AppTheme.Motion.animation(AppTheme.Motion.standard, reduceMotion: reduceMotion)) {
                            model.removeRecord(record.id)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).frame(width: AppTheme.Size.minTouch, height: AppTheme.Size.minTouch)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("Record options")
            }

            if record.included {
                VStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(record.fields) { field in
                        FieldRow(
                            field: field,
                            onChange: { model.update(recordID: record.id, fieldID: field.id, value: $0) },
                            onSetDraft: { model.setDraftValue(recordID: record.id, fieldID: field.id, value: $0) },
                            onLooksRight: { model.markLooksRight(recordID: record.id, fieldID: field.id) },
                            onRemove: {
                                withAnimation(AppTheme.Motion.animation(AppTheme.Motion.standard, reduceMotion: reduceMotion)) {
                                    model.remove(recordID: record.id, fieldID: field.id)
                                }
                            },
                            onShowSource: onShowSource
                        )
                    }
                    if record.field(record.kind.dateKey) == nil, let fallbackDate {
                        Label("Date: visit date \(fallbackDate.shortDate)", systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .transition(.opacity)

                if !issues.isEmpty {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        ForEach(issues, id: \.self) { NeedsCheckBadge(text: $0) }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card()
        .opacity(record.included ? 1 : 0.6)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .strokeBorder(
                    issues.isEmpty || !record.included ? Color.clear : AppTheme.Colors.statusWarning,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
    }

    private func displayTitle(_ value: String) -> String {
        if record.kind.primaryKey.isDate, let date = ReviewDate.parse(value) { return date.shortDate }
        return value
    }
}

// MARK: - Field row

private struct FieldRow: View {
    let field: ReviewField
    let onChange: (String) -> Void
    /// Sets a starting value without clearing an AI "Check" flag.
    let onSetDraft: (String) -> Void
    let onLooksRight: () -> Void
    let onRemove: () -> Void
    let onShowSource: (String) -> Void

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(field.key.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(field.needsCheck ? AppTheme.Colors.warningText : AppTheme.Colors.textSecondary)
                if field.needsCheck { NeedsCheckBadge() }
                if field.key.isVerbatim {
                    Label("Exactly as written", systemImage: "quote.opening")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle").foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(field.key.label)")
            }

            editor

            if let source = field.sourceText {
                Button { onShowSource(source) } label: {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "text.quote")
                        Text("“\(source)”").lineLimit(2).multilineTextAlignment(.leading)
                        if let page = field.pageNumber { Text("· p.\(page)") }
                    }
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.sourceText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Source text: \(source). Show in document.")
            }

            if field.needsCheck {
                Button(field.isEmpty ? "Leave empty" : "Looks right", action: onLooksRight)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(AppTheme.Colors.warningText)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(
            (field.needsCheck ? AppTheme.Colors.statusWarning.opacity(0.10) : Color.clear),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.input, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.input, style: .continuous)
                .strokeBorder(field.needsCheck ? AppTheme.Colors.statusWarning : .clear, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .onAppear { text = field.value }
    }

    @ViewBuilder
    private var editor: some View {
        if field.key.isDate {
            if let date = field.dateValue {
                DatePicker(
                    field.key.label,
                    selection: Binding(get: { date }, set: { onChange(ReviewDate.string($0)) }),
                    displayedComponents: .date
                )
                .labelsHidden()
            } else {
                HStack {
                    Text(field.isEmpty ? "Not found" : "“\(field.value)” — unclear format")
                        .foregroundStyle(AppTheme.Colors.warningText)
                    Spacer()
                    // Starts the picker at today but keeps the field flagged until the user confirms.
                    Button("Set date") { onSetDraft(ReviewDate.string(.now)) }
                        .buttonStyle(.bordered)
                }
                .font(.subheadline)
            }
        } else {
            TextField(field.key.label, text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(field.key.isVerbatim ? .body.monospaced() : .body)
                .onSubmit { onChange(text) }
                .onChange(of: text) { _, newValue in
                    if newValue != field.value { onChange(newValue) }
                }
        }
    }
}

// MARK: - Source pane (original / recognized text)

struct SourcePane: View {
    let document: DocumentModel
    let highlight: String?
    @Binding var pane: ExtractionReviewView.LeftPane
    @Environment(AppContainer.self) private var container

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $pane) {
                ForEach(ExtractionReviewView.LeftPane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(AppTheme.Spacing.md)

            switch pane {
            case .original:
                DocumentPreview(url: container.fileStorage.resolveURL(relativePath: document.filePath), isPDF: document.isPDF)
            case .text:
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        if let highlight {
                            Label("Showing “\(highlight)”", systemImage: "text.quote")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.sourceText)
                        }
                        Text(highlighted(document.ocrText ?? "No text was recognized.", term: highlight))
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(AppTheme.Spacing.lg)
                }
            }
        }
        .background(AppTheme.Colors.bgSurface)
    }

    private func highlighted(_ text: String, term: String?) -> AttributedString {
        var attributed = AttributedString(text)
        guard let term, !term.isEmpty else { return attributed }
        var searchRange = attributed.startIndex..<attributed.endIndex
        while let range = attributed[searchRange].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[range].backgroundColor = AppTheme.Colors.statusSource.opacity(0.25)
            attributed[range].foregroundColor = AppTheme.Colors.textPrimary
            searchRange = range.upperBound..<attributed.endIndex
        }
        return attributed
    }
}

// MARK: - Saved confirmation

private struct SavedConfirmationView: View {
    let saved: [SavedRecordSummary]
    let petName: String
    let onAddReminder: (ReminderDraft) -> Void
    let onViewTimeline: () -> Void
    let onDone: () -> Void

    @State private var appeared = false

    private var dueSuggestions: [SavedRecordSummary] { saved.filter { ($0.nextDueDate ?? .distantPast) > .now } }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.xl) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AppTheme.Colors.statusSuccess)
                    .symbolEffect(.bounce, value: appeared)
                    .padding(.top, AppTheme.Spacing.xxxl)
                VStack(spacing: AppTheme.Spacing.xs) {
                    Text(saved.isEmpty ? "Document reviewed" : "Saved to \(petName)'s timeline")
                        .font(.title2.weight(.bold))
                    Text("Each record links back to the original document.")
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .multilineTextAlignment(.center)

                if !saved.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(saved) { item in
                            HStack(spacing: AppTheme.Spacing.md) {
                                TypeIcon(systemImage: item.type.symbol, tint: item.type.tint)
                                VStack(alignment: .leading) {
                                    Text(item.title).font(.subheadline.weight(.semibold))
                                    Text(item.date.shortDate).font(.caption).foregroundStyle(AppTheme.Colors.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, AppTheme.Spacing.sm)
                        }
                    }
                    .card()
                }

                if !dueSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Add a reminder?").font(.headline)
                        Text("These dates are stated on the document.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        ForEach(dueSuggestions) { item in
                            Button {
                                onAddReminder(ReminderDraft(
                                    title: "\(item.title) due",
                                    type: item.type == .vaccination ? .vaccination : .medication,
                                    dueDate: item.nextDueDate ?? .now,
                                    healthEventId: item.id
                                ))
                            } label: {
                                HStack {
                                    Label(item.title, systemImage: "bell.badge")
                                    Spacer()
                                    Text(item.nextDueDate?.shortDate ?? "").foregroundStyle(AppTheme.Colors.textSecondary)
                                }
                                .frame(minHeight: AppTheme.Size.minTouch)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .card()
                }

                VStack(spacing: AppTheme.Spacing.sm) {
                    Button("View timeline", action: onViewTimeline).buttonStyle(.primary)
                    Button("Done", action: onDone).buttonStyle(.secondary)
                }
            }
            .padding(AppTheme.Spacing.lg)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .onAppear { appeared = true }
    }
}

private extension View {
    @ViewBuilder
    func navigationBarBackButtonHiddenCompat() -> some View {
        navigationBarBackButtonHidden(true)
    }
}
