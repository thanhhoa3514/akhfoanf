import Foundation
import SwiftUI

struct PDFReportOptions: Sendable, Hashable {
    var startDate: Date?
    var endDate: Date?
    var includeProfile: Bool = true
    var includeVisits: Bool = true
    var includeVaccinations: Bool = true
    var includeMedications: Bool = true
    var includeOtherEvents: Bool = true
    var includeWeights: Bool = true
    var includeNotes: Bool = true
    var includeDocumentReferences: Bool = true
}

enum PDFReportError: LocalizedError {
    case couldNotCreateFile
    var errorDescription: String? { "The PDF couldn't be created. Please try again." }
}

@MainActor
protocol PDFReportServiceProtocol {
    func generateReport(
        pet: PetModel,
        events: [HealthEventModel],
        weights: [WeightEntryModel],
        documents: [DocumentModel],
        options: PDFReportOptions
    ) throws -> URL
}

/// Offline health report generator. Renders SwiftUI pages with `ImageRenderer` into a
/// CoreGraphics PDF context — identical output on iOS and macOS, no network.
@MainActor
final class PDFReportService: PDFReportServiceProtocol {
    static let pageSize = CGSize(width: 612, height: 792) // US Letter @72dpi
    private static let usableHeight: CGFloat = 792 - 2 * 40 - 30

    func generateReport(
        pet: PetModel,
        events: [HealthEventModel],
        weights: [WeightEntryModel],
        documents: [DocumentModel],
        options: PDFReportOptions
    ) throws -> URL {
        let blocks = Self.makeBlocks(pet: pet, events: events, weights: weights, documents: documents, options: options)
        let pages = Self.paginate(blocks)

        let safeName = pet.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName) Health Report \(Date.now.formatted(.iso8601.year().month().day())).pdf")
        var box = CGRect(origin: .zero, size: Self.pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw PDFReportError.couldNotCreateFile }

        for (index, page) in pages.enumerated() {
            let renderer = ImageRenderer(
                content: ReportPageView(blocks: page, pageNumber: index + 1, pageCount: pages.count, petName: pet.name)
                    .environment(\.colorScheme, .light)
            )
            renderer.proposedSize = ProposedViewSize(Self.pageSize)
            renderer.render { _, render in
                context.beginPDFPage(nil)
                render(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return url
    }

    // MARK: - Content model

    enum Block: Hashable {
        case header(title: String, subtitle: String, range: String)
        case section(String)
        case row(title: String, detail: String, date: String)
        case paragraph(String)

        var estimatedHeight: CGFloat {
            switch self {
            case .header: 110
            case .section: 34
            case .row: 40
            case .paragraph(let text): CGFloat(max(1, text.count / 90 + 1)) * 16 + 8
            }
        }
    }

    private static func makeBlocks(
        pet: PetModel,
        events: [HealthEventModel],
        weights: [WeightEntryModel],
        documents: [DocumentModel],
        options: PDFReportOptions
    ) -> [Block] {
        func inRange(_ date: Date) -> Bool {
            if let start = options.startDate, date < start { return false }
            if let end = options.endDate, date > end { return false }
            return true
        }
        let rangeText: String = {
            switch (options.startDate, options.endDate) {
            case let (start?, end?): "\(start.shortDate) – \(end.shortDate)"
            case let (start?, nil): "Since \(start.shortDate)"
            case let (nil, end?): "Until \(end.shortDate)"
            default: "All records"
            }
        }()

        var blocks: [Block] = [.header(title: "\(pet.name) — Health Report", subtitle: pet.subtitle, range: rangeText)]
        let docTitles = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0.displayTitle) })
        let filtered = events.filter { inRange($0.eventDate) }.sorted { $0.eventDate > $1.eventDate }

        if options.includeProfile {
            blocks.append(.section("Profile"))
            var lines: [String] = []
            if let birth = pet.birthDate { lines.append("Born \(birth.shortDate)") }
            if let sex = pet.sex, !sex.isEmpty { lines.append("Sex: \(sex)") }
            if let chip = pet.microchipNumber, !chip.isEmpty { lines.append("Microchip: \(chip)") }
            if !lines.isEmpty { blocks.append(.paragraph(lines.joined(separator: " · "))) }
            if options.includeNotes, let notes = pet.notes, !notes.isEmpty { blocks.append(.paragraph(notes)) }
        }

