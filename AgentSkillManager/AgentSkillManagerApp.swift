import SwiftUI

@main
struct AgentSkillManagerApp: App {
    @State private var store = AppStore()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        Window("스킬 작업대", id: "workbench") {
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
    }

    private var colorScheme: ColorScheme? {
        return appearance == "light" ? .light : appearance == "dark" ? .dark : nil
    }
}
