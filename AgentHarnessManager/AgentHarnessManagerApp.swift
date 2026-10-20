import SwiftUI

@main
struct AgentHarnessManagerApp: App {
    @State private var store = AppStore()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        Window("Agent Harness Manager", id: "workbench") {
            ContentView()
                .environment(store)
                .preferredColorScheme(colorScheme)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 800)
        .defaultLaunchBehavior(.presented)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("새로고침") {
                    Task { await store.rescan() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isScanning)
            }
        }

        Settings {
            SettingsView()
                .environment(store)
            .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 900, height: 680)
        .windowResizability(.contentMinSize)
    }

    private var colorScheme: ColorScheme? {
        return appearance == "light" ? .light : appearance == "dark" ? .dark : nil
    }
}
