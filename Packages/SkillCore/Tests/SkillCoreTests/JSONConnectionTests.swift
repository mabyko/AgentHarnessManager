import Foundation
import XCTest
@testable import SkillCore

final class JSONConnectionTests: XCTestCase {
    private let targets: [AgentConnectionTarget] = [.antigravity, .opencode, .pi, .devin, .cursor]

    func testFirstInstallCreatesPrivateConfigurationOnlyAfterApproval() async throws {
        let fixture = try JSONConnectionFixture(); defer { fixture.remove() }
        for target in targets {
            let plan = try await fixture.plan(target)
            XCTAssertFalse(FileManager.default.fileExists(atPath: plan.configurationURL.path))
            let backup = try await fixture.installer.apply(plan, backupDirectory: fixture.backups)
            XCTAssertNil(backup)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: plan.configurationURL.path)[.posixPermissions] as? Int, 0o600)
            let status = try await fixture.installer.status(target: target, helperURL: fixture.helper, domain: "json.tests")
            XCTAssertEqual(status, .registered)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.canary.path))
    }

    func testConfigurationSelectionChangesAfterPreviewAreBlocked() async throws {
        let fixture = try JSONConnectionFixture(); defer { fixture.remove() }
        let plan = try await fixture.plan(.opencode)
        let different = plan.configurationURL.deletingLastPathComponent().appendingPathComponent("opencode.jsonc")
        let original = Data("{/* keep */}".utf8)
        try fixture.write(original, to: different)
        do { _ = try await fixture.installer.apply(plan, backupDirectory: fixture.backups); XCTFail("Changed configuration selection accepted") }
        catch AgentConnectionError.changed {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.configurationURL.path))
        XCTAssertEqual(try Data(contentsOf: different), original)
    }

    func testFiveAgentsInstallInspectAndRemoveWithoutLaunchingAnAgentOrChangingOtherSettings() async throws {
        let fixture = try JSONConnectionFixture(); defer { fixture.remove() }
        let installer = fixture.installer
        for target in targets {
            let initial = try await fixture.plan(target)
            XCTAssertTrue(initial.editsConfiguration)
            XCTAssertTrue(initial.arguments.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: initial.configurationURL.deletingLastPathComponent().path))
            let key = target == .opencode ? "mcp" : "mcpServers"
            let original = Data(((target == .opencode ? "// exact comment\n" : "") + "{ \"keep\" : \"untouched\", \"\(key)\": {\"other\": {\"command\": \"other\"}} }\n").utf8)
            try fixture.write(original, to: initial.configurationURL)
            let absent = try await installer.status(target: target, helperURL: fixture.helper, domain: "json.tests")
            XCTAssertEqual(absent, .notRegistered)
            let plan = try await fixture.plan(target)
            XCTAssertEqual(try Data(contentsOf: plan.configurationURL), original)
            XCTAssertFalse(plan.displayCommand.contains("untouched"), "Preview must not display unrelated private configuration")
            let backup = try await installer.apply(plan, backupDirectory: fixture.backups)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backup)), original)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: backup!.path)[.posixPermissions] as? Int, 0o600)
            let installed = try String(contentsOf: plan.configurationURL, encoding: .utf8)
            XCTAssertTrue(installed.contains("\"keep\" : \"untouched\""))
            if target == .opencode { XCTAssertTrue(installed.hasPrefix("// exact comment\n")) }
            let registered = try await installer.status(target: target, helperURL: fixture.helper, domain: "json.tests")
            XCTAssertEqual(registered, .registered)
            do { _ = try await fixture.plan(target); XCTFail("Repeated install overwrote registration") }
            catch AgentConnectionError.alreadyInstalled {}
            let removal = try await fixture.plan(target, removing: true)
            _ = try await installer.apply(removal, backupDirectory: fixture.backups)
            let remaining = try MCPConfiguration(Data(contentsOf: plan.configurationURL), comments: target == .opencode)
            XCTAssertNotNil(try remaining.server(in: key, named: "other"))
            XCTAssertNil(try remaining.server(in: key, named: AgentConnectionInstaller.serverName))
            let removed = try await installer.status(target: target, helperURL: fixture.helper, domain: "json.tests")
            XCTAssertEqual(removed, .notRegistered)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.canary.path), "Configuration management executed a process")
    }

    func testForeignRegistrationsAndStalePreviewsArePreservedForEveryNewAgent() async throws {
        let fixture = try JSONConnectionFixture(); defer { fixture.remove() }
        for target in targets {
            let config = try await fixture.plan(target).configurationURL
            let key = target == .opencode ? "mcp" : "mcpServers"
            let entry: [String: Any] = target == .opencode ? ["type": "local", "command": ["/foreign/tool"]] : ["command": "/foreign/tool", "args": []]
            let original = try JSONSerialization.data(withJSONObject: [key: [AgentConnectionInstaller.serverName: entry]])
            try fixture.write(original, to: config)
            for removing in [false, true] {
                do { _ = try await fixture.plan(target, removing: removing); XCTFail("Foreign entry accepted") }
                catch AgentConnectionError.conflict {}
            }
            XCTAssertEqual(try Data(contentsOf: config), original)
            try Data("{}".utf8).write(to: config)
            let plan = try await fixture.plan(target)
            let external = Data("{\"changed\":true}".utf8)
            try external.write(to: config)
            do { _ = try await fixture.installer.apply(plan, backupDirectory: fixture.backups); XCTFail("Stale preview accepted") }
            catch AgentConnectionError.changed {}
            XCTAssertEqual(try Data(contentsOf: config), external)
        }
    }

    func testJSONCCommentsTrailingCommasAndRemovalPositionsArePreserved() throws {
        let entry: [String: Any] = ["command": "owned", "args": []]
        for middle in ["\"owned\":{},\n// other comment\n\"other\":{}", "\"other\":{},\"owned\":{}", "\"owned\":{},", "\"owned\":{}"] {
            let original = Data(("{\"mcp\":{/* map comment */" + middle + "},\"keep\":\"💡 } // \\\"\"}").utf8)
            let removed = try MCPConfiguration(original, comments: true).replacing(in: "mcp", named: "owned", with: nil)
            XCTAssertNil(try MCPConfiguration(removed, comments: true).server(in: "mcp", named: "owned"))
            XCTAssertTrue(String(decoding: removed, as: UTF8.self).contains("/* map comment */"))
            if middle.contains("other comment") { XCTAssertTrue(String(decoding: removed, as: UTF8.self).contains("// other comment")) }
            let installed = try MCPConfiguration(removed, comments: true).replacing(in: "mcp", named: "owned", with: entry)
            XCTAssertEqual(try MCPConfiguration(installed, comments: true).server(in: "mcp", named: "owned")?["command"] as? String, "owned")
        }
        for invalid in ["{\"mcp\":{},\"mcp\":{}}", "{\"mcp\":{\"owned\":{},\"owned\":{}}}", "{\"mcp\":[]}"] {
            XCTAssertThrowsError(try MCPConfiguration(Data(invalid.utf8), comments: true).server(in: "mcp", named: "owned"))
        }
    }

    func testSymlinkedParentAndConfigChangesAfterPreviewDoNotReadOrWriteOutside() async throws {
        let fixture = try JSONConnectionFixture(); defer { fixture.remove() }
        let outside = fixture.home.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = outside.appendingPathComponent("mcp.json"), original = Data("{}".utf8)
        try original.write(to: sentinel)
        let parent = fixture.home.appendingPathComponent(".cursor")
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: outside)
        do { _ = try await fixture.plan(.cursor); XCTFail("Symlinked parent accepted") }
        catch AgentConnectionError.invalidConfiguration {}
        try FileManager.default.removeItem(at: parent)
        let plan = try await fixture.plan(.cursor)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: plan.configurationURL, withDestinationURL: sentinel)
        do { _ = try await fixture.installer.apply(plan, backupDirectory: fixture.backups); XCTFail("Config symlink accepted") }
        catch AgentConnectionError.invalidConfiguration {}
        XCTAssertEqual(try Data(contentsOf: sentinel), original)
    }

    func testExistingJSONCAndLegacyConfigurationsAndEnvironmentOverrides() async throws {
        let fixture = try JSONConnectionFixture(); defer { fixture.remove() }
        let jsonc = fixture.home.appendingPathComponent(".config/opencode/opencode.jsonc")
        try fixture.write(Data("{/* keep */ \"mcp\": {}}".utf8), to: jsonc)
        let opencode = try await fixture.plan(.opencode)
        XCTAssertEqual(opencode.configurationURL, jsonc)
        try Data("{}".utf8).write(to: jsonc.deletingLastPathComponent().appendingPathComponent("opencode.json"))
        do { _ = try await fixture.plan(.opencode); XCTFail("Ambiguous files accepted") }
        catch AgentConnectionError.ambiguousConfiguration {}
        let antigravity = fixture.home.appendingPathComponent(".gemini/antigravity/mcp_config.json")
        try fixture.write(Data("{}".utf8), to: antigravity)
        let legacyAntigravity = try await fixture.plan(.antigravity)
        XCTAssertEqual(legacyAntigravity.configurationURL, antigravity)
        let devin = fixture.home.appendingPathComponent(".config/devin/config.json")
        try fixture.write(Data("{\"mcpServers\":{},\"keep\":true}".utf8), to: devin)
        let legacyDevin = try await fixture.plan(.devin)
        XCTAssertEqual(legacyDevin.configurationURL, devin)
        let custom = AgentConnectionInstaller(home: fixture.home, environment: ["PI_CODING_AGENT_DIR": fixture.home.appendingPathComponent("custom-pi").path, "OPENCODE_CONFIG": fixture.home.appendingPathComponent("custom-open.jsonc").path])
        let pi = try await custom.prepare(target: .pi, removing: false, helperURL: fixture.helper, domain: "json.tests")
        XCTAssertEqual(pi.configurationURL, fixture.home.appendingPathComponent("custom-pi/mcp.json"))
        let open = try await custom.prepare(target: .opencode, removing: false, helperURL: fixture.helper, domain: "json.tests")
        XCTAssertEqual(open.configurationURL, fixture.home.appendingPathComponent("custom-open.jsonc"))
    }

    func testDisabledOwnedRegistrationIsReportedAndModifiedInvocationIsNotRemoved() async throws {
        let fixture = try JSONConnectionFixture(); defer { fixture.remove() }
        let plan = try await fixture.plan(.pi)
        let entry: [String: Any] = ["command": fixture.helper.path, "args": ["--domain", "json.tests", "mcp"], "enabled": false]
        try fixture.write(try JSONSerialization.data(withJSONObject: ["mcpServers": [AgentConnectionInstaller.serverName: entry]]), to: plan.configurationURL)
        let status = try await fixture.installer.status(target: .pi, helperURL: fixture.helper, domain: "json.tests")
        XCTAssertEqual(status, .disabled)
        var changed = entry; changed["env"] = ["EXTRA": "fixture"]
        let data = try JSONSerialization.data(withJSONObject: ["mcpServers": [AgentConnectionInstaller.serverName: changed]])
        try data.write(to: plan.configurationURL)
        do { _ = try await fixture.plan(.pi, removing: true); XCTFail("Modified invocation was removed") }
        catch AgentConnectionError.conflict {}
        XCTAssertEqual(try Data(contentsOf: plan.configurationURL), data)
    }
}

private struct JSONConnectionFixture {
    let home: URL
    var helper: URL { home.appendingPathComponent("ahm") }
    var canary: URL { home.appendingPathComponent("executed") }
    var backups: URL { home.appendingPathComponent("backups") }
    var installer: AgentConnectionInstaller { AgentConnectionInstaller(home: home, environment: [:]) }
    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("ahm-json-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try "#!/bin/sh\ntouch '\(canary.path)'\nexit 1\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    }
    func plan(_ target: AgentConnectionTarget, removing: Bool = false) async throws -> AgentConnectionPlan {
        try await installer.prepare(target: target, removing: removing, helperURL: helper, domain: "json.tests")
    }
    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
}
