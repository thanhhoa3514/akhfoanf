import Foundation
import Observation
import SwiftUI

/// Pushable destinations. Value-based so iPhone NavigationStacks and macOS split-view
/// list selections share one routing vocabulary.
enum Route: Hashable {
    case event(UUID)
    case document(UUID)
    case petProfile(UUID)
    case weightLog(UUID)
}

/// Sidebar sections (macOS / iPad) == tabs (iPhone).
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home, history, documents, reminders, search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .history: String(localized: "Health History")
        case .documents: String(localized: "Documents")
        case .reminders: String(localized: "Reminders")
        case .search: String(localized: "Search")
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .history: "heart.text.square"
        case .documents: "doc.text"
        case .reminders: "bell"
        case .search: "magnifyingglass"
        }
    }

    /// iPhone shows 4 tabs; search lives in the Home toolbar there.
    static var phoneTabs: [AppSection] { [.home, .history, .documents, .reminders] }
}

/// Prefill for a new reminder (e.g. from an explicitly stated vaccine due date).
struct ReminderDraft: Identifiable, Hashable {
    let id = UUID()
    var title: String = ""
    var type: ReminderType = .custom
    var dueDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    var healthEventId: UUID?
}

/// App-wide modal sheets.
enum AppSheet: Identifiable, Hashable {
    case newPet
    case editPet(UUID)
    case capture(source: CaptureSource?)
    case review(documentID: UUID)
    case newEvent(type: HealthEventType?)
    case editEvent(UUID)
    case newReminder(ReminderDraft)
    case editReminder(UUID)
    case export
    case settings
    case search

    var id: String {
        switch self {
        case .newPet: "newPet"
        case .editPet(let id): "editPet-\(id)"
        case .capture(let source): "capture-\(source?.rawValue ?? "choose")"
        case .review(let id): "review-\(id)"
        case .newEvent(let type): "newEvent-\(type?.rawValue ?? "any")"
        case .editEvent(let id): "editEvent-\(id)"
        case .newReminder(let draft): "newReminder-\(draft.id)"
        case .editReminder(let id): "editReminder-\(id)"
        case .export: "export"
        case .settings: "settings"
        case .search: "search"
        }
    }
}

enum CaptureSource: String, Hashable {
    case camera, photos, files
}

@MainActor
@Observable
final class AppState {
    private static let selectedPetKey = "selectedPetID"

    var selectedPetID: UUID? {
        didSet { UserDefaults.standard.set(selectedPetID?.uuidString, forKey: Self.selectedPetKey) }
    }
    var section: AppSection = .home
    var sheet: AppSheet?
    /// macOS / iPad detail-column selection.
    var detailRoute: Route?
    /// iPhone per-tab navigation paths.
    var paths: [AppSection: [Route]] = [:]
    /// Set by ⌘F to activate the search field.
    var isSearchPresented = false

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.selectedPetKey) {
            selectedPetID = UUID(uuidString: raw)
        }
    }

    func path(for section: AppSection) -> Binding<[Route]> {
        Binding(
            get: { self.paths[section] ?? [] },
            set: { self.paths[section] = $0 }
        )
    }

    /// Opens a route in the right container for the current layout.
    func open(_ route: Route, in section: AppSection? = nil, compact: Bool) {
        if compact {
            let target = section ?? self.section
            self.section = target
            paths[target, default: []].append(route)
        } else {
            // Split view: keep the current content column, open in the detail column.
            detailRoute = route
        }
    }

    func switchPet(to id: UUID) {
        selectedPetID = id
        detailRoute = nil
        paths = [:]
    }
}
