import SwiftData
import SwiftUI

/// Screen 13 — Global Search (offline, read-only). Searches every pet: titles, notes, clinics,
/// medications, vaccines, document titles and text recognized inside documents (PRD F11).
struct SearchView: View {
    var showsDoneButton = false

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query(sort: \HealthEventModel.eventDate, order: .reverse) private var events: [HealthEventModel]
    @Query(sort: \DocumentModel.createdAt, order: .reverse) private var documents: [DocumentModel]
    @Query private var pets: [PetModel]
    @State private var query = ""
    @State private var scope: Scope = .all

    enum Scope: String, CaseIterable, Identifiable {
        case all = "All", records = "Records", documents = "Documents"
        var id: String { rawValue }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var petNames: [UUID: String] { Dictionary(uniqueKeysWithValues: pets.map { ($0.id, $0.name) }) }

    private var matchingPets: [PetModel] {
        guard scope == .all else { return [] }
        return pets.filter { $0.name.localizedStandardContains(trimmed) || ($0.microchipNumber ?? "").localizedStandardContains(trimmed) }
    }

    private var matchingEvents: [HealthEventModel] {
        guard scope != .documents else { return [] }
        return events.filter { event in
            [event.title, event.notes, event.providerName, event.dosageText, event.frequencyText, event.eventType.title]
                .compactMap { $0 }
                .contains { $0.localizedStandardContains(trimmed) }
        }
    }

    private struct DocumentMatch: Identifiable {
        let document: DocumentModel
        let snippet: String?
        var id: UUID { document.id }
    }

    private var matchingDocuments: [DocumentMatch] {
        guard scope != .records else { return [] }
        return documents.compactMap { doc in
            if doc.displayTitle.localizedStandardContains(trimmed) || doc.docType.title.localizedStandardContains(trimmed) {
                return DocumentMatch(document: doc, snippet: nil)
            }
            if let text = doc.ocrText, let snippet = Self.snippet(in: text, for: trimmed) {
                return DocumentMatch(document: doc, snippet: snippet)
            }
            return nil
        }
    }

    private struct Suggestion { let text: String; let symbol: String }

    /// Quick starts built from the user's own data: recent vaccines and medications, then clinics.
    private var suggestions: [Suggestion] {
        var seen = Set<String>()
        var result: [Suggestion] = []
        func add(_ text: String?, _ symbol: String) {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
                  seen.insert(text.lowercased()).inserted, result.count < 6 else { return }
            result.append(Suggestion(text: text, symbol: symbol))
        }
        for event in events where event.eventType == .vaccination || event.eventType == .medication {
            add(event.title, event.eventType.symbol)
        }
        for event in events { add(event.providerName, "building.2") }
        return result
    }

    var body: some View {
        @Bindable var appState = appState
        RouteList {
            if trimmed.isEmpty {
                ContentUnavailableView {
                    Label("Search all records", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a vaccine, medication, clinic, or words from inside a scanned document. Works offline.")
                }
                .listRowBackground(Color.clear)
                if !suggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(suggestions, id: \.text) { suggestion in
                            Button { query = suggestion.text } label: {
                                Label(suggestion.text, systemImage: suggestion.symbol)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                            }
                        }
                    }
                }
            } else if matchingPets.isEmpty && matchingEvents.isEmpty && matchingDocuments.isEmpty {
                ContentUnavailableView.search(text: trimmed)
                    .listRowBackground(Color.clear)
            } else {
                if !matchingPets.isEmpty {
                    Section("Pets") {
                        ForEach(matchingPets) { pet in
                            Button {
                                appState.switchPet(to: pet.id)
                                if showsDoneButton { dismiss() }
                            } label: {
                                HStack { PetAvatar(pet: pet, size: 32); Text(pet.name) }
                            }
                        }
                    }
                }
                if !matchingEvents.isEmpty {
                    Section("Health records (\(matchingEvents.count))") {
                        ForEach(matchingEvents.prefix(50)) { event in
                            NavigationLink(value: Route.event(event.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    TimelineRow(event: event, sourceTitle: nil, showsRail: false)
                                    if pets.count > 1, let name = petNames[event.petId] {
                                        Text(name).font(.appCaption).foregroundStyle(AppTheme.Colors.textSecondary).padding(.leading, 48)
                                    }
                                }
                            }
                        }
                    }
                }
                if !matchingDocuments.isEmpty {
                    Section("Documents (\(matchingDocuments.count))") {
                        ForEach(matchingDocuments.prefix(50)) { match in
                            let doc = match.document
                            let snippet = match.snippet
                            NavigationLink(value: Route.document(doc.id)) {
                                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                                    DocumentThumbnail(document: doc, size: 40)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(doc.displayTitle).font(.body.weight(.semibold))
                                        Text([doc.docType.title, pets.count > 1 ? petNames[doc.petId] : nil].compactMap { $0 }.joined(separator: " · "))
                                            .font(.appCaption).foregroundStyle(AppTheme.Colors.textSecondary)
                                        if let snippet {
                                            Text(Self.highlight(snippet, term: trimmed))
                                                .font(.appCaption)
                                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                                .lineLimit(3)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, isPresented: $appState.isSearchPresented, prompt: "Vaccines, meds, clinics, document text")
        .searchScopes($scope) {
            ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
        }
        .navigationTitle("Search")
        .modifier(SheetRouteDestinations(enabled: showsDoneButton))
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear { if showsDoneButton { appState.isSearchPresented = true } }
    }

    static func snippet(in text: String, for term: String, radius: Int = 48) -> String? {
        guard let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        let body = text[start..<end].replacingOccurrences(of: "\n", with: " ")
        return (start > text.startIndex ? "…" : "") + body + (end < text.endIndex ? "…" : "")
    }

    static func highlight(_ text: String, term: String) -> AttributedString {
        var attributed = AttributedString(text)
        if let range = attributed.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[range].foregroundColor = AppTheme.Colors.textPrimary
            attributed[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }
}

/// Registers Route destinations only when the view owns its NavigationStack (presented as a sheet).
struct SheetRouteDestinations: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.navigationDestination(for: Route.self) { RouteView(route: $0) }
        } else {
            content
        }
    }
}