        func rows(for type: HealthEventType) -> [Block] {
            filtered.filter { $0.eventType == type }.map { event in
                var detail: [String] = []
                if let clinic = event.providerName { detail.append(clinic) }
                if let due = event.nextDueDate { detail.append("Next due \(due.shortDate)") }
                if let dosage = event.dosageText { detail.append(dosage) }
                if let freq = event.frequencyText { detail.append(freq) }
                if event.eventType == .medication { detail.append(event.isActiveMedication ? "Active" : "Completed") }
                if options.includeNotes, let notes = event.notes, !notes.isEmpty { detail.append(notes) }
                if options.includeDocumentReferences, let src = event.sourceDocumentId, let title = docTitles[src] {
                    detail.append("Source: \(title)")
                }
                return .row(title: event.title, detail: detail.joined(separator: " · "), date: event.eventDate.shortDate)
            }
        }

        let sections: [(Bool, String, [HealthEventType])] = [
            (options.includeVaccinations, "Vaccinations", [.vaccination]),
            (options.includeMedications, "Medications", [.medication]),
            (options.includeVisits, "Vet visits", [.veterinaryVisit]),
            (options.includeOtherEvents, "Other health events", [.surgery, .diagnosis, .allergy, .symptom, .laboratoryResult, .note, .other])
        ]
        for (enabled, title, types) in sections where enabled {
            let sectionRows = types.flatMap(rows(for:))
            guard !sectionRows.isEmpty else { continue }
            blocks.append(.section(title))
            blocks.append(contentsOf: sectionRows)
        }

        if options.includeWeights {
            let entries = weights.filter { inRange($0.measurementDate) }.sorted { $0.measurementDate > $1.measurementDate }
            if !entries.isEmpty {
                blocks.append(.section("Weight"))
                blocks.append(contentsOf: entries.map {
                    .row(title: "\($0.weight.formatted(.number.precision(.fractionLength(0...2)))) \($0.unit)", detail: $0.notes ?? "", date: $0.measurementDate.shortDate)
                })
            }
        }

        if options.includeDocumentReferences {
            let docs = documents.filter { inRange($0.createdAt) }
            if !docs.isEmpty {
                blocks.append(.section("Documents on file"))
                blocks.append(contentsOf: docs.map { .row(title: $0.displayTitle, detail: $0.docType.title, date: $0.createdAt.shortDate) })
            }
        }

        blocks.append(.paragraph("Generated on \(Date.now.shortDate) by Pet Health Memory from owner-confirmed records. Not a veterinary document."))
        return blocks
    }

    private static func paginate(_ blocks: [Block]) -> [[Block]] {
        var pages: [[Block]] = [[]]
        var height: CGFloat = 0
        for block in blocks {
            // Keep a section title together with at least its first row.
            let needed = block.estimatedHeight + (block.isSection ? Block.row(title: "", detail: "", date: "").estimatedHeight : 0)
            if height + needed > usableHeight, !(pages[pages.count - 1].isEmpty) {
                pages.append([])
                height = 0
            }
            pages[pages.count - 1].append(block)
            height += block.estimatedHeight
        }
        return pages
    }
}

private extension PDFReportService.Block {
    var isSection: Bool { if case .section = self { true } else { false } }
}

/// One rendered PDF page. Uses fixed light colours for print.
private struct ReportPageView: View {
    let blocks: [PDFReportService.Block]
    let pageNumber: Int
    let pageCount: Int
    let petName: String

    private let ink = Color(red: 0.12, green: 0.14, blue: 0.13)
    private let muted = Color(red: 0.36, green: 0.40, blue: 0.39)
    private let brand = Color(red: 0.25, green: 0.46, blue: 0.41)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .header(title, subtitle, range):
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(ink)
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(muted)
                        Text(range).font(.system(size: 11, weight: .semibold)).foregroundStyle(brand)
                        Rectangle().fill(brand).frame(height: 2).padding(.top, 8)
                    }
                    .padding(.bottom, 8)
                case let .section(title):
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(brand)
                        .padding(.top, 12)
                case let .row(title, detail, date):
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                            if !detail.isEmpty {
                                Text(detail).font(.system(size: 10)).foregroundStyle(muted).lineLimit(2)
                            }
                        }
                        Spacer()
                        Text(date).font(.system(size: 10)).foregroundStyle(muted)
                    }
                    .padding(.vertical, 3)
                    .overlay(alignment: .bottom) { Rectangle().fill(muted.opacity(0.2)).frame(height: 0.5) }
                case let .paragraph(text):
                    Text(text).font(.system(size: 11)).foregroundStyle(ink)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text(petName).font(.system(size: 9)).foregroundStyle(muted)
                Spacer()
                Text("Page \(pageNumber) of \(pageCount)").font(.system(size: 9)).foregroundStyle(muted)
            }
        }
        .padding(40)
        .frame(width: PDFReportService.pageSize.width, height: PDFReportService.pageSize.height, alignment: .topLeading)
        .background(Color.white)
    }
}
