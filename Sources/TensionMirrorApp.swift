import SwiftUI

@main
struct TensionMirrorApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                #if os(macOS)
                .frame(minWidth: 950, minHeight: 750)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1550, height: 950)
        #endif
    }
}
