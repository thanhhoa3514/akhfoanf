import SwiftData
import SwiftUI

@main
struct PetHealthMemoryApp: App {
    private let modelContainer: ModelContainer
    @State private var container = AppContainer()
    @State private var appState = AppState()

    init() {
        let modelContainer = ModelContainerFactory.makeContainer(inMemory: LaunchOptions.isUITesting)
        LaunchOptions.prepare(modelContainer)
        self.modelContainer = modelContainer
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .environment(appState)
                .tint(AppTheme.Colors.brandPrimary)
                .preferredColorScheme(LaunchOptions.colorScheme)
        }
        .modelContainer(modelContainer)
        .commands { AppCommands(appState: appState) }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        #endif

        #if os(macOS)
        Settings {
            SettingsView(showsDoneButton: false)
                .environment(container)
                .environment(appState)
                .frame(width: 520, height: 560)
                .preferredColorScheme(LaunchOptions.colorScheme)
        }
        .modelContainer(modelContainer)
        #endif
    }
}

/// Keyboard shortcuts (DESIGN.md — macOS enhancements). Also surface on iPad hardware keyboards.
struct AppCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Health Event") { appState.sheet = .newEvent(type: nil) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(appState.selectedPetID == nil)
            Button("Import Document…") { appState.sheet = .capture(source: .files) }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(appState.selectedPetID == nil)
            Divider()
            Button("New Reminder") { appState.sheet = .newReminder(ReminderDraft()) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(appState.selectedPetID == nil)
            Button("New Pet…") { appState.sheet = .newPet }
        }
        CommandMenu("Records") {
            Button("Search") {
                appState.section = .search
                appState.isSearchPresented = true
            }
            .keyboardShortcut("f", modifiers: .command)
            Button("Export PDF Report…") { appState.sheet = .export }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(appState.selectedPetID == nil)
        }
    }
}
