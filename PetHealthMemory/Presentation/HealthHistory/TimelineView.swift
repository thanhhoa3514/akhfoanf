import SwiftData
import SwiftUI

enum TimelineFilter: String, CaseIterable, Identifiable {
    case all, visits, vaccines, medications, labs, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .visits: String(localized: "Visits")
        case .vaccines: String(localized: "Vaccines")
        case .medications: String(localized: "Meds")
        case .labs: String(localized: "Labs")
        case .other: String(localized: "Other")
        }
    }

    func matches(_ type: HealthEventType) -> Bool {
        switch self {
        case .all: true
        case .visits: type == .veterinaryVisit || type == .surgery
        case .vaccines: type == .vaccination
        case .medications: type == .medication
        case .labs: type == .laboratoryResult || type == .diagnosis
        case .other: [.allergy, .symptom, .weight, .note, .other].contains(type)
        }
    }
}

/// Screen 2 — Health History (chronological timeline, grouped by month).
struct TimelineView: View {
    let petID: UUID

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var events: [HealthEventModel]
    @Query private var documents: [DocumentModel]
    @State private var filter: TimelineFilter = .all

    init(petID: UUID) {
        self.petID = petID
        _events = Query(
            filter: #Predicate<HealthEventModel> { $0.petId == petID },
            // createdAt breaks ties so same-day events keep a stable order.
            sort: [SortDescriptor(\.eventDate, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        _documents = Query(filter: #Predicate<DocumentModel> { $0.petId == petID })
    }

    private var filtered: [HealthEventModel] { events.filter { filter.matches($0.eventType) } }

    private struct MonthGroup: Identifiable {
        let id: Date
        let events: [HealthEventModel]
    }

    private var grouped: [MonthGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filtered) { event in
            calendar.date(from: calendar.dateComponents([.year, .month], from: event.eventDate)) ?? event.eventDate
        }
        return groups.keys.sorted(by: >).map { MonthGroup(id: $0, events: groups[$0] ?? []) }
    }

    private var docTitles: [UUID: String] {
        Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0.displayTitle) })
    }

    var body: some View {
        RouteList(firstRoute: filtered.first.map { .event($0.id) }) {
            Section {
                FilterPillBar(options: TimelineFilter.allCases, selection: $filter, title: \.title)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if filtered.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(grouped) { group in
                    Section(group.id.monthYear) {
                        ForEach(group.events) { event in
                            NavigationLink(value: Route.event(event.id)) {
                                TimelineRow(
                                    event: event,
                                    sourceTitle: event.sourceDocumentId.flatMap { docTitles[$0] },
                                    showsRail: true
                                )
                            }
                            .listRowSeparator(.hidden)
                        }
                    }
                }
            }
        }
        .animation(AppTheme.Motion.animation(AppTheme.Motion.quick, reduceMotion: reduceMotion), value: filter)
        .navigationTitle("Health History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(HealthEventType.allCases, id: \.self) { type in
                        Button { appState.sheet = .newEvent(type: type) } label: {
                            Label(type.title, systemImage: type.symbol)
                        }
                    }
                } label: {
                    Label("Add record", systemImage: "plus")
                } primaryAction: {
                    appState.sheet = .newEvent(type: nil)
                }
                .menuIndicator(.hidden)
                .help("New health event (⌘N)")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if events.isEmpty {
            ContentUnavailableView {
                Label("No health records yet", systemImage: "heart.text.square")
            } description: {
                Text("Import a vet document and confirm the details, or add a record by hand.")
            } actions: {
                Button("Import a document") { appState.sheet = .capture(source: nil) }
                    .buttonStyle(.borderedProminent)
                Button("Add by hand") { appState.sheet = .newEvent(type: nil) }
            }
        } else {
            ContentUnavailableView(
                "No \(filter.title.lowercased()) yet",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Try another filter.")
            )
        }
    }
}

/// Timeline row: type icon on a vertical rail, title, date, key detail, and source badge.
struct TimelineRow: View {
    let event: HealthEventModel
    let sourceTitle: String?
    var showsRail = true

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            TypeIcon(systemImage: event.eventType.symbol, tint: event.eventType.tint)
                .background(alignment: .top) {
                    if showsRail {
                        Rectangle()
                            .fill(AppTheme.Colors.borderSubtle)
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                            .offset(y: AppTheme.Size.rowIcon)
                            .padding(.bottom, -AppTheme.Spacing.xl)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: AppTheme.Spacing.sm)
                    Text(event.eventDate.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.appCaption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                if let detail = keyDetail {
                    Text(detail)
                        .font(.appSubheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: AppTheme.Spacing.xs) {
                    if event.eventType == .medication {
                        Pill(
                            text: event.isActiveMedication ? String(localized: "Active") : String(localized: "Completed"),
                            systemImage: event.isActiveMedication ? "circle.fill" : "checkmark",
                            tint: event.isActiveMedication ? AppTheme.Colors.statusSuccess : AppTheme.Colors.textSecondary,
                            textColor: event.isActiveMedication ? AppTheme.Colors.successText : AppTheme.Colors.textSecondary
                        )
                    }
                    if let due = event.nextDueDate {
                        DueBadge(date: due, soonWindow: event.eventType == .vaccination
                                 ? DueState.vaccineSoonWindow : DueState.defaultSoonWindow)
                    }
                    if let sourceTitle {
                        SourceBadge(title: sourceTitle)
                    }
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.eventType.title), \(event.title), \(event.eventDate.shortDate)")
    }

    private var keyDetail: String? {
        switch event.eventType {
        case .medication:
            return [event.dosageText, event.frequencyText].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        default:
            return [event.providerName, event.notes].compactMap { $0 }.first
        }
    }
}
