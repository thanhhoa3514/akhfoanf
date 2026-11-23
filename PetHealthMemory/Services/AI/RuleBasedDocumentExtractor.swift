import Foundation

/// Deterministic, 100% on-device structured extractor for veterinary OCR text.
/// Runs on every iOS 17+ / macOS 14+ device and on macOS CI without requiring Apple Intelligence.
/// Strictly follows PRD F04: never invents missing fields, flags ambiguous dates, and preserves
/// exact medication instructions alongside `sourceText`.
enum RuleBasedDocumentExtractor {
    private static let vaccineKeywords: [(pattern: String, canonical: String)] = [
        (#"\brabies\b|\btollwut\b|\brage\b"#, "Rabies"),
        (#"\bdhppi\b"#, "DHPPi"),
        (#"\bdhpp\b|\bdhlpp\b|\bdapp\b"#, "DHPP"),
        (#"\bfvrcp\b"#, "FVRCP"),
        (#"\bbordetella\b"#, "Bordetella"),
        (#"\bleptospirosis\b|\blepto\b"#, "Leptospirosis"),
        (#"\bfelv\b"#, "FeLV"),
        (#"\blyme\b"#, "Lyme"),
    ]

    static func extract(from ocrText: String) -> [ExtractedFieldDraft] {
        let trimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let pages = trimmed.components(separatedBy: "\n\n")
        var drafts: [ExtractedFieldDraft] = []

        if let docType = detectDocumentType(in: trimmed) {
            drafts.append(
                ExtractedFieldDraft(
                    fieldName: ExtractionFieldKey.documentType.rawValue,
                    fieldValue: docType.rawValue,
                    confidence: "high"
                )
            )
        }

        if let clinic = extractClinic(from: pages) {
            drafts.append(clinic)
        }

        if let visitDate = extractPrimaryDate(from: pages) {
            drafts.append(visitDate)
        }

        if let weight = extractWeight(from: pages) {
            drafts.append(weight)
        }

        drafts.append(contentsOf: extractVaccinations(from: pages))
        drafts.append(contentsOf: extractMedications(from: pages))

        return drafts
    }

    // MARK: - Document Type

    private static func detectDocumentType(in text: String) -> DocumentType? {
        let lower = text.lowercased()
        if lower.contains("vaccination certificate") || lower.contains("impfpass") || lower.contains("certificat de vaccination") {
            return .vaccinationCertificate
        }
        if lower.contains("prescription") || lower.contains("rx:") {
            return .prescription
        }
        if lower.contains("laboratory") || lower.contains("lab result") || lower.contains("blood panel") || lower.contains("cbc") {
            return .laboratoryResult
        }
        if lower.contains("invoice") || lower.contains("receipt") || lower.contains("total due") {
            return .invoice
        }
        if lower.contains("consultation") || lower.contains("visit report") || lower.contains("check-up") || lower.contains("exam") {
            return .veterinaryVisitReport
        }
        if lower.contains("vaccine") || lower.contains("rabies") || lower.contains("dhpp") {
            return .vaccinationCertificate
        }
        return nil
    }

    // MARK: - Clinic

    private static func extractClinic(from pages: [String]) -> ExtractedFieldDraft? {
        let clinicPattern = #"(?i)\b(animal\s+clinic|vet(?:erinary)?\s+clinic|animal\s+hospital|vet(?:erinary)?\s+hospital|clinique\s+v[eé]t[eé]rinaire|tierarztpraxis|pet\s+clinic)\b"#
        for (pageIndex, page) in pages.enumerated() {
            for rawLine in page.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, line.count <= 100 else { continue }
                if firstMatch(clinicPattern, in: line) != nil {
                    let display = line == line.uppercased() ? line.localizedCapitalized : line
                    return ExtractedFieldDraft(
                        fieldName: ExtractionFieldKey.clinic.rawValue,
                        fieldValue: display,
                        sourceText: line,
                        pageNumber: pageIndex + 1,
                        confidence: "high"
                    )
                }
            }
        }
        return nil
    }

    // MARK: - Dates

    private struct ParsedDate {
        let normalizedISO: String?
        let isAmbiguous: Bool
        let rawToken: String
    }

    private static func extractPrimaryDate(from pages: [String]) -> ExtractedFieldDraft? {
        for (pageIndex, page) in pages.enumerated() {
            for rawLine in page.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = line.lowercased()
                if lower.contains("next due") || lower.contains("due ") || lower.contains("expires") {
                    continue
                }
                if let parsed = parseDate(in: line) {
                    return ExtractedFieldDraft(
                        fieldName: ExtractionFieldKey.visitDate.rawValue,
                        fieldValue: parsed.normalizedISO,
                        sourceText: line,
                        pageNumber: pageIndex + 1,
                        confidence: parsed.isAmbiguous ? "low" : "high",
                        isAmbiguous: parsed.isAmbiguous
                    )
                }
            }
        }
        return nil
    }

    /// Normalizes unambiguous dates to YYYY-MM-DD and flags ambiguous DD/MM vs MM/DD dates.
    private static func parseDate(in line: String) -> ParsedDate? {
        // 1. ISO: YYYY-MM-DD
        if let match = firstMatch(#"\b(20\d{2})[-/](0?[1-9]|1[0-2])[-/](0?[1-9]|[12]\d|3[01])\b"#, in: line),
           match.groups.count == 3 {
            let y = Int(match.groups[0])!
            let m = Int(match.groups[1])!
            let d = Int(match.groups[2])!
            return ParsedDate(
                normalizedISO: String(format: "%04d-%02d-%02d", y, m, d),
                isAmbiguous: false,
                rawToken: match.full
            )
        }

        // 2. Slash or dot numeric: AA/BB/YYYY or AA/BB/YY
        if let match = firstMatch(#"\b(\d{1,2})[/.](\d{1,2})[/.](\d{2,4})\b"#, in: line),
           match.groups.count == 3,
           let a = Int(match.groups[0]),
           let b = Int(match.groups[1]),
           let rawYear = Int(match.groups[2]) {
            let year = rawYear < 100 ? (2000 + rawYear) : rawYear
            guard (1990...2100).contains(year), a >= 1, b >= 1 else { return nil }

            if a > 12 && b <= 12 {
                // Unambiguously DD/MM/YYYY
                return ParsedDate(
                    normalizedISO: String(format: "%04d-%02d-%02d", year, b, a),
                    isAmbiguous: false,
                    rawToken: match.full
                )
            } else if b > 12 && a <= 12 {
                // Unambiguously MM/DD/YYYY
                return ParsedDate(
                    normalizedISO: String(format: "%04d-%02d-%02d", year, a, b),
                    isAmbiguous: false,
                    rawToken: match.full
                )
            } else if a <= 12 && b <= 12 {
                if a == b {
                    return ParsedDate(
                        normalizedISO: String(format: "%04d-%02d-%02d", year, a, b),
                        isAmbiguous: false,
                        rawToken: match.full
                    )
                }
                // Ambiguous DD/MM vs MM/DD: flag for human review, leave value nil (PRD F04).
                return ParsedDate(normalizedISO: nil, isAmbiguous: true, rawToken: match.full)
            }
        }
        return nil
    }

    // MARK: - Weight

    private static func extractWeight(from pages: [String]) -> ExtractedFieldDraft? {
        let pattern = #"(?i)\b(?:wt|weight|gewicht|poids)?[:\s]*(\d{1,3}(?:[.,]\d{1,2})?)\s*(kg|lbs?|pounds?)\b"#
        for (pageIndex, page) in pages.enumerated() {
            for rawLine in page.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if let match = firstMatch(pattern, in: line), match.groups.count == 2 {
                    let number = match.groups[0].replacingOccurrences(of: ",", with: ".")
                    let unitRaw = match.groups[1].lowercased()
                    let unit = unitRaw.hasPrefix("kg") ? "kg" : "lb"
                    return ExtractedFieldDraft(
                        fieldName: ExtractionFieldKey.weight.rawValue,
                        fieldValue: "\(number) \(unit)",
                        sourceText: line,
                        pageNumber: pageIndex + 1,
                        confidence: "high"
                    )
                }
            }
        }
        return nil
    }

    // MARK: - Vaccinations

    private static func extractVaccinations(from pages: [String]) -> [ExtractedFieldDraft] {
        var results: [ExtractedFieldDraft] = []
        var groupIndex = 0
        var seenVaccines = Set<String>()

        for (pageIndex, page) in pages.enumerated() {
            let lines = page.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for (lineIndex, line) in lines.enumerated() {
                for (pattern, canonical) in vaccineKeywords {
                    guard !seenVaccines.contains(canonical),
                          firstMatch("(?i)\(pattern)", in: line) != nil else { continue }
                    seenVaccines.insert(canonical)
                    let groupKey = "vaccination-\(groupIndex)"
                    groupIndex += 1

                    results.append(
                        ExtractedFieldDraft(
                            fieldName: ExtractionFieldKey.vaccineName.rawValue,
                            fieldValue: canonical,
                            sourceText: line,
                            pageNumber: pageIndex + 1,
                            confidence: "high",
                            groupKey: groupKey
                        )
                    )

                    if let given = parseDate(in: line), !line.lowercased().contains("next due") {
                        results.append(
                            ExtractedFieldDraft(
                                fieldName: ExtractionFieldKey.vaccineDate.rawValue,
                                fieldValue: given.normalizedISO,
                                sourceText: line,
                                pageNumber: pageIndex + 1,
                                confidence: given.isAmbiguous ? "low" : "high",
                                isAmbiguous: given.isAmbiguous,
                                groupKey: groupKey
                            )
                        )
                    }

                    // Check same line or following line for explicit "next due" date
                    let candidateDueLines = [line] + (lineIndex + 1 < lines.count ? [lines[lineIndex + 1]] : [])
                    for candidate in candidateDueLines where candidate.lowercased().contains("next due") {
                        if let due = parseDate(in: candidate) {
                            results.append(
                                ExtractedFieldDraft(
                                    fieldName: ExtractionFieldKey.nextDueDate.rawValue,
                                    fieldValue: due.normalizedISO,
                                    sourceText: candidate,
                                    pageNumber: pageIndex + 1,
                                    confidence: due.isAmbiguous ? "low" : "high",
                                    isAmbiguous: due.isAmbiguous,
                                    groupKey: groupKey
                                )
                            )
                        }
                        break
                    }
                }
            }
        }
        return results
    }

    // MARK: - Medications

    private static func extractMedications(from pages: [String]) -> [ExtractedFieldDraft] {
        var results: [ExtractedFieldDraft] = []
        var groupIndex = 0
        let medLinePattern = #"(?i)(?:^rx\s*:\s*|medication\s*:\s*)([A-Za-z][A-Za-z0-9\-\s]{1,40}?)(?:\s+(\d+(?:\.\d+)?\s*(?:mg|mcg|ml|g)\b[^,\n-]*))?(?:\s*[-–—]\s*(.+))?$"#
        let frequencyPattern = #"(?i)\b(once\s+daily|twice\s+daily|every\s+\d+\s+(?:hours?|days?|weeks?|months?)|q\d+[hdw]|sid|bid|tid|qid)\b"#

        for (pageIndex, page) in pages.enumerated() {
            for rawLine in page.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let match = firstMatch(medLinePattern, in: line),
                      let rawName = match.groups.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !rawName.isEmpty else { continue }

                let groupKey = "medication-\(groupIndex)"
                groupIndex += 1

                results.append(
                    ExtractedFieldDraft(
                        fieldName: ExtractionFieldKey.medicationName.rawValue,
                        fieldValue: rawName,
                        sourceText: line,
                        pageNumber: pageIndex + 1,
                        confidence: "high",
                        groupKey: groupKey
                    )
                )

                if match.groups.count >= 2 {
                    let dosage = match.groups[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !dosage.isEmpty {
                        results.append(
                            ExtractedFieldDraft(
                                fieldName: ExtractionFieldKey.dosageText.rawValue,
                                fieldValue: dosage,
                                sourceText: line,
                                pageNumber: pageIndex + 1,
                                confidence: "high",
                                groupKey: groupKey
                            )
                        )
                    }
                }

                let instructionSource = match.groups.count >= 3 ? match.groups[2] : line
                if let freq = firstMatch(frequencyPattern, in: instructionSource) {
                    let isAbbrev = ["sid", "bid", "tid", "qid"].contains(freq.full.lowercased())
                        || freq.full.lowercased().hasPrefix("q")
                    results.append(
                        ExtractedFieldDraft(
                            fieldName: ExtractionFieldKey.frequencyText.rawValue,
                            fieldValue: instructionSource.trimmingCharacters(in: .whitespacesAndNewlines),
                            sourceText: line,
                            pageNumber: pageIndex + 1,
                            confidence: isAbbrev ? "medium" : "high",
                            isAmbiguous: isAbbrev,
                            groupKey: groupKey
                        )
                    )
                }
            }
        }
        return results
    }

    // MARK: - Regex Helper

    private struct RegexMatch {
        let full: String
        let groups: [String]
    }

    private static func firstMatch(_ pattern: String, in text: String) -> RegexMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let fullRange = Range(match.range, in: text) else { return nil }

        var groups: [String] = []
        for idx in 1..<match.numberOfRanges {
            let groupRange = match.range(at: idx)
            if groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: text) {
                groups.append(String(text[swiftRange]))
            } else {
                groups.append("")
            }
        }
        return RegexMatch(full: String(text[fullRange]), groups: groups)
    }
}
