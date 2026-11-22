import Foundation
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Launch arguments used by the UI test target (`PetHealthMemoryUITests`).
///
/// - `-ui-testing`: in-memory store, no persisted pet selection, no animations.
/// - `-seed-sample-data`: inserts a realistic demo pet with history (only with `-ui-testing`).
/// - `-color-scheme dark|light`: forces the appearance for screenshot runs.
enum LaunchOptions {
    private static let arguments = ProcessInfo.processInfo.arguments

    static let isUITesting = arguments.contains("-ui-testing")
    static let seedSampleData = isUITesting && arguments.contains("-seed-sample-data")

    static var colorScheme: ColorScheme? {
        guard let index = arguments.firstIndex(of: "-color-scheme"),
              arguments.indices.contains(index + 1) else { return nil }
        switch arguments[index + 1] {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    /// Called once from the App initialiser before any view reads state.
    @MainActor
    static func prepare(_ modelContainer: ModelContainer) {
        guard isUITesting else { return }
        UserDefaults.standard.removeObject(forKey: "selectedPetID")
        #if canImport(UIKit)
        UIView.setAnimationsEnabled(false)
        #endif
        if seedSampleData {
            SampleData.insert(into: modelContainer.mainContext)
        }
    }
}

/// Deterministic demo data for screenshots. Dates are relative to now so "due soon" and
/// "overdue" states always render the same way.
enum SampleData {
    @MainActor
    static func insert(into context: ModelContext) {
        let calendar = Calendar.current
        func days(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now)) ?? .now
        }

        let clinic = CareProviderModel(clinicName: "Riverside Animal Clinic", vetName: "Dr. Lan Pham",
                                       phone: "+84 28 3822 1234")
        context.insert(clinic)

        let pet = PetModel(name: "Mochi", species: "Dog", breed: "Shiba Inu",
                           birthDate: calendar.date(byAdding: .year, value: -4, to: .now),
                           sex: "Female", microchipNumber: "900215001234567")
        context.insert(pet)

        let rabies = HealthEventModel(petId: pet.id, type: HealthEventType.vaccination.rawValue,
                                      title: "Rabies", eventDate: days(-340), providerId: clinic.id,
                                      providerName: clinic.clinicName, nextDueDate: days(25))
        let dhpp = HealthEventModel(petId: pet.id, type: HealthEventType.vaccination.rawValue,
                                    title: "DHPP", eventDate: days(-200), providerId: clinic.id,
                                    providerName: clinic.clinicName, nextDueDate: days(165))
        let apoquel = HealthEventModel(petId: pet.id, type: HealthEventType.medication.rawValue,
                                       title: "Apoquel", eventDate: days(-14),
                                       dosageText: "5.4 mg tablet", frequencyText: "Once daily with food",
                                       startDate: days(-14), endDate: days(16),
                                       medicationStatus: MedicationStatus.active.rawValue)
        let visit = HealthEventModel(petId: pet.id, type: HealthEventType.veterinaryVisit.rawValue,
                                     title: "Annual check-up", eventDate: days(-14),
                                     notes: "Mild skin allergy. Recheck in 4 weeks.",
                                     providerId: clinic.id, providerName: clinic.clinicName)
        let allergy = HealthEventModel(petId: pet.id, type: HealthEventType.allergy.rawValue,
                                       title: "Chicken protein", eventDate: days(-400))
        [rabies, dhpp, apoquel, visit, allergy].forEach { context.insert($0) }

        let reminders = [
            ReminderModel(petId: pet.id, healthEventId: rabies.id, title: "Rabies booster",
                          reminderType: ReminderType.vaccination.rawValue, dueDate: days(25)),
            ReminderModel(petId: pet.id, healthEventId: apoquel.id, title: "Apoquel refill",
                          reminderType: ReminderType.medication.rawValue, dueDate: days(-1)),
            ReminderModel(petId: pet.id, title: "Skin recheck",
                          reminderType: ReminderType.veterinaryAppointment.rawValue, dueDate: days(14)),
        ]
        reminders.forEach { context.insert($0) }

        let weights: [(Int, Double)] = [(-180, 9.8), (-120, 10.1), (-60, 10.4), (-14, 10.2)]
        for (offset, kg) in weights {
            context.insert(WeightEntryModel(petId: pet.id, weight: kg, measurementDate: days(offset)))
        }

        try? context.save()
    }
}
