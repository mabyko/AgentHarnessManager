import AppKit
import ApplicationServices
import SkillCore
import SwiftUI

@main struct InstructionCheck {
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
        let home = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("home")
        let file = home.appendingPathComponent(".codex/AGENTS.md")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [suite, "--fixture"]
        try process.run()
        defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        func check(_ condition: Bool, _ message: String) {
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
            guard depth < 25 else { return [] }
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
        func press(_ id: String) {
            check(AXUIElementPerformAction(find(id), "AXPress" as CFString) == .success, "Cannot activate " + id)
            Thread.sleep(forTimeInterval: 0.15)
        }
        func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
                event.flags = flags; event.postToPid(process.processIdentifier)
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        _ = find("instructions.agent.codex")
        NSRunningApplication(processIdentifier: process.processIdentifier)?.activate(options: [.activateIgnoringOtherApps])
        for agent in ["cursor", "devin"] {
            press("instructions.agent." + agent)
            check(string(find("instructions.agent." + agent), "AXDescription").contains("미지원"), "Unsupported agent label")
            check(!elements(app).contains { string($0, "AXIdentifier") == "instructions.editor" }, "Unsupported agent must not expose an editor")
        }
        press("instructions.agent.codex")
        let editor = find("instructions.editor")
        let textArea = elements(editor).first { string($0, "AXRole") == "AXTextArea" } ?? editor
        check(AXUIElementSetAttributeValue(textArea, "AXFocused" as CFString, kCFBooleanTrue) == .success, "Focus native editor")
        key(0, flags: .maskCommand)
        let text = Array("# Global instructions\nUse synthetic fixtures.\nUpdated in the native editor.\n".utf16)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
            text.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: text.count, unicodeString: $0.baseAddress!) }
            event.postToPid(process.processIdentifier)
        }
        wait("Editor changes were not observed") { (value(find("instructions.review"), "AXEnabled") as? Bool) == true }
        press("instructions.agent.claudeCode")
        press("instructions.agent.codex")
        check(elements(find("instructions.editor")).contains { string($0, "AXValue").contains("Updated in the native editor.") }, "Switching agents must preserve the draft")
        press("instructions.review")
        _ = find("instructions.apply")
        let original = "# Global instructions\nUse synthetic fixtures.\n"
        check(try String(contentsOf: file, encoding: .utf8) == original, "Review must not write the file")
        press("instructions.cancel")
        press("instructions.review")
        press("instructions.apply")
        wait("Reviewed file was not saved") { (try? String(contentsOf: file, encoding: .utf8))?.contains("Updated in the native editor.") == true }
        wait("Backup menu did not enable") { (value(find("instructions.backups"), "AXEnabled") as? Bool) == true }
        press("instructions.backups")
        var restoreItem: AXUIElement?
        wait("Backup restore item missing") {
            restoreItem = elements(app).first { string($0, "AXRole") == "AXMenuItem" && string($0, "AXTitle").contains("변경 전") }
            return restoreItem != nil
        }
        check(AXUIElementPerformAction(restoreItem!, "AXPress" as CFString) == .success, "Select instruction backup")
        press("instructions.apply")
        wait("Backup was not restored") { (try? String(contentsOf: file, encoding: .utf8)) == original }
        try Data().write(to: home.appendingPathComponent("capture"))
        wait("Instruction screenshots were not captured") { FileManager.default.fileExists(atPath: home.appendingPathComponent("capture.done").path) }
        print("PASS: native instruction editor, unsupported states, draft navigation, review cancellation, save and backup restore; light/dark screenshots in /tmp/ahm-instructions-*.png")
    }

    @MainActor static func fixture(_ suite: String) throws {
        let home = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("home")
        let file = home.appendingPathComponent(".codex/AGENTS.md")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Global instructions\nUse synthetic fixtures.\n".write(to: file, atomically: true, encoding: .utf8)
        let store = AppStore(defaults: UserDefaults(suiteName: suite)!, home: home,
                             installationDetector: AgentInstallationDetector(executableDirectories: [], applicationDirectories: []), instructionEnvironment: [:])
        store.page = .instructions
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let view = NSHostingView(rootView: ContentView().environment(store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = view
        window.center(); window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        Task { @MainActor in
            while !FileManager.default.fileExists(atPath: home.appendingPathComponent("capture").path) { try? await Task.sleep(for: .milliseconds(100)) }
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua), ("compact", NSAppearance.Name.darkAqua)] {
                if name == "compact" { window.setContentSize(NSSize(width: 960, height: 640)) }
                window.appearance = NSAppearance(named: appearance)
                try? await Task.sleep(for: .milliseconds(300))
                view.layoutSubtreeIfNeeded()
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/ahm-instructions-" + name + ".png"))
                }
            }
            try? Data().write(to: home.appendingPathComponent("capture.done"))
        }
        withExtendedLifetime((store, window)) { app.run() }
    }
}
