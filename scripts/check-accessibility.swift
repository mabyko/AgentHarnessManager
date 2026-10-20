import AppKit
import ApplicationServices
import SkillCore
import SwiftUI

@main struct AccessibilityCheck {
    @MainActor static func main() {
        do { try run() }
        catch { fputs("FAIL: " + error.localizedDescription + "\n", stderr); exit(1) }
    }

    @MainActor static func run() throws {
        guard CommandLine.arguments.count >= 2 && CommandLine.arguments[1].hasPrefix("ahm.settings.check.") else { exit(64) }
        let suite = CommandLine.arguments[1]
        if CommandLine.arguments.last == "--fixture" { try fixture(suite); return }
        guard AXIsProcessTrusted() else {
            fputs("Accessibility access is unavailable for the test runner; no permission prompt was requested.\n", stderr)
            exit(77)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [suite, "--fixture"]
        try process.run()
        defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        func check(_ condition: Bool, _ message: String = "Accessibility check failed") {
            if !condition {
                if process.isRunning { process.terminate() }; process.waitUntilExit()
                fputs("FAIL: " + message + "\n", stderr); exit(1)
            }
        }
        let app = AXUIElementCreateApplication(process.processIdentifier)
        func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            var result: CFTypeRef?
            AXUIElementCopyAttributeValue(element, key as CFString, &result)
            return result
        }
        func string(_ element: AXUIElement, _ key: String) -> String { value(element, key) as? String ?? "" }
        func elements(_ root: AXUIElement, depth: Int = 0) -> [AXUIElement] {
            guard depth < 24 else { return [] }
            return [root] + (value(root, "AXChildren") as? [AXUIElement] ?? []).flatMap { elements($0, depth: depth + 1) }
        }
        func wait(_ message: String, _ predicate: () -> Bool) {
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline { if predicate() { return }; Thread.sleep(forTimeInterval: 0.05) }
            check(false, message)
        }
        func find(_ id: String) -> AXUIElement {
            var result: AXUIElement?
            wait("Missing accessibility identifier: " + id) {
                result = elements(app).first { string($0, "AXIdentifier") == id }; return result != nil
            }
            return result!
        }
        func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
                event.flags = flags; event.postToPid(process.processIdentifier)
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        func focus(_ element: AXUIElement) {
            check(AXUIElementSetAttributeValue(element, "AXFocused" as CFString, kCFBooleanTrue) == .success)
            Thread.sleep(forTimeInterval: 0.1)
        }
        func focusedID() -> String {
            guard let element = value(app, "AXFocusedUIElement") else { return "" }
            return string(element as! AXUIElement, "AXIdentifier")
        }
        func selectPage(_ id: String) {
            let button = find("settings.page." + id)
            focus(button)
            check(AXUIElementPerformAction(button, "AXPress" as CFString) == .success)
            Thread.sleep(forTimeInterval: 0.2)
        }
        wait("Fixture windows did not open") { elements(app).contains { string($0, "AXIdentifier") == "settings.page.general" } }
        NSRunningApplication(processIdentifier: process.processIdentifier)!.activate(options: [.activateIgnoringOtherApps])
        AXUIElementPerformAction(find("a11y.settings"), "AXRaise" as CFString)
        Thread.sleep(forTimeInterval: 0.3)

        selectPage("general")
        key(48)
        check(focusedID() == "settings.page.connections", "Tab must reach the next settings category; focused=" + focusedID())
        key(48, flags: .maskShift)
        check(focusedID() == "settings.page.general", "Shift-Tab must return to the previous category")
        key(48); key(49)
        let names = AgentConnectionTarget.allCases
        for target in names {
            let row = find("agent.connection." + target.rawValue)
            let children = elements(row)
            check(children.contains { string($0, "AXDescription") == target.name && string($0, "AXValue") == "등록 상태 미확인" })
            for action in ["install", "remove"] {
                let button = find("agent.connection." + action + "." + target.rawValue)
                check(string(button, "AXRole") == "AXButton" && string(button, "AXDescription").contains(target.name))
                var actions: CFArray?
                check(AXUIElementCopyActionNames(button, &actions) == .success && (actions as? [String] ?? []).contains("AXPress"))
            }
            check(!children.contains { string($0, "AXRole") == "AXImage" }, "Decorative agent icons must not be announced")
        }
        selectPage("paths")
        func selectAgent(_ name: String) {
            check(AXUIElementPerformAction(find("settings.pathAgent"), "AXPress" as CFString) == .success)
            var item: AXUIElement?
            wait("Accessible agent menu item missing: " + name) {
                item = elements(app).first { string($0, "AXRole") == "AXMenuItem" && string($0, "AXTitle") == name }
                return item != nil
            }
            check(AXUIElementPerformAction(item!, "AXPress" as CFString) == .success)
            wait("Accessible agent selection failed: " + name) { string(find("settings.pathAgent"), "AXValue").contains(name) }
        }
        selectAgent("Claude Code")
        selectAgent("OpenCode")
        let finderLabels = elements(app).filter { string($0, "AXRole") == "AXButton" }
            .map { string($0, "AXDescription") }.filter { $0.contains("Finder에서 보기") }
        check(finderLabels.count == 2 && Set(finderLabels).count == 2, "Finder buttons must identify their distinct paths")

        let library = find("a11y.library")
        check(AXUIElementPerformAction(library, "AXRaise" as CFString) == .success)
        let newGroup = elements(library).first { string($0, "AXRole") == "AXButton" && string($0, "AXDescription") == "새 그룹" }!
        check(elements(library).contains { string($0, "AXRole") == "AXButton" && string($0, "AXDescription") == "Codex, 1개" })
        focus(newGroup); key(49)
        wait("Keyboard action did not open the group sheet") { elements(app).contains { string($0, "AXRole") == "AXSheet" } }
        wait("Group name field did not receive focus") {
            guard let element = value(app, "AXFocusedUIElement") else { return false }
            return string(element as! AXUIElement, "AXRole") == "AXTextField"
        }
        key(53)
        wait("Escape did not dismiss the group sheet") { !elements(app).contains { string($0, "AXRole") == "AXSheet" } }
        print("PASS: native AX agent names/states and press actions, unique action/path labels, hidden decorative icons, sidebar Tab/Shift-Tab/Space, accessible picker selection, and group-sheet focus/Escape; isolated fixture only")
        print("NOT CHECKED: spoken VoiceOver output and global all-controls Tab traversal; system settings unchanged")
    }

    @MainActor static func fixture(_ suite: String) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let home = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("home")
        for path in [".agents/skills/keyboard-demo", ".claude/skills/voiceover-demo"] {
            let folder = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "---\nname: \(folder.lastPathComponent)\ndescription: Synthetic accessibility fixture\n---\nRead only test content.\n".write(to: folder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        let defaults = UserDefaults(suiteName: suite)!
        let store = AppStore(defaults: defaults, home: home)
        func window<V: View>(_ root: V, id: String, size: NSSize) -> NSWindow {
            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.setAccessibilityIdentifier(id)
            window.contentView = NSHostingView(rootView: root.environment(store))
            window.makeKeyAndOrderFront(nil)
            return window
        }
        let library = window(ContentView(), id: "a11y.library", size: NSSize(width: 1280, height: 800))
        let settings = window(SettingsView(), id: "a11y.settings", size: NSSize(width: 900, height: 900))
        app.activate(ignoringOtherApps: true)
        Task { @MainActor in await store.rescan() }
        withExtendedLifetime((library, settings)) { app.run() }
    }
}
