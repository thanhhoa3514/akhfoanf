import SwiftData
import SwiftUI

private struct CompactLayoutKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// true → iPhone tab layout (push navigation). false → split view (detail column).
    var isCompactLayout: Bool {
        get { self[CompactLayoutKey.self] }
        set { self[CompactLayoutKey.self] = newValue }
    }
}

/// First-launch gate + adaptive navigation shell.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppContainer.self) private var container
    @Query(sort: \PetModel.createdAt) private var pets: [PetModel]
    @Query private var reminders: [ReminderModel]
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var isCompact: Bool {
        #if os(iOS)
        return sizeClass != .regular
        #else
        return false
        #endif
    }

    var body: some View {
        @Bindable var appState = appState
        Group {
            if pets.isEmpty {
                // No heavy onboarding: first launch goes straight to creating a pet (DESIGN.md).
                NavigationStack {
                    PetFormView(mode: .firstLaunch)
                }
            } else if isCompact {
                PhoneTabRoot()
            } else {
                SplitRoot()
            }
        }
        .environment(\.isCompactLayout, isCompact)
        .sheet(item: $appState.sheet) { sheet in
            SheetRouter(sheet: sheet)
                .environment(\.isCompactLayout, isCompact)
        }
        .onAppear(perform: ensureSelectedPet)
        .onChange(of: pets.map(\.id)) { _, _ in ensureSelectedPet() }
        .task { await reconcileNotifications() }
    }

    private func ensureSelectedPet() {
        if let id = appState.selectedPetID, pets.contains(where: { $0.id == id }) { return }
        appState.selectedPetID = pets.first?.id
    }

    /// PRD F09: notification state is reconciled on every launch.
    private func reconcileNotifications() async {
        let petNames = Dictionary(uniqueKeysWithValues: pets.map { ($0.id, $0.name) })
        let open = reminders.filter(\.isOpen).map {
            (id: $0.id, title: $0.title, body: petNames[$0.petId] ?? "", dueDate: $0.dueDate)
        }
        await container.notificationService.reconcile(reminders: open)
    }
}

// MARK: - iPhone

private struct PhoneTabRoot: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.section) {
            ForEach(AppSection.phoneTabs) { section in
                SectionStack(section: section)
                    .tabItem { Label(section.title, systemImage: section.symbol) }
                    .tag(section)
            }
        }
        .onChange(of: appState.section) { _, newValue in
            // ⌘F on an iPad keyboard in compact width: search lives on Home.
            if newValue == .search {
                appState.section = .home
                appState.sheet = .search
            }
        }
    }
}

/// NavigationStack per tab with shared route destinations and zoom namespace.
private struct SectionStack: View {
    let section: AppSection
    @Environment(AppState.self) private var appState
    @Namespace private var zoom

    var body: some View {
        NavigationStack(path: appState.path(for: section)) {
            SectionRootView(section: section)
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route)
                }
        }
        .environment(\.zoomNamespace, zoom)
    }
}

// MARK: - macOS / iPad

private struct SplitRoot: View {
    @Environment(AppState.self) private var appState
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } content: {
            SectionRootView(section: appState.section)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
        } detail: {
            NavigationStack {
                Group {
                    if let route = appState.detailRoute {
                        RouteView(route: route)
                            .id(route)
                    } else {
                        DetailPlaceholder(section: appState.section)
                    }
                }
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
        }
        .onChange(of: appState.section) { _, _ in appState.detailRoute = nil }
        .onChange(of: appState.selectedPetID) { _, _ in appState.detailRoute = nil }
    }
}

private struct DetailPlaceholder: View {
    let section: AppSection
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if section == .home, let petID = appState.selectedPetID {
                PetProfileDetailView(petID: petID)
            } else {
                ContentUnavailableView(
                    placeholderTitle,
                    systemImage: section.symbol,
                    description: Text(placeholderMessage)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .canvasBackground()
    }

    private var placeholderTitle: String {
        switch section {
        case .documents: "Select a document"
        case .history: "Select a record"
        case .reminders: "Reminders"
        case .search: "Search everything"
        case .home: "Pet Health Memory"
        }
    }

    private var placeholderMessage: String {
        switch section {
        case .documents: "Drop PDFs or photos onto the list to import them."
        case .history: "Records you open appear here, with their source document."
        case .reminders: "Pick a reminder to edit it, or press ⇧⌘R to add one."
        case .search: "Vaccines, medications, clinics, notes and text inside documents."
        case .home: ""
        }
    }
}

// MARK: - Shared roots

/// Section root view shared by iPhone tabs and the split view content column.
struct SectionRootView: View {
    let section: AppSection
    @Environment(AppState.self) private var appState

    var body: some View {
        if let petID = appState.selectedPetID {
            switch section {
            case .home: HomeView(petID: petID)
            case .history: TimelineView(petID: petID)
            case .documents: DocumentsListView(petID: petID)
            case .reminders: RemindersView(petID: petID)
            case .search: SearchView()
            }
        } else {
            ProgressView()
        }
    }
}

struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .event(let id): HealthEventDetailView(eventID: id)
        case .document(let id): DocumentDetailView(documentID: id).zoomDestination(id: route)
        case .petProfile(let id): PetProfileDetailView(petID: id)
        case .weightLog(let id): WeightLogView(petID: id)
        }
    }
}

/// Every modal in the app, presented from the root so any screen (or a menu command) can open it.
struct SheetRouter: View {
    let sheet: AppSheet
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch sheet {
            case .newPet:
                NavigationStack { PetFormView(mode: .create) }
            case .editPet(let id):
                NavigationStack { PetFormView(mode: .edit(id)) }
            case .capture(let source):
                if let petID = appState.selectedPetID {
                    DocumentCaptureFlow(petID: petID, initialSource: source)
                }
            case .review(let documentID):
                NavigationStack { ExtractionReviewView(documentID: documentID) }
            case .newEvent(let type):
                if let petID = appState.selectedPetID {
                    NavigationStack { HealthEventFormView(mode: .create(petID: petID, type: type)) }
                }
            case .editEvent(let id):
                NavigationStack { HealthEventFormView(mode: .edit(id)) }
            case .newReminder(let draft):
                if let petID = appState.selectedPetID {
                    NavigationStack { ReminderFormView(mode: .create(petID: petID, draft: draft)) }
                }
            case .editReminder(let id):
                NavigationStack { ReminderFormView(mode: .edit(id)) }
            case .export:
                if let petID = appState.selectedPetID {
                    NavigationStack { ExportReportView(petID: petID) }
                }
            case .settings:
                NavigationStack { SettingsView(showsDoneButton: true) }
            case .search:
                NavigationStack { SearchView(showsDoneButton: true) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 560, idealHeight: 680)
        #endif
    }
}
