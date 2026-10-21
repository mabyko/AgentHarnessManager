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
        let home = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("home")
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
        func wait(_ message: String, timeout: TimeInterval = 5, _ predicate: () -> Bool) {
            let deadline = Date().addingTimeInterval(timeout)
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
        func expectHeading(_ title: String) {
            wait("Missing destination heading: " + title) {
                elements(find("workbench.listTitle")).contains { element in
                    ["AXValue", "AXTitle", "AXDescription"].contains { string(element, $0) == title }
                }
            }
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
            let installed = [.codex, .opencode].contains(target)
            check(children.contains { string($0, "AXDescription") == target.name && string($0, "AXValue").contains(installed ? "CLI 설치 감지됨" : "미설치") })
            for action in ["install", "remove"] {
                let button = find("agent.connection." + action + "." + target.rawValue)
                check(string(button, "AXRole") == "AXButton" && string(button, "AXDescription").contains(target.name))
                let enabled = action == "install" ? installed : (!target.requiresCLIForConnection || installed)
                check((value(button, "AXEnabled") as? Bool) == enabled, "Installation status must control button availability: " + target.rawValue + "." + action)
                if enabled {
                    var actions: CFArray?
                    check(AXUIElementCopyActionNames(button, &actions) == .success && (actions as? [String] ?? []).contains("AXPress"))
                }
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
        _ = AXUIElementSetAttributeValue(library, "AXMain" as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: process.processIdentifier)!.activate()
        Thread.sleep(forTimeInterval: 0.3)
        let navigation = ["sidebar.skills", "sidebar.instructions", "sidebar.activity"]
        let navigationLabels = ["스킬 라이브러리", "전역 지침", "활동 이력"]
        let sidebarIDs = Set(elements(library).map { string($0, "AXIdentifier") }.filter { $0.hasPrefix("sidebar.") })
        check(sidebarIDs == Set(navigation), "Sidebar must expose only three task destinations: \(sidebarIDs)")
        for (id, label) in zip(navigation, navigationLabels) {
            let row = find(id)
            let role = string(row, "AXRole")
            let title = string(row, "AXTitle")
            let description = string(row, "AXDescription")
            check(role == "AXButton" && (title.contains(label) || description.contains(label)),
                  "Task navigation must be a named native button: \(id), expected=\(label), role=\(role), title=\(title), description=\(description)")
        }
        check(!elements(library).contains { string($0, "AXRole") == "AXButton" && string($0, "AXDescription") == "새 그룹" }, "New group belongs to its section header, outside the task sidebar")
        focus(find("sidebar.skills"))
        key(48)
        check(focusedID() == "sidebar.instructions", "Tab must reach global instructions; focused=" + focusedID())
        key(48)
        check(focusedID() == "sidebar.activity", "Tab must reach activity; focused=" + focusedID())
        key(48, flags: .maskShift)
        check(focusedID() == "sidebar.instructions", "Shift-Tab must return to instructions")
        key(49)
        _ = find("instructions.agentPicker")
        expectHeading("전역 지침")

        func press(_ id: String, expecting nextID: String? = nil) {
            let result = AXUIElementPerformAction(find(id), "AXPress" as CFString)
            if let nextID { _ = find(nextID) }
            else { check(result == .success, "Cannot activate " + id) }
        }
        func selectSegment(_ id: String, _ title: String) {
            var segment: AXUIElement?
            wait("Missing native segment: " + title) {
                segment = elements(find(id)).first { element in
                    ["AXRadioButton", "AXButton"].contains(string(element, "AXRole")) &&
                    ["AXTitle", "AXDescription"].contains { key in string(element, key) == title }
                }
                return segment != nil
            }
            _ = AXUIElementPerformAction(segment!, "AXPress" as CFString)
            Thread.sleep(forTimeInterval: 0.15)
        }
        func selectMenu(_ id: String, _ title: String) {
            press(id)
            var item: AXUIElement?
            wait("Missing native filter option: " + title) {
                item = elements(app).first { string($0, "AXRole") == "AXMenuItem" && string($0, "AXTitle") == title }
                return item != nil
            }
            _ = AXUIElementPerformAction(item!, "AXPress" as CFString)
            wait("Filter did not select: " + title) { string(find(id), "AXValue").contains(title) }
        }
        func expectText(_ text: String) {
            wait("Missing section description: " + text) { elements(library).contains { string($0, "AXValue").contains(text) } }
        }
        press("sidebar.activity", expecting: "workbench.activitySection")
        expectHeading("활동 이력")
        for (segment, description) in [("요청", "에이전트가 제안한 변경"), ("변경", "완료 기록 최근"), ("검사 이력", "로컬 검사 이력")] {
            selectSegment("workbench.activitySection", segment)
            expectText(description)
            expectHeading("활동 이력")
        }
        press("sidebar.skills", expecting: "workbench.skillSection")
        selectSegment("workbench.skillSection", "그룹")
        let newGroup = find("groups.new")
        check(string(newGroup, "AXRole") == "AXButton", "New group must be a native header button")
        focus(newGroup); key(49)
        wait("Keyboard action did not open the group sheet") { elements(app).contains { string($0, "AXRole") == "AXSheet" } }
        wait("Group name field did not receive focus") {
            guard let element = value(app, "AXFocusedUIElement") else { return false }
            return string(element as! AXUIElement, "AXRole") == "AXTextField"
        }
        key(53)
        wait("Escape did not dismiss the group sheet") { !elements(app).contains { string($0, "AXRole") == "AXSheet" } }
        selectSegment("workbench.skillSection", "검사 결과")
        expectText("로컬 검사 ·")
        selectSegment("workbench.skillSection", "스킬")
        _ = find("library.scope")
        press("library.filters")
        press("library.agent")
        wait("Installed agent filter options did not open") { elements(app).contains { string($0, "AXRole") == "AXMenuItem" && string($0, "AXTitle") == "Codex" } }
        let agentOptions = elements(app).filter { string($0, "AXRole") == "AXMenuItem" }.map { string($0, "AXTitle") }
        check(agentOptions.contains("Codex") && agentOptions.contains("OpenCode"), "Installed agents must appear in the filter menu")
        check(!agentOptions.contains { $0.contains("Claude Code") }, "Uninstalled agents must not appear in the filter menu")
        key(53)
        selectMenu("library.agent", "Codex")
        selectMenu("library.group", "Keyboard group")
        check(string(find("library.agent"), "AXValue").contains("Codex"), "Selecting a group must preserve the agent filter")
        expectText("keyboard-demo")
        check((value(find("library.clearFilters"), "AXEnabled") as? Bool) == true, "Combined filters must expose reset")
        press("library.clearFilters")
        wait("Combined filters did not clear") {
            string(find("library.agent"), "AXValue").contains("모든 에이전트") &&
            string(find("library.group"), "AXValue").contains("모든 그룹") &&
            (value(find("library.clearFilters"), "AXEnabled") as? Bool) == false
        }
        key(53)
        press("library.install", expecting: "library.installRoot")
        wait("Install action must open a native sheet") { elements(app).contains { string($0, "AXRole") == "AXSheet" } }
        let checksGitHub = ProcessInfo.processInfo.environment["AHM_CHECK_GITHUB"] == "1"
        if checksGitHub {
            check(AXUIElementSetAttributeValue(find("library.githubURL"), "AXValue" as CFString,
                "https://github.com/mattpocock/skills" as CFString) == .success, "Repository field must accept a GitHub URL")
            press("library.loadGitHub")
            var row: AXUIElement?
            wait("GitHub skill list did not load", timeout: 20) {
                row = elements(app).first { element in
                    string(element, "AXRole") == "AXRow" && elements(element).contains { string($0, "AXValue") == "codebase-design" }
                }
                return row != nil
            }
            check(AXUIElementSetAttributeValue(row!, "AXSelected" as CFString, kCFBooleanTrue) == .success, "GitHub skill must be selectable")
            wait("Selected GitHub skill must enable installation review") { (value(find("library.prepareInstall"), "AXEnabled") as? Bool) == true }
        }
        try Data().write(to: home.appendingPathComponent("capture.install"))
        wait("Install sheet was not captured") { FileManager.default.fileExists(atPath: home.appendingPathComponent("capture.install.done").path) }
        if checksGitHub {
            press("library.prepareInstall")
            wait("GitHub install must reach the final review sheet", timeout: 20) {
                elements(app).contains { string($0, "AXIdentifier") == "library.applyChange" }
            }
            check(elements(app).contains { string($0, "AXValue").contains("출처: https://github.com/mattpocock/skills") }, "Review must show the GitHub source")
        }
        key(53)
        wait("Escape must cancel installation") { !elements(app).contains { string($0, "AXRole") == "AXSheet" } }
        try Data().write(to: home.appendingPathComponent("capture.layout"))
        wait("Workbench layout screenshots were not captured") { FileManager.default.fileExists(atPath: home.appendingPathComponent("capture.layout.done").path) }
        print("PASS: native AX agent names/states and actions; task-only sidebar Tab/Shift-Tab/Space; segmented skills/instructions/activity navigation; installed-agent and combined group filters/reset; group/install-sheet focus/Escape; optional GitHub selection/download/review; full-window layout captures in /tmp/ahm-workbench-layout-*.png")
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
        for path in [".claude/skills/keyboard-demo", ".grok/skills/keyboard-demo"] {
            let link = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home.appendingPathComponent(".agents/skills/keyboard-demo"))
        }
        let defaults = UserDefaults(suiteName: suite)!
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for name in ["codex", "opencode"] {
            let executable = bin.appendingPathComponent(name)
            try Data("#!/bin/sh\nexit 99\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }
        let store = AppStore(defaults: defaults, home: home,
                             installationDetector: AgentInstallationDetector(executableDirectories: [bin], applicationDirectories: []), instructionEnvironment: [:])
        func window<V: View>(_ root: V, id: String, size: NSSize) -> NSWindow {
            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.setAccessibilityIdentifier(id)
            let controller = NSHostingController(rootView: root.environment(store))
            controller.sizingOptions = [.minSize]
            window.contentViewController = controller
            window.setContentSize(size)
            window.makeKeyAndOrderFront(nil)
            return window
        }
        let library = window(ContentView().frame(minWidth: 960, minHeight: 640), id: "a11y.library", size: NSSize(width: 1280, height: 800))
        let settings = window(SettingsView(), id: "a11y.settings", size: NSSize(width: 900, height: 900))
        app.activate(ignoringOtherApps: true)
        Task { @MainActor in
            await store.rescan()
            while store.isScanning || !store.hasScanned { try? await Task.sleep(for: .milliseconds(50)) }
            guard let skill = store.skills.first(where: { $0.name == "keyboard-demo" }),
                  store.saveGroup(SkillGroup(name: "Keyboard group", skillIDs: [skill.id])) else {
                fputs("FAIL: Could not seed the isolated keyboard group\n", stderr); exit(1)
            }
            while !FileManager.default.fileExists(atPath: home.appendingPathComponent("capture.layout").path) {
                if FileManager.default.fileExists(atPath: home.appendingPathComponent("capture.install").path),
                   !FileManager.default.fileExists(atPath: home.appendingPathComponent("capture.install.done").path),
                   let sheet = library.attachedSheet, let view = sheet.contentView {
                    let output = URL(fileURLWithPath: "/tmp/ahm-skill-install.png")
                    var captured = false
                    if CGPreflightScreenCaptureAccess() {
                        let capture = Process()
                        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                        capture.arguments = ["-x", "-o", "-l", String(sheet.windowNumber), output.path]
                        do { try capture.run(); capture.waitUntilExit(); captured = capture.terminationStatus == 0 }
                        catch { print("Sheet screenshot unavailable:", error.localizedDescription) }
                    }
                    if !captured, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        try? bitmap.representation(using: .png, properties: [:])?.write(to: output)
                    }
                    try? Data().write(to: home.appendingPathComponent("capture.install.done"))
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            store.selectedSkillID = store.filteredSkills.first?.id
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua), ("compact", NSAppearance.Name.darkAqua)] {
                library.appearance = NSAppearance(named: appearance)
                if name == "compact" {
                    library.setContentSize(NSSize(width: 960, height: 640))
                    library.contentView?.layoutSubtreeIfNeeded()
                    let layout = library.contentLayoutRect.size
                    let content = library.contentView!.bounds.size
                    library.setContentSize(NSSize(width: content.width + max(0, 960 - layout.width),
                                                  height: content.height + max(0, 640 - layout.height)))
                }
                library.makeKeyAndOrderFront(nil)
                library.contentView?.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(300))
                let output = URL(fileURLWithPath: "/tmp/ahm-workbench-layout-" + name + ".png")
                if CGPreflightScreenCaptureAccess() {
                    let capture = Process()
                    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    capture.arguments = ["-x", "-o", "-l", String(library.windowNumber), output.path]
                    do {
                        try capture.run(); capture.waitUntilExit()
                        if capture.terminationStatus == 0 { continue }
                    }
                    catch { print("Window screenshot unavailable:", error.localizedDescription) }
                }
                if let view = library.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: output)
                }
            }
            try? Data().write(to: home.appendingPathComponent("capture.layout.done"))
        }
        withExtendedLifetime((library, settings)) { app.run() }
    }
}
