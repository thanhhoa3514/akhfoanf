import SwiftUI

/// A List whose `NavigationLink(value: Route)` rows push on iPhone and drive the detail column
/// (with selection highlight + keyboard navigation) on macOS / iPad.
struct RouteList<Content: View>: View {
    @Environment(AppState.self) private var appState
    @Environment(\.isCompactLayout) private var isCompact
    @ViewBuilder let content: () -> Content

    var body: some View {
        @Bindable var appState = appState
        Group {
            if isCompact {
                List { content() }
            } else {
                List(selection: $appState.detailRoute) { content() }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .canvasBackground()
    }
}

extension View {
    /// Navigates to a route from non-list contexts (dashboard cards, buttons).
    func routeButton(_ route: Route, section: AppSection? = nil) -> some View {
        modifier(RouteButtonModifier(route: route, section: section))
    }
}

private struct RouteButtonModifier: ViewModifier {
    let route: Route
    let section: AppSection?
    @Environment(AppState.self) private var appState
    @Environment(\.isCompactLayout) private var isCompact

    func body(content: Content) -> some View {
        Button {
            appState.open(route, in: section, compact: isCompact)
        } label: {
            content.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
