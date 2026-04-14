import SwiftUI

@main
struct ImageProcessorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .commands {
            // Remove "New Window" from File menu — single-window tool
            CommandGroup(replacing: .newItem) { }
        }
    }
}
