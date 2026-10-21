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
        func press(_ id: String, expecting nextID: String? = nil) {
            let button = find(id)
            wait("Control did not enable: " + id) { (value(button, "AXEnabled") as? Bool) != false }
            let result = AXUIElementPerformAction(button, "AXPress" as CFString)
            if let nextID { _ = find(nextID); return }
            if result != .success {
                var actions: CFArray?
                AXUIElementCopyActionNames(button, &actions)
                print("Action diagnostics:", id, string(button, "AXRole"), string(button, "AXDescription"), actions as? [String] ?? [], result.rawValue)
            }
            check(result == .success, "Cannot activate " + id)
            Thread.sleep(forTimeInterval: 0.15)
        }
        func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
                event.flags = flags; event.postToPid(process.processIdentifier)
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        func selectAgent(_ agent: SkillAgent) {
            press("instructions.agentPicker")
            let title = agent.displayName + (GlobalInstructionService.supportedAgents.contains(agent) ? "" : " (미지원)")
            var item: AXUIElement?
            wait("Missing instruction agent menu item: " + title) {
                item = elements(app).first { string($0, "AXRole") == "AXMenuItem" && string($0, "AXTitle") == title }
                return item != nil
            }
            check(AXUIElementPerformAction(item!, "AXPress" as CFString) == .success, "Select instruction agent")
            wait("Instruction agent selection did not change") { string(find("instructions.agentPicker"), "AXValue").contains(agent.displayName) }
        }
        func enterText(_ value: String) {
            let editor = find("instructions.editor")
            let textArea = elements(editor).first { string($0, "AXRole") == "AXTextArea" } ?? editor
            check(AXUIElementSetAttributeValue(textArea, "AXFocused" as CFString, kCFBooleanTrue) == .success, "Focus native editor")
            key(0, flags: .maskCommand)
            let text = Array(value.utf16)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
                text.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: text.count, unicodeString: $0.baseAddress!) }
                event.postToPid(process.processIdentifier)
            }
        }
        func capture(_ name: String) throws {
            try Data().write(to: home.appendingPathComponent("capture." + name))
            wait("State screenshot was not captured: " + name) { FileManager.default.fileExists(atPath: home.appendingPathComponent("capture." + name + ".done").path) }
        }
        func origin(_ id: String) -> CGPoint {
            var point = CGPoint.zero
            check(AXValueGetValue(value(find(id), "AXPosition") as! AXValue, .cgPoint, &point), "Read layout position: " + id)
            return point
        }
        _ = find("instructions.agentPicker")
        _ = find("sidebar.instructions")
        check(!elements(app).contains { string($0, "AXIdentifier") == "instructions.back" }, "Global instructions must keep app navigation instead of a separate back link")
        NSRunningApplication(processIdentifier: process.processIdentifier)?.activate(options: [.activateIgnoringOtherApps])
        let headerY = origin("workbench.listTitle").y
        let footerY = origin("instructions.counts").y
        for agent in [SkillAgent.cursor, .devin] {
            selectAgent(agent)
            check(string(find("instructions.agentPicker"), "AXValue").contains("미지원"), "Unsupported agent label")
            check(!elements(app).contains { string($0, "AXIdentifier") == "instructions.editor" }, "Unsupported agent must not expose an editor")
            check(abs(origin("workbench.listTitle").y - headerY) < 2, "Unsupported agents must keep the list header at the top")
            check(abs(origin("instructions.counts").y - footerY) < 2, "Unsupported agents must keep the list footer at the bottom")
            try capture("unsupported-" + agent.rawValue)
        }
        selectAgent(.codex)
        check(!elements(app).contains { string($0, "AXIdentifier") == "instructions.undoCreate" }, "An existing default file must not have creation undo")
        enterText("# Global instructions\nUse synthetic fixtures.\nUpdated in the native editor.\n")
        wait("Editor changes were not observed") { (value(find("instructions.review"), "AXEnabled") as? Bool) == true }
        wait("Persistent navigation must indicate unsaved instruction drafts") {
            let row = find("sidebar.instructions")
            return (string(row, "AXTitle") + string(row, "AXDescription")).contains("초안")
        }
        press("instructions.reload")
        key(36)
        check(elements(find("instructions.editor")).contains { string($0, "AXValue").contains("Updated in the native editor.") }, "Return must cancel draft discard")
        selectAgent(.claudeCode)
        selectAgent(.codex)
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

        selectAgent(.grokBuild)
        let createdFile = home.appendingPathComponent(".grok/AGENTS.md")
        _ = find("instructions.beginCreation")
        check(!FileManager.default.fileExists(atPath: createdFile.path), "Selecting a missing candidate must not create it")
        try capture("missing")
        press("instructions.beginCreation", expecting: "instructions.editor")
        check((value(find("instructions.review"), "AXEnabled") as? Bool) == false, "Empty creation must be disabled")
        enterText(" \n\t")
        check((value(find("instructions.review"), "AXEnabled") as? Bool) == false, "Whitespace creation must be disabled")
        enterText("# Synthetic Grok instructions\nReview changes before applying them.\n")
        wait("Nonempty creation did not enable") { (value(find("instructions.review"), "AXEnabled") as? Bool) == true }
        press("instructions.review")
        check(["AXTitle", "AXDescription"].contains { string(find("instructions.apply"), $0) == "파일 만들기" }, "Creation review must name its action")
        check(!FileManager.default.fileExists(atPath: createdFile.path), "Creation preview must not write")
        press("instructions.apply")
        _ = find("instructions.undoCreate")
        press("instructions.undoCreate")
        check(["AXTitle", "AXDescription"].contains { string(find("instructions.apply"), $0) == "새 파일 제거" }, "Creation undo must clearly name removal")
        key(36)
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.05)
            check(FileManager.default.fileExists(atPath: createdFile.path), "Return must not default to removing a file")
        }
        _ = find("instructions.apply")
        try capture("creation-review")
        press("instructions.apply")
        wait("Creation undo did not remove the new file") { !FileManager.default.fileExists(atPath: createdFile.path) }
        _ = find("instructions.beginCreation")
        check(try String(contentsOf: file, encoding: .utf8) == original, "Creation undo must preserve existing instructions")
        selectAgent(.codex)
        NSRunningApplication(processIdentifier: process.processIdentifier)?.activate(options: [])
        if let window = elements(app).first(where: { string($0, "AXRole") == "AXWindow" }) {
            _ = AXUIElementPerformAction(window, "AXRaise" as CFString)
        }
        let navigationButton = find("sidebar.instructions")
        var position = CGPoint.zero
        var size = CGSize.zero
        check(AXValueGetValue(value(navigationButton, "AXPosition") as! AXValue, .cgPoint, &position), "Read navigation button position")
        check(AXValueGetValue(value(navigationButton, "AXSize") as! AXValue, .cgSize, &size), "Read navigation button size")
        let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        let originalPointer = CGEvent(source: nil)!.location
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.2)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)!.post(tap: .cghidEventTap)
        try capture("button-pressed")
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)!.post(tap: .cghidEventTap)
        try capture("button-released")
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: originalPointer, mouseButton: .left)!.post(tap: .cghidEventTap)
        try Data().write(to: home.appendingPathComponent("capture"))
        wait("Instruction screenshots were not captured") { FileManager.default.fileExists(atPath: home.appendingPathComponent("capture.done").path) }
        print("PASS: persistent navigation, native agent picker, explicit nonempty creation, protected existing files, non-default destructive action, creation undo, draft navigation, reviewed save and restore; screenshots in /tmp/ahm-instructions-*.png")
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
        let controller = NSHostingController(rootView: ContentView().environment(store).frame(minWidth: 960, minHeight: 640))
        controller.sizingOptions = [.minSize]
        let view = controller.view
        // Match the app's full-size content window so SwiftUI reserves the toolbar inset.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.center(); window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        Task { @MainActor in
            @MainActor func snapshot(_ target: NSView, name: String) async {
                target.layoutSubtreeIfNeeded()
                if CGPreflightScreenCaptureAccess(), let targetWindow = target.window {
                    try? await Task.sleep(for: .milliseconds(300))
                    let capture = Process()
                    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    let output = URL(fileURLWithPath: "/tmp/ahm-instructions-" + name + "-window.png")
                    capture.arguments = ["-x", "-o", "-l", String(targetWindow.windowNumber), output.path]
                    do {
                        try capture.run(); capture.waitUntilExit()
                        if capture.terminationStatus == 0 {
                            try Data(contentsOf: output).write(to: URL(fileURLWithPath: "/tmp/ahm-instructions-" + name + ".png"))
                            return
                        }
                    }
                    catch { print("Window screenshot unavailable:", error.localizedDescription) }
                }
                if let bitmap = target.bitmapImageRepForCachingDisplay(in: target.bounds) {
                    target.cacheDisplay(in: target.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/ahm-instructions-" + name + ".png"))
                }
            }
            var captured = Set<String>()
            while !FileManager.default.fileExists(atPath: home.appendingPathComponent("capture").path) {
                for name in ["unsupported-cursor", "unsupported-devin", "missing", "creation-review", "button-pressed", "button-released"] where !captured.contains(name) {
                    if FileManager.default.fileExists(atPath: home.appendingPathComponent("capture." + name).path) {
                        await snapshot(window.sheets.first?.contentView ?? view, name: name)
                        captured.insert(name)
                        try? Data().write(to: home.appendingPathComponent("capture." + name + ".done"))
                    }
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua), ("compact", NSAppearance.Name.darkAqua)] {
                if name == "compact" {
                    window.setContentSize(NSSize(width: 960, height: 640))
                    view.layoutSubtreeIfNeeded()
                    let layout = window.contentLayoutRect.size
                    let content = window.contentView!.bounds.size
                    window.setContentSize(NSSize(width: content.width + max(0, 960 - layout.width),
                                                 height: content.height + max(0, 640 - layout.height)))
                }
                window.appearance = NSAppearance(named: appearance)
                try? await Task.sleep(for: .milliseconds(300))
                await snapshot(view, name: name)
                if name == "compact" { print("Compact layout:", view.bounds, window.contentLayoutRect, view.safeAreaInsets); fflush(stdout) }
            }
            try? Data().write(to: home.appendingPathComponent("capture.done"))
        }
        withExtendedLifetime((store, window)) { app.run() }
    }
}
