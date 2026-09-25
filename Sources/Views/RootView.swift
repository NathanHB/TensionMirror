import SwiftUI

struct RootView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
                .environmentObject(appState.restTimer)

            TabView {
                BrowseView()
                    .environmentObject(appState)
                    .environmentObject(appState.bluetooth)
                    .tabItem { Label("Browse", systemImage: "square.grid.2x2") }

                PlusOneGameView()
                    .environmentObject(appState)
                    .environmentObject(appState.bluetooth)
                    .tabItem { Label("+1 Game", systemImage: "hand.point.up.left") }

                HistoryView()
                    .environmentObject(appState)
                    .environmentObject(appState.bluetooth)
                    .tabItem { Label("History", systemImage: "calendar") }
            }
        }
    }
}
