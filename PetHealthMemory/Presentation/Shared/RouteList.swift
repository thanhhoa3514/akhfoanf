import SwiftUI

/// A List whose `NavigationLink(value: Route)` rows push on iPhone and drive the detail column
/// (with selection highlight + keyboard navigation) on macOS / iPad.
struct RouteList<Content: View>: View {
    @Environment(AppState.self) private var appState
    @Environment(\.isCompactLayout) private var isCompact
    /// Wide layouts select this when nothing is selected (Mail-style), so the detail column is
    /// never an empty "Select a …" placeholder while there is something to show.
    var firstRoute: Route? = nil
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
        .onChange(of: appState.detailRoute, initial: true) { _, _ in selectFirstIfNeeded() }
        .onChange(of: firstRoute) { _, _ in selectFirstIfNeeded() }
    }

    private func selectFirstIfNeeded() {
        guard !isCompact, appState.detailRoute == nil, let firstRoute else { return }
        appState.detailRoute = firstRoute
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
