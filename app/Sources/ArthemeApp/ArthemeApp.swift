import ArthemeKit
import SwiftUI

@main
struct ArthemeApp: App {
    @StateObject private var store = ThemeStore()

    var body: some Scene {
        Window("Artheme", id: "themes") {
            ContentView().environmentObject(store)
        }
        .defaultSize(width: 760, height: 560)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Next Theme") { store.next() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
            }
        }

        // The menu bar item is the point of the app: switching without opening
        // anything. The window is for browsing.
        MenuBarExtra("Artheme", systemImage: "paintpalette") {
            MenuContent().environmentObject(store)
        }
    }
}

private struct MenuContent: View {
    @EnvironmentObject var store: ThemeStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(store.themes) { theme in
            Button { store.apply(theme) } label: {
                Text(theme.slug == store.currentSlug ? "✓ \(theme.displayName)" : theme.displayName)
            }
        }
        Divider()
        Button("Next Theme") { store.next() }
            .keyboardShortcut("n", modifiers: [.command, .option])
        Button("Browse Themes…") {
            openWindow(id: "themes")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit Artheme") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
