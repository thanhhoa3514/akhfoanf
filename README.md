# Pet Health Memory — iOS App

Offline-first, privacy-first iOS application built with **SwiftUI, MVVM, Repository Pattern, SwiftData, Vision, Foundation Models, UserNotifications, and PDFKit**.

Design spec: [docs/DESIGN.md](docs/DESIGN.md). Design review and revised tokens: [docs/DESIGN_REVIEW.md](docs/DESIGN_REVIEW.md).

## Folder Structure

```text
PetHealthMemory/
├── App/                  # App entry point, DI container, root tab shell
├── DesignSystem/         # Warm Sage & Warm Alabaster tokens (Theme.swift) + shared components
├── Domain/               # Core enums, repository protocols, domain use cases
├── Data/
│   ├── Persistence/      # SwiftData ModelContainer + @Model entities
│   ├── Repositories/     # Concrete SwiftData repository implementations
│   └── Storage/          # App-private FileManager document storage
├── Services/
│   ├── OCR/              # On-device Apple Vision OCR
│   ├── AI/               # Apple Foundation Models extraction + manual fallback
│   ├── Notifications/    # Offline UNUserNotificationCenter scheduler & reconciler
│   └── PDF/              # Offline PDFKit health report exporter
├── Presentation/         # Feature modules (SwiftUI Views + ViewModels)
│   ├── Home/
│   ├── PetProfile/
│   ├── Documents/
│   ├── ExtractionReview/
│   ├── HealthHistory/
│   ├── Reminders/
│   ├── Search/
│   ├── Export/
│   └── Settings/
├── Resources/            # Assets.xcassets, Info.plist, localization
└── Tests/                # XCTest integration suites (PersistenceTests)
```

## Building (iOS + macOS)

The Xcode project is generated from [`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen); the `.xcodeproj` is not checked in.

```bash
brew install xcodegen
xcodegen generate
open PetHealthMemory.xcodeproj
```

`project.yml` already sets:

- One multiplatform target (iPhone, iPad, Mac). Deployment targets **iOS 17.0** / **macOS 14.0** (SwiftData, `@Observable`, `ContentUnavailableView`, `sensoryFeedback`). The zoom navigation transition switches on automatically on iOS 18+.
- Swift **5** language mode, Default Actor Isolation **nonisolated**, Strict Concurrency **Minimal**. Migrate to Swift 6 strict concurrency afterwards; start with `Thumbnailer`, which returns a non-Sendable `NSImage` out of `Task.detached`.
- `NSCameraUsageDescription` (iOS document scanner) and, on macOS, App Sandbox with **User Selected File ▸ Read Only** (Files import and drag & drop).
- Bundle ID `com.pethealthmemory.app`. Change it and pick your signing team in Xcode before running on a device.

The iCloud / CloudKit capability is only needed once sync ships.

**CI:** [`.github/workflows/build.yml`](.github/workflows/build.yml) builds for iOS Simulator and macOS on every push to `main` and every pull request, unsigned. The full log is uploaded as an artifact.

Run the app: first launch opens the pet profile form.

**Trying the review UI before Foundation Models is wired:** in a DEBUG build, open Settings ▸ Developer ▸
*Simulate detail extraction* and import any PDF or photo. The sample data includes ambiguous fields, two vaccines and a medication.

**Design rationale:** see [docs/DESIGN_REVIEW.md](docs/DESIGN_REVIEW.md). The optional sync backend is developed separately (private repository); the app works fully offline without it.

### Screen map

| # | Screen | File |
| :- | :--- | :--- |
| — | Adaptive shell (tabs on iPhone, 3-column split on Mac/iPad), sheets, commands | `App/RootView.swift`, `App/SidebarView.swift`, `App/PetHealthMemoryApp.swift` |
| 1 | Home | `Presentation/Home/HomeView.swift` |
| 2 | Health History | `Presentation/HealthHistory/TimelineView.swift` |
| 3 / 8 | Documents / Document Detail | `Presentation/Documents/DocumentsListView.swift`, `DocumentDetailView.swift` |
| 4 / 12 | Reminders / Reminder form | `Presentation/Reminders/*` |
| 5 / 6 | Pet form / Pet profile | `Presentation/PetProfile/*` |
| 7 | Capture → processing → review flow | `Presentation/Documents/DocumentCaptureFlow.swift`, `DocumentProcessor.swift` |
| 9 | AI Extraction Review | `Presentation/ExtractionReview/*` |
| 10 / 11 | Event detail / form | `Presentation/HealthHistory/HealthEvent*.swift` |
| 13 | Search | `Presentation/Search/SearchView.swift` |
| 14 | PDF export | `Presentation/Export/ExportReportView.swift` + `Services/PDF/PDFReportService.swift` |
| 15 | Settings & data | `Presentation/Settings/SettingsView.swift` |
| 16 | Weight log | `Presentation/HealthHistory/WeightLogView.swift` |

Data access: list screens read SwiftData directly through `@Query`. Multi-step flows (import pipeline, extraction review) use
`@Observable` models. The repository protocols in `Domain/Repositories` are kept as a seam for persistence integration tests and are not yet implemented.

## UI Implementation Handoff Notes

- Use color and spacing tokens from `DesignSystem/Theme.swift` (supports Light & Dark Mode + Dynamic Type).
- Multi-step flow state lives in `@Observable` models inside `Presentation/<Feature>/`. Simple lists use `@Query`.
- Text colours must use the `*Text` tokens (WCAG AA). `status*` tokens are for fills and icons only.
- Never auto-save AI-extracted fields — all extracted fields must pass through `Presentation/ExtractionReview/` and user confirmation before creating `HealthEventModel` records.
- Always preserve original files in `LocalFileStorage` and link records via `sourceDocumentId`.
