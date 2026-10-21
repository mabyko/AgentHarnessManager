import SwiftUI

@main
struct AgentHarnessManagerApp: App {
    @NSApplicationDelegateAdaptor(InstructionAppDelegate.self) private var appDelegate
    @State private var store = AppStore()
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        Window("Agent Harness Manager", id: "workbench") {
            ContentView()
                .onAppear { appDelegate.instructions = store.instructions; appDelegate.store = store }
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
                    Task {
                        if store.page == .instructions { await store.instructions.refresh(); await store.instructions.loadBackups() }
                        else { await store.rescan() }
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isScanning || store.instructions.busy)
                Button("지침 변경 검토…") { Task { await store.instructions.prepareSave() } }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(store.page != .instructions || !store.instructions.canSave)
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
