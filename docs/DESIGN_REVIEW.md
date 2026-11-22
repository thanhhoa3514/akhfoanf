# Design Review — UI, UX & Motion (DESIGN.md draft v1)

**Reviewed:** [DESIGN.md](./DESIGN.md), plus the product requirements (PRD) and roadmap.
**Implemented in:** `app/PetHealthMemory/` (SwiftUI, iOS 17+ / macOS 14+)
**Date:** 2026-11-22

---

## 1. Verdict

The draft has the right direction. The calm sage and alabaster tone, offline-first approach, human-in-the-loop AI and source traceability all fit the product. The core weaknesses are:

1. **Accessibility.** The light palette fails WCAG AA for text in almost every status colour.
2. **The review workflow is underspecified.** Grouping, how flags get resolved, partial save, and "come back later" are all undefined, and that workflow *is* the product.
3. **Some motion specs are iOS-only or block the user.**

All P0 and P1 items below are fixed in the implementation.

### Keep as is
- No onboarding: first launch goes straight to the pet form. It's implemented as the whole onboarding, under 30 s.
- 4 tabs on iPhone, split view on Mac and iPad.
- Amber = "needs a human". Source badge = provenance.
- Default spring `0.35 / bounce 0.15` and Reduce Motion fallback.
- No splash, no decorative bounce, no blocking modals during capture.

---

## 2. Visual / UI findings

### P0-1 Light-mode contrast fails WCAG AA (4.5:1 for text)

Measured against `bgSurface #FFFFFF` and `bgCanvas #F8F7F4`:

| Token (light) | On surface | On canvas | Verdict |
| :--- | :---: | :---: | :--- |
| `brandPrimary #4E8C7D` (and white label on it) | 3.91 | 3.65 | ❌ text, ❌ button label |
| `statusWarning #D99B26` | 2.42 | 2.26 | ❌ unreadable as text |
| `statusDanger #D65A5A` | 3.84 | 3.58 | ❌ |
| `statusSuccess #3D9970` | 3.51 | 3.27 | ❌ |
| `statusSource #5A84A2` | 3.99 | 3.73 | ❌ |
| `brandAccent #E09A6C` | 2.33 | 2.18 | ❌ (icons/fills only) |
| `textSecondary #64706C` | 5.15 | 4.81 | ✅ (tight) |
| Dark mode, all tokens | ≥ 5.5 | ≥ 6.1 | ✅ |

**Fix (implemented in `DesignSystem/Theme.swift`).** Keep the hues as fills. Add text-safe variants, and deepen the primary slightly.

