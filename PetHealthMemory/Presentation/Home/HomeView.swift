import SwiftData
import SwiftUI

/// Screen 1 — Home (Pet Dashboard).
/// Hierarchy: who (pet) → do (capture) → attention (due / needs review) → prepare (vet summary) → recent.
struct HomeView: View {
    let petID: UUID

    @Environment(AppState.self) private var appState
    @Environment(\.isCompactLayout) private var isCompact
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("syncMode") private var syncModeRaw = SyncMode.localOnly.rawValue

    @Query private var pets: [PetModel]
    @Query private var events: [HealthEventModel]
    @Query private var reminders: [ReminderModel]
    @Query private var documents: [DocumentModel]

    init(petID: UUID) {
        self.petID = petID
        _pets = Query(filter: #Predicate<PetModel> { $0.id == petID })
        _events = Query(
            filter: #Predicate<HealthEventModel> { $0.petId == petID },
            // createdAt breaks ties so same-day events keep a stable order.
            sort: [SortDescriptor(\.eventDate, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        _reminders = Query(filter: #Predicate<ReminderModel> { $0.petId == petID }, sort: \.dueDate)
        _documents = Query(filter: #Predicate<DocumentModel> { $0.petId == petID }, sort: \.createdAt, order: .reverse)
    }

    private var pet: PetModel? { pets.first }
    private var dueSoon: [ReminderModel] {
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        return reminders.filter { $0.isOpen && $0.dueDate <= horizon }
    }
    private var docsToReview: [DocumentModel] { documents.filter { $0.status.needsReview } }
    private var failedDocs: [DocumentModel] { documents.filter { $0.status == .failed } }
    private var activeMeds: [HealthEventModel] { events.filter(\.isActiveMedication) }
    private var latestVaccines: [HealthEventModel] {
        var seen = Set<String>()
        return events.filter { $0.eventType == .vaccination && seen.insert($0.title.lowercased()).inserted }
    }
    private var allergies: [HealthEventModel] { events.filter { $0.eventType == .allergy } }
    private var isBrandNew: Bool { events.isEmpty && documents.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                header
                captureCard
                if isBrandNew {
                    firstRunGuide
                } else {
                    attentionSection
                    vetSummarySection
                    recentSection
                }
                MedicalDisclaimer()
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xxxl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .id(petID) // crossfade content on pet switch
            .transition(.opacity)
        }
        .animation(AppTheme.Motion.animation(AppTheme.Motion.quick, reduceMotion: reduceMotion), value: petID)
        .canvasBackground()
        .navigationTitle("Home")
        #if os(iOS)
        .toolbar(isCompact ? .hidden : .automatic, for: .navigationBar)
        #else
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { appState.sheet = .export } label: { Label("Export PDF", systemImage: "square.and.arrow.up") }
            }
        }
        #endif
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            PetAvatar(pet: pet, size: 56)
                .routeButton(.petProfile(petID))
                .accessibilityLabel("Open \(pet?.name ?? "pet") profile")

            VStack(alignment: .leading, spacing: 2) {
                PetSwitcherMenu {
                    HStack(spacing: 4) {
                        Text(pet?.name ?? "")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                Text(pet?.subtitle ?? "")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                syncIndicator
            }
            Spacer()
            #if os(iOS)
            HStack(spacing: 0) {
                Button { appState.sheet = .search } label: {
                    Image(systemName: "magnifyingglass").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Search")
                Button { appState.sheet = .settings } label: {
                    Image(systemName: "gearshape").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
            .font(.title3)
            .foregroundStyle(AppTheme.Colors.textPrimary)
            #endif
        }
        .padding(.top, AppTheme.Spacing.md)
    }

    /// Only shown when sync is on — "Local only" is the quiet default (DESIGN.md Sync UX).
    @ViewBuilder
    private var syncIndicator: some View {
        let mode = SyncMode(rawValue: syncModeRaw) ?? .localOnly
        if mode != .localOnly {
            Label(mode == .iCloud ? "iCloud · Synced" : "Backend · Synced", systemImage: "checkmark.icloud")
                .font(.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    // MARK: Capture (1 tap away)

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                TypeIcon(systemImage: "doc.viewfinder", tint: AppTheme.Colors.brandPrimary, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a vet document")
                        .font(.headline)
                    Text("Read on this device. You check everything before it's saved.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            // Icon-over-title tiles: three equal columns always fit an iPhone width
            // (a horizontal icon + title row truncated "Photos" on 6.1" screens).
            HStack(spacing: AppTheme.Spacing.sm) { captureButtons }
                .labelStyle(TileLabelStyle())
        }
        .card()
    }

    @ViewBuilder
    private var captureButtons: some View {
        #if os(iOS)
        Button { appState.sheet = .capture(source: .camera) } label: {
            Label("Scan", systemImage: "camera.fill")
        }
        .buttonStyle(.primary)
        #endif
        Button { appState.sheet = .capture(source: .photos) } label: {
            Label("Photos", systemImage: "photo.on.rectangle")
        }
        .buttonStyle(.secondary)
        Button { appState.sheet = .capture(source: .files) } label: {
            Label("Files", systemImage: "folder")
        }
        .buttonStyle(.secondary)
    }

    // MARK: First run

    private var firstRunGuide: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("How it works").font(.headline)
            guideStep(1, "Scan a vaccination card, invoice or report", "camera.viewfinder")
            guideStep(2, "Check the details we found — amber means “please check”", "checklist")
            guideStep(3, "It's saved to \(pet?.name ?? "your pet")'s timeline, linked to the original", "clock.arrow.circlepath")
            Divider()
            Button { appState.sheet = .newEvent(type: nil) } label: {
                Label("Or add a record by hand", systemImage: "square.and.pencil")
            }
            .foregroundStyle(AppTheme.Colors.brandText)
            .frame(minHeight: AppTheme.Size.minTouch)
        }
        .card()
    }

    private func guideStep(_ number: Int, _ text: String, _ symbol: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.Colors.brandText)
                .frame(width: 28, height: 28)
                .background(AppTheme.Colors.brandPrimarySoft, in: Circle())
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
            Image(systemName: symbol).foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Needs attention

    @ViewBuilder
    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionHeader(title: "Needs attention")
            if dueSoon.isEmpty && docsToReview.isEmpty && failedDocs.isEmpty {
                Label("All caught up", systemImage: "checkmark.seal")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.successText)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(docsToReview.prefix(3)) { doc in
                        attentionRow(
                            icon: "doc.badge.ellipsis", tint: AppTheme.Colors.statusWarning,
                            title: "Review \(doc.displayTitle)",
                            subtitle: doc.status == .extracted ? "Details found — confirm before saving" : "Text read — add details by hand"
                        ) { appState.sheet = .review(documentID: doc.id) }
                    }
                    ForEach(failedDocs.prefix(2)) { doc in
                        attentionRow(
                            icon: "exclamationmark.triangle", tint: AppTheme.Colors.statusDanger,
                            title: "Couldn't read \(doc.displayTitle)",
                            subtitle: "Retry or enter details by hand"
                        ) { appState.open(.document(doc.id), in: .documents, compact: isCompact) }
                    }
                    ForEach(dueSoon.prefix(4)) { reminder in
                        attentionRow(
                            icon: reminder.type.symbol, tint: DueState(date: reminder.dueDate).fill,
                            title: reminder.title,
                            subtitle: nil,
                            badge: AnyView(DueBadge(date: reminder.dueDate))
                        ) { appState.sheet = .editReminder(reminder.id) }
                    }
                }
                .card(padding: 0)
            }
        }
    }

    private func attentionRow(
        icon: String, tint: Color, title: String, subtitle: String?, badge: AnyView? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                TypeIcon(systemImage: icon, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.Colors.textPrimary).lineLimit(2)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                badge
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Vet visit summary (appointment preparation)

    private var vetSummarySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionHeader(title: "Ready for the vet", actionTitle: "Export PDF") { appState.sheet = .export }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                summaryGroup(title: "Active medications", symbol: "pills.fill", empty: "None recorded", items: activeMeds.map { med in
                    SummaryItem(id: med.id, name: med.title, detail: [med.dosageText, med.frequencyText].compactMap { $0 }.joined(separator: " · "))
                })
                Divider()
                summaryGroup(title: "Latest vaccinations", symbol: "syringe.fill", empty: "None recorded", items: latestVaccines.prefix(4).map { vaccine in
                    let given = "Given \(vaccine.eventDate.shortDate)"
                    return SummaryItem(
                        id: vaccine.id, name: vaccine.title,
                        detail: vaccine.nextDueDate.map { "\(given) · next due \($0.shortDate)" } ?? given
                    )
                })
                if !allergies.isEmpty {
                    Divider()
                    summaryGroup(title: "Allergies", symbol: "allergens.fill", empty: "", items: allergies.map { SummaryItem(id: $0.id, name: $0.title, detail: $0.notes ?? "") })
                }
            }
            .card()
        }
    }

    private struct SummaryItem: Identifiable {
        let id: UUID
        let name: String
        let detail: String
    }

    private func summaryGroup(title: String, symbol: String, empty: String, items: [SummaryItem]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            if items.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(AppTheme.Colors.textSecondary)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.body.weight(.medium)).foregroundStyle(AppTheme.Colors.textPrimary)
                    if !item.detail.isEmpty {
                        Text(item.detail).font(.caption).foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .routeButton(.event(item.id), section: .history)
            }
        }
    }

    // MARK: Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionHeader(title: "Recent history", actionTitle: events.isEmpty ? nil : "See all") {
                appState.section = .history
            }
            if events.isEmpty {
                Text("Confirmed records will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(events.prefix(3)) { event in
                        TimelineRow(event: event, sourceTitle: nil, showsRail: false)
                            .padding(.horizontal, AppTheme.Spacing.lg)
                            .padding(.vertical, AppTheme.Spacing.sm)
                            .routeButton(.event(event.id), section: .history)
                    }
                }
                .card(padding: 0)
            }
        }
    }
}