| Token | Light | Contrast (canvas) | Dark |
| :--- | :--- | :---: | :--- |
| `brandPrimary` (fill + CTA) | **`#3F7568`** (was #4E8C7D) | 4.96, white-on 5.31 | `#6DB3A2` |
| `onBrandPrimary` (new) | `#FFFFFF` | — | `#0F1A17` (dark label on light-sage button) |
| `brandText` (new) | `#3F7568` | 4.96 | `#6DB3A2` |
| `warningText` (new) | `#8A5F0C` | 5.27 | `#E6B34B` |
| `dangerText` (new) | `#B04545` | 5.18 | `#E57373` |
| `successText` (new) | `#2E7D5B` | 4.67 | `#52B788` |
| `sourceText` (new) | `#466C8C` | 5.18 | `#7AA6C4` |
| `textSecondary` | `#5C6763` (was #64706C) | 5.48 | `#9AA6A2` |

The rule, now written into the `Theme.swift` header: `status*` / `brand*` are for fills, icons and strokes; `*Text` are the only colours allowed for text.

### P0-2 Amber means two things, and colour carries the meaning alone

DESIGN.md uses Soft Amber for both "AI uncertain" and "upcoming due date". In the review screen and on Home these sit side by side, so users can't tell them apart. And because colour is the only signal, colour-blind users and grayscale printing lose the information (WCAG 1.4.1).

**Fix (`Components.swift`):**
- **AI uncertain:** `NeedsCheckBadge`, which combines a `questionmark.circle.fill` icon, a **"Check"** label, a **dashed amber stroke** and a 10 % amber fill. It's resolved explicitly with **Looks right** or **Leave empty**.
- **Due soon:** `DueBadge`, which uses a `clock` icon, a relative label ("In 3 days") and amber *text only*, with no stroke.
- **Overdue:** `exclamationmark.circle.fill` with danger text.

### P1-1 No home for "imported but not reviewed yet"

The draft assumes users finish review right after capture. In a vet clinic they won't, because they'll be interrupted. Their extraction would then be lost, or it would sit in limbo.

**Fix:**
- Review has a **Later** button. The document keeps status `extracted` or `ocrCompleted`.
- Those documents appear in a **"Needs your attention"** section at the top of Documents and in the Home **Needs attention** card.
- On macOS/iPad they also show as a **sidebar badge count**.
- Drag-and-drop batch imports land in the same queue rather than opening one modal per file.

### P1-2 Extraction review rules were undefined

PRD F05 asks for edit, add, delete, partial save and confirm, but DESIGN.md doesn't define how these combine. These are the rules that were implemented (`ExtractionReviewModel`):

- **Grouping.** Fields are grouped into **records** (Visit, Vaccination, Medication, Diagnosis, Lab, Weight) using `groupKey`. A certificate with two vaccines therefore produces two cards.
- **Per-record include toggle.** This is how partial saves work.
- **When a record can be saved:** it has its title field and a date (its own date or the visit date), and it has no unresolved **Check** fields.
- **Save button.** It states the outcome, e.g. "Save 3 records" or "1 record needs attention". It is never just "Confirm".
- **Visit record.** Defaults **off** for vaccination certificates to avoid timeline clutter. It defaults **on** for visit reports and invoices.
- **Dates.** Only ISO-normalised dates become date pickers. Ambiguous raw dates such as `11/12/27` stay as **"unclear format"** with the source quote. The app never guesses between Nov 12 and Dec 11 (PRD F04).
- **Medication instructions** show **"Exactly as written"** and use monospaced text.
- **Pet-name mismatch.** If the document says "Max" but the selected pet is Bella, an inline amber warning appears.
- **Source quotes** on each field are tappable. They open the **Recognized text** pane with the snippet highlighted: a sheet on iPhone, the left pane on Mac.

### P1-3 Home IA is overloaded and doesn't support appointment prep

The IA diagram sends 6 destinations from Home: Pet profile, Search, Export, Settings, Capture and Profile. It also has no screen for *appointment preparation*, which is one of the PRD's six proof points.

**Fix. Home hierarchy is: who → do → attention → prepare → recent.**
1. Pet header, which is also the pet switcher menu. The avatar opens the profile. Search and settings are toolbar icons.
2. **Add a vet document** card with Scan, Photos and Files, so capture is one tap away.
3. **Needs attention**: documents to review, failed OCR, and reminders overdue or due within 7 days.
4. **Ready for the vet**: active medications, latest vaccination per vaccine with next due date, and allergies. It includes **Export PDF**. This is the MVP version of appointment prep.
5. **Recent history**: the last 3 records.

### P1-4 macOS mapping was vague ("sidebar → list → inspector")

**Fix (`RootView.swift`).**
- **Sidebar:** pets (switcher), the sections (Home, History, Documents, Reminders, Search) with badges, and a pinned **Import Document** button.
- **Content column:** the section's list.
- **Detail column:** the selected record or document.
- For Home, the content column is the dashboard and the detail column defaults to the **Pet Profile**.
- **Review:** the original or recognized text sits on the left and the fields on the right.
- **Shortcuts:**
  - ⌘N new record
  - ⌘I import
  - ⌘F search
  - ⌘E export
  - ⇧⌘R new reminder (added)
  - ⏎ saves the review (default action)

### P2 items

| # | Finding | Fix |
| :- | :--- | :--- |
| P2-1 | DESIGN.md says "15 MVP screens" but numbers 1–16. | 16 screens, with #16 Weight optional. Update the heading. |
| P2-2 | Destructive dialogs don't say what is lost. | Pet delete lists counts ("12 records, 5 documents…"). Document delete says linked records are kept but unlinked. Clearing all data needs two confirmations. |
| P2-3 | No "not medical advice" placement. | `MedicalDisclaimer` footer on Home, Event Detail, Review and Settings. |
| P2-4 | Custom canvas colours could fight iOS 26 Liquid Glass or macOS toolbars. | `canvasBackground()` paints only behind content and never tints the system bars or tab bar. |
| P2-5 | Typography had only "SF Pro + Dynamic Type". | Mapping: `largeTitle` first-run, `title2` headers, `headline` card titles, `subheadline` metadata, `caption` badges. No fixed sizes in app UI; the PDF uses fixed sizes. |
| P2-6 | The sync indicator "in Settings/Home" adds noise for the default local-only user. | Home shows sync status **only when sync is on**. Settings always shows it. |
| P2-7 | First-run Home was a dead end once a pet existed. | Three-step "How it works" card plus "Or add a record by hand". |
| P2-8 | Notification permission had no denied state. | Reminders shows a banner, "Notifications are off — Turn on in Settings". The form says the reminder is saved locally anyway. |

---

## 3. Motion findings

| # | Draft spec | Problem | Revised spec (implemented) |
| :- | :--- | :--- | :--- |
| M1 | `.navigationTransition(.zoom)` from thumbnails and source badges | Needs **iOS 18+** and doesn't exist on **macOS**. It is also a strong motion. | `zoomSource` / `zoomDestination` modifiers (`Platform.swift`): zoom on iOS 18+, a plain push elsewhere, and **off under Reduce Motion**. Source IDs are `Route.document(id)`, so they're unique per screen. |
| M2 | "Confirmed cards collapse smoothly … **before** navigating to Timeline" | Animation sits on the critical path. The app also navigated away automatically, which skipped the PRD's "Optional: add reminder" step. | **Save first, synchronously**, then cross-fade to a **Saved** state: checkmark `symbolEffect(.bounce)`, list of created records, reminder suggestions for **due dates stated on the document**, and View timeline / Done buttons. Leaving is user-driven. |
| M3 | Success haptic as the confirmation signal | `sensoryFeedback` does nothing on most Macs and on iPhones with haptics disabled. | Haptics are an addition only. Every state change has a visible state: checkmark, strikethrough, pill change. |
| M4 | Shimmer/scanline and step text "Reading → Extracting → Ready" | OCR often takes < 300 ms, so swapping one label flickers. Shimmer also ignored Reduce Motion. | **Checklist** of steps with ticks, so fast steps still read as completed. Stage changes are announced to VoiceOver. No artificial delay. The scanline is a static tint under Reduce Motion. |
| M5 | `matchedGeometryEffect` sliding pill for the **pet switcher** and filters | A sliding pill doesn't scale past about 3 pets and duplicates a system pattern. | Pet switcher is a native `Menu` with a 0.2 s content crossfade (`.id(petID)`). The sliding pill is kept for **timeline filters** only. |
| M6 | Not specified | List insert/remove, counters and toggles snapped. | Records and fields: insert = opacity + move-from-bottom, remove = opacity + scale 0.92. Counts use `.contentTransition(.numericText())`. Checkmarks use `.symbolEffect(.replace)`. Drop target is a dashed sage outline. |
| M7 | "Fall back to opacity fade" | No token, so each screen would improvise. | `AppTheme.Motion.animation(_:reduceMotion:)` returns `reduced` (0.15 s ease) whenever Reduce Motion is on. |

### Motion tokens

| Token | Value | Use |
| :--- | :--- | :--- |
| `standard` | `spring(0.35, bounce 0.15)` | Layout changes, filter pill, record add/remove |
| `quick` | `easeInOut(0.2)` | Pet switch crossfade, include toggle, button press |
| `confirm` | `spring(0.3, bounce 0.1)` | Save → Saved, medication active toggle |
| `reduced` | `easeInOut(0.15)` | Replaces all of the above under Reduce Motion |

---

## 4. Screen inventory & states (as implemented)

| # | Screen | File | Empty | Loading | Error | Offline | Destructive confirm |
| :- | :--- | :--- | :-: | :-: | :-: | :-: | :-: |
| 1 | Home | `Home/HomeView.swift` | First-run guide | — | — | n/a (local) | — |
| 2 | Health History | `HealthHistory/TimelineView.swift` | ✅ + per-filter | — | — | n/a | — |
| 3 | Documents | `Documents/DocumentsListView.swift` | ✅ | Processing pill + scanline | Couldn't-read pill | n/a | ✅ |
| 4 | Reminders | `Reminders/RemindersView.swift` | ✅ | — | Notifications-off banner | n/a | swipe delete |
| 5 | Create/Edit Pet | `PetProfile/PetFormView.swift` | — | — | ✅ | — | — |
| 6 | Pet Profile | `PetProfile/PetProfileDetailView.swift` | Weight empty | — | — | — | ✅ with counts |
| 7 | Capture / Import | `Documents/DocumentCaptureFlow.swift` | — | ✅ checklist | ✅ Retry / manual / keep only | — | — |
| 8 | Document Detail | `Documents/DocumentDetailView.swift` | — | ✅ | ✅ Retry | — | ✅ |
| 9 | Extraction Review | `ExtractionReview/*` | Manual mode | — | ✅ save error | — | Discard confirm |
| 10 | Event Detail | `HealthHistory/HealthEventDetailView.swift` | No-source states | — | — | — | ✅ |
| 11 | Create/Edit Event | `HealthHistory/HealthEventFormView.swift` | — | — | — | — | — |
| 12 | Create/Edit Reminder | `Reminders/ReminderFormView.swift` | — | — | Permission denied | — | ✅ |
| 13 | Search | `Search/SearchView.swift` | Prompt + no results | — | — | ✅ offline by design | — |
| 14 | PDF Export | `Export/ExportReportView.swift` | — | ✅ | ✅ | ✅ offline | — |
| 15 | Settings & Data | `Settings/SettingsView.swift` | — | — | ✅ | — | ✅ ×2 |
| 16 | Weight Log | `HealthHistory/WeightLogView.swift` | ✅ | — | — | — | ✅ |

"Offline" is not a separate state for local screens because they never wait on the network. It only becomes relevant once sync ships (Sprint 7). The planned states are `Syncing…` and `Offline — changes saved locally`, shown in Settings and next to the Home header.

---

## 5. Open questions for product

1. **Visit records from certificates:** should they stay off by default (current choice), or be on and merged with the vaccination?
2. **Flag resolution:** should unresolved **Check** fields block saving that record (current choice, safest), or be saved with a warning badge?
3. **Multi-pet documents** (one invoice for two pets): split per pet in review, or out of scope for MVP?
4. **Reminder suggestions:** reminders are offered only for due dates stated on the document. Confirm that this doesn't count as "recommending schedules" (PRD non-goal).
